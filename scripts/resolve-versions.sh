#!/usr/bin/env bash
#
# Resolve the current release inputs and compute the build id and release tag.
#
# Writes KEY=VALUE lines to $VERSIONS_FILE (default: versions.env) and, when
# running in GitHub Actions, to $GITHUB_OUTPUT. See docs/release-pipeline.md.
#
# Requires: bash, curl, git, sha256sum, gh.

set -euo pipefail

GH=${GH:-gh}
VERSIONS_FILE=${VERSIONS_FILE:-versions.env}
ALPINE_RELEASES_URL=${ALPINE_RELEASES_URL:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

for cmd in curl git sha256sum "$GH"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing command: $cmd"
done

# ---------------------------------------------------------------------------
# Alpine release and package-index hash
# ---------------------------------------------------------------------------
log "resolving Alpine release"
alpine_yaml=$(curl -fsSL "$ALPINE_RELEASES_URL")
alpine_version=$(printf '%s\n' "$alpine_yaml" | awk '$1 == "version:" { print $2; exit }')
alpine_branch=$(printf '%s\n' "$alpine_yaml" | awk '$1 == "branch:" { print $2; exit }')
[ -n "$alpine_version" ] || die "could not parse version from $ALPINE_RELEASES_URL"
[ -n "$alpine_branch" ] || die "could not parse branch from $ALPINE_RELEASES_URL"

apkindex_hash=$(
    {
        curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/${alpine_branch}/main/x86_64/APKINDEX.tar.gz"
        curl -fsSL "https://dl-cdn.alpinelinux.org/alpine/${alpine_branch}/community/x86_64/APKINDEX.tar.gz"
    } | sha256sum | cut -c1-7
)
[ -n "$apkindex_hash" ] || die "could not hash APKINDEX archives"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
fetch_conandata() {
    curl -fsSL "https://raw.githubusercontent.com/Ultimaker/$1/$2/conandata.yml"
}

# Print the version declared by a repository's conandata.yml at a ref.
conandata_version() {
    fetch_conandata "$1" "$2" 2>/dev/null \
        | sed -n 's/^version:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' \
        | head -n1
}

# Print the first "<name>/<version>" requirement from a conandata.yml.
requirement() {
    local name=$1 version
    version=$(printf '%s\n' "$conandata" \
        | sed -n "s/.*\"${name}\/\([^\"]*\)\".*/\1/p" \
        | head -n1)
    printf '%s' "${version%%@*}"
}

# Use the exact tag when it exists; otherwise the head of the default branch.
resolve_ref() {
    local repo=$1 version=$2 ref
    if [ -n "$version" ] && git ls-remote --tags --refs "https://github.com/Ultimaker/$repo" "refs/tags/$version" 2>/dev/null | grep -q .; then
        printf '%s' "$version"
        return
    fi
    ref=$(git ls-remote "https://github.com/Ultimaker/$repo" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }')
    [ -n "$ref" ] || die "could not resolve $repo $version"
    printf '%s' "$ref"
}

check_conandata() {
    local repo=$1 ref=$2 expected=$3 got
    [ -n "$expected" ] || return 0
    got=$(conandata_version "$repo" "$ref")
    if [ "$got" != "$expected" ]; then
        die "$repo at $ref declares '${got:-nothing}', expected '$expected'"
    fi
}

# Latest released tag for a non-UltiMaker source dependency. Prefer the GitHub
# release tag, but use the newest git tag when it is newer than the latest
# release (mapbox/wagyu publishes 0.5.0 as a tag while releases/latest reports
# 0.2.1, and CuraEngine requires 0.5.0).
latest_source_ref() {
    local repo=$1 release highest newest
    release=$("$GH" api "repos/$repo/releases/latest" --jq .tag_name 2>/dev/null || true)
    highest=$(git ls-remote --tags --refs "https://github.com/$repo" 2>/dev/null \
        | sed 's#.*refs/tags/##' | sort -V | tail -n1)
    if [ -n "$release" ] && [ "$release" != "null" ]; then
        if [ -n "$highest" ] && [ "$highest" != "$release" ]; then
            newest=$(printf '%s\n%s\n' "$release" "$highest" | sort -V | tail -n1)
            if [ "$newest" = "$highest" ]; then
                log "note: $repo latest release is $release; newest tag is $highest"
                printf '%s' "$highest"
                return
            fi
        fi
        printf '%s' "$release"
        return
    fi
    [ -n "$highest" ] || die "could not resolve latest release for $repo"
    printf '%s' "$highest"
}

# ---------------------------------------------------------------------------
# Cura and its dependency chain
# ---------------------------------------------------------------------------
log "resolving Cura release"
cura_tag=$("$GH" api repos/UltiMaker/Cura/releases/latest --jq .tag_name)
[ -n "$cura_tag" ] && [ "$cura_tag" != "null" ] || die "could not resolve the Cura release tag"
cura_version=${cura_tag#v}

log "reading Cura $cura_tag conandata"
conandata=$(fetch_conandata Cura "$cura_tag")
uranium_version=$(requirement uranium)
curaengine_version=$(requirement curaengine)
fdm_materials_version=$(requirement fdm_materials)
pynest2d_version=$(requirement pynest2d)
pysavitar_version=$(requirement pysavitar)
dulcificum_version=$(requirement dulcificum)
[ -n "$uranium_version" ] || die "Cura conandata has no uranium requirement"
[ -n "$curaengine_version" ] || die "Cura conandata has no curaengine requirement"
[ -n "$fdm_materials_version" ] || die "Cura conandata has no fdm_materials requirement"
[ -n "$pynest2d_version" ] || die "Cura conandata has no pynest2d requirement"
[ -n "$pysavitar_version" ] || die "Cura conandata has no pysavitar requirement"
[ -n "$dulcificum_version" ] || die "Cura conandata has no dulcificum requirement"

uranium_ref=$(resolve_ref Uranium "$uranium_version")
curaengine_ref=$(resolve_ref CuraEngine "$curaengine_version")
fdm_materials_ref=$(resolve_ref fdm_materials "$fdm_materials_version")
pynest2d_ref=$(resolve_ref pynest2d "$pynest2d_version")
pysavitar_ref=$(resolve_ref pySavitar "$pysavitar_version")
dulcificum_ref=$(resolve_ref synsepalum-dulcificum "$dulcificum_version")

check_conandata Uranium "$uranium_ref" "$uranium_version"
check_conandata CuraEngine "$curaengine_ref" "$curaengine_version"
check_conandata fdm_materials "$fdm_materials_ref" "$fdm_materials_version"
check_conandata pynest2d "$pynest2d_ref" "$pynest2d_version"
check_conandata pySavitar "$pysavitar_ref" "$pysavitar_version"
check_conandata synsepalum-dulcificum "$dulcificum_ref" "$dulcificum_version"

log "reading pySavitar $pysavitar_ref conandata"
conandata=$(fetch_conandata pySavitar "$pysavitar_ref")
libsavitar_version=$(requirement savitar)
[ -n "$libsavitar_version" ] || die "pySavitar conandata has no savitar requirement"

libsavitar_ref=$(resolve_ref libSavitar "$libsavitar_version")
check_conandata libSavitar "$libsavitar_ref" "$libsavitar_version"

# Dulcificum's conanfile pins ctre/3.7.2. Alpine 3.24 does not package it, so the
# header-only library is built from source; keep the ref explicit.
ctre_ref="v3.7.2"

log "reading Uranium $uranium_ref conandata"
conandata=$(fetch_conandata Uranium "$uranium_ref")
pyarcus_version=$(requirement pyarcus)
libuvula_version=$(requirement uvula)
[ -n "$pyarcus_version" ] || die "Uranium conandata has no pyarcus requirement"
[ -n "$libuvula_version" ] || die "Uranium conandata has no uvula requirement"

pyarcus_ref=$(resolve_ref pyArcus "$pyarcus_version")
libuvula_ref=$(resolve_ref libUvula "$libuvula_version")
check_conandata pyArcus "$pyarcus_ref" "$pyarcus_version"
check_conandata libUvula "$libuvula_ref" "$libuvula_version"

log "reading CuraEngine $curaengine_ref conandata"
conandata=$(fetch_conandata CuraEngine "$curaengine_ref")
libarcus_version=$(requirement arcus)
curaformulae_version=$(requirement cura-formulae-engine)
[ -n "$libarcus_version" ] || die "CuraEngine conandata has no arcus requirement"
[ -n "$curaformulae_version" ] || die "CuraEngine conandata has no cura-formulae-engine requirement"

libarcus_ref=$(resolve_ref libArcus "$libarcus_version")
curaformulae_ref=$(resolve_ref CuraFormulaeEngine "$curaformulae_version")
check_conandata libArcus "$libarcus_ref" "$libarcus_version"
check_conandata CuraFormulaeEngine "$curaformulae_ref" "$curaformulae_version"

# libnest2d and Scripta have no usable tags. Use their main branches and let the
# build-time version checks catch an incompatible tree.
libnest2d_ref=$(resolve_ref libnest2d "")
scripta_ref=$(resolve_ref Scripta_public "")

# Non-UltiMaker dependencies are built from source too, so use their latest
# release tags and include them in the hash.
zeus_ref=$(latest_source_ref zeus-cpp/expected)
lexy_ref=$(latest_source_ref foonathan/lexy)
geometry_ref=$(latest_source_ref mapbox/geometry.hpp)
wagyu_ref=$(latest_source_ref mapbox/wagyu)

# ---------------------------------------------------------------------------
# Dependency hash, build id and release tag
# ---------------------------------------------------------------------------
deps_hash=$(
    printf '%s\n' \
        "uranium=${uranium_ref}" \
        "curaengine=${curaengine_ref}" \
        "fdm_materials=${fdm_materials_ref}" \
        "pynest2d=${pynest2d_ref}" \
        "libarcus=${libarcus_ref}" \
        "pyarcus=${pyarcus_ref}" \
        "libsavitar=${libsavitar_ref}" \
        "pysavitar=${pysavitar_ref}" \
        "dulcificum=${dulcificum_ref}" \
        "ctre=${ctre_ref}" \
        "libnest2d=${libnest2d_ref}" \
        "libuvula=${libuvula_ref}" \
        "curaformulae=${curaformulae_ref}" \
        "scripta=${scripta_ref}" \
        "zeus=${zeus_ref}" \
        "lexy=${lexy_ref}" \
        "geometry=${geometry_ref}" \
        "wagyu=${wagyu_ref}" \
        | sha256sum | cut -c1-7
)

# The run number exists only in the git tag: it keeps successive builds of the
# same Cura version in run order when tags are sorted, which the random hashes
# cannot do. Artifact names, image tags, SOURCES-*.txt and the release title use
# the build id, so identical inputs keep identical file names.
run_number=${RUN_NUMBER:-${GITHUB_RUN_NUMBER:-0}}
build_id="${cura_tag}-${deps_hash}-alpine-${alpine_version}-${apkindex_hash}"
release_tag="${cura_tag}-${run_number}-${deps_hash}-alpine-${alpine_version}-${apkindex_hash}"
alpine_image="alpine:${alpine_version}"

cat > "$VERSIONS_FILE" <<EOF
CURA_TAG=${cura_tag}
CURA_VERSION=${cura_version}
URANIUM_REF=${uranium_ref}
CURAENGINE_REF=${curaengine_ref}
CURAENGINE_VERSION=${curaengine_version}
FDM_MATERIALS_REF=${fdm_materials_ref}
LIBARCUS_REF=${libarcus_ref}
LIBARCUS_VERSION=${libarcus_version}
PYARCUS_REF=${pyarcus_ref}
PYSAVITAR_REF=${pysavitar_ref}
PYSAVITAR_VERSION=${pysavitar_version}
LIBSAVITAR_REF=${libsavitar_ref}
LIBSAVITAR_VERSION=${libsavitar_version}
DULCIFICUM_REF=${dulcificum_ref}
DULCIFICUM_VERSION=${dulcificum_version}
CTRE_REF=${ctre_ref}
PYNEST2D_REF=${pynest2d_ref}
LIBNEST2D_REF=${libnest2d_ref}
LIBUVULA_REF=${libuvula_ref}
LIBUVULA_VERSION=${libuvula_version}
CURAFORMULAE_REF=${curaformulae_ref}
CURAFORMULAE_VERSION=${curaformulae_version}
SCRIPTA_REF=${scripta_ref}
ZEUS_REF=${zeus_ref}
LEXY_REF=${lexy_ref}
GEOMETRY_REF=${geometry_ref}
WAGYU_REF=${wagyu_ref}
ALPINE_VERSION=${alpine_version}
ALPINE_BRANCH=${alpine_branch}
ALPINE_IMAGE=${alpine_image}
APKINDEX_HASH=${apkindex_hash}
DEPS_HASH=${deps_hash}
RUN_NUMBER=${run_number}
BUILD_ID=${build_id}
RELEASE_TAG=${release_tag}
EOF

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    cat "$VERSIONS_FILE" >> "$GITHUB_OUTPUT"
fi

log "Cura:        ${cura_tag}"
log "Alpine:      ${alpine_version} (${alpine_branch}), APKINDEX ${apkindex_hash}"
log "Deps hash:   ${deps_hash}"
log "Run number:  ${run_number}"
log "Build id:    ${build_id}"
log "Release tag: ${release_tag}"

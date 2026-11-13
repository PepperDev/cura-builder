#!/usr/bin/env bash
#
# Build the image from a resolved versions.env and export the release tarball.
# See docs/release-plan.md.
#
# Requires: bash, docker, sha256sum, tar (in the image).

set -euo pipefail

VERSIONS_FILE=${VERSIONS_FILE:-versions.env}
DIST_DIR=${DIST_DIR:-dist}
PLATFORM=${PLATFORM:-linux/amd64}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

[ -f "$VERSIONS_FILE" ] || die "missing $VERSIONS_FILE; run scripts/resolve-versions.sh first"
# shellcheck disable=SC1090
. "$VERSIONS_FILE"

for var in CURA_TAG CURA_VERSION URANIUM_REF CURAENGINE_REF CURAENGINE_VERSION \
           FDM_MATERIALS_REF LIBARCUS_REF LIBARCUS_VERSION PYARCUS_REF \
           PYNEST2D_REF LIBNEST2D_REF LIBUVULA_REF LIBUVULA_VERSION \
           CURAFORMULAE_REF CURAFORMULAE_VERSION SCRIPTA_REF ZEUS_REF LEXY_REF \
           GEOMETRY_REF WAGYU_REF ALPINE_IMAGE RELEASE_TAG; do
    [ -n "${!var:-}" ] || die "$var is not set in $VERSIONS_FILE"
done

command -v docker >/dev/null 2>&1 || die "missing command: docker"

image="cura-alpine:${RELEASE_TAG}"
tarball_name="cura-${RELEASE_TAG}-linux-x86_64.tar.gz"
tarball="$DIST_DIR/$tarball_name"

mkdir -p "$DIST_DIR"

log "building $image for $PLATFORM"
docker build \
    --platform "$PLATFORM" \
    --build-arg ALPINE_IMAGE="$ALPINE_IMAGE" \
    --build-arg CURA_REF="$CURA_TAG" \
    --build-arg CURA_VERSION="$CURA_VERSION" \
    --build-arg URANIUM_REF="$URANIUM_REF" \
    --build-arg CURAENGINE_REF="$CURAENGINE_REF" \
    --build-arg CURAENGINE_VERSION="$CURAENGINE_VERSION" \
    --build-arg FDM_MATERIALS_REF="$FDM_MATERIALS_REF" \
    --build-arg LIBARCUS_REF="$LIBARCUS_REF" \
    --build-arg LIBARCUS_VERSION="$LIBARCUS_VERSION" \
    --build-arg PYARCUS_REF="$PYARCUS_REF" \
    --build-arg PYNEST2D_REF="$PYNEST2D_REF" \
    --build-arg LIBNEST2D_REF="$LIBNEST2D_REF" \
    --build-arg LIBUVULA_REF="$LIBUVULA_REF" \
    --build-arg LIBUVULA_VERSION="$LIBUVULA_VERSION" \
    --build-arg CURAFORMULAE_REF="$CURAFORMULAE_REF" \
    --build-arg CURAFORMULAE_VERSION="$CURAFORMULAE_VERSION" \
    --build-arg SCRIPTA_REF="$SCRIPTA_REF" \
    --build-arg ZEUS_REF="$ZEUS_REF" \
    --build-arg LEXY_REF="$LEXY_REF" \
    --build-arg GEOMETRY_REF="$GEOMETRY_REF" \
    --build-arg WAGYU_REF="$WAGYU_REF" \
    -t "$image" \
    .

# ---------------------------------------------------------------------------
# Export the allowlisted build outputs
# ---------------------------------------------------------------------------
log "exporting $tarball_name"
container="cura-export-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT

# Required paths fail the export when missing. Optional globs are expanded
# inside the container and skipped when a component is not installed.
read -r -d '' export_script <<'EOS' || true
set -eu
cd /

required="
usr/bin/cura
usr/bin/CuraEngine
usr/lib/cura
usr/lib/uranium
usr/share/cura
usr/share/uranium
usr/share/locale
usr/share/licenses/cura-alpine
usr/lib/python3.14/site-packages/UM
usr/lib/python3.14/site-packages/cura
usr/lib/python3.14/site-packages/pyArcus.so
usr/lib/python3.14/site-packages/pyArcus.pyi
usr/lib/python3.14/site-packages/stl
usr/lib/python3.14/site-packages/trimesh
usr/lib/python3.14/site-packages/python_utils
usr/lib/python3.14/site-packages/typing_extensions.py
"
for f in $required; do
    if [ ! -e "$f" ]; then
        echo "missing required export path: $f" >&2
        exit 1
    fi
done

list=/tmp/export-list
: > "$list"
for p in $required \
         'usr/lib/libArcus.so*' \
         'usr/lib/libcura-formulae-engine.so*' \
         'usr/lib/python3.14/site-packages/pynest2d*' \
         'usr/lib/python3.14/site-packages/pyUvula*' \
         'usr/lib/python3.14/site-packages/numpy_stl*'; do
    for f in $p; do
        [ -e "$f" ] || continue
        echo "$f" >> "$list"
    done
done

tar czf /tmp/artifacts.tar.gz -T "$list"
EOS

docker create --name "$container" --entrypoint /bin/sh "$image" -c "$export_script" >/dev/null
docker start "$container" >/dev/null
status=$(docker wait "$container")
[ "$status" = "0" ] || die "export container failed with status $status"
docker cp "$container:/tmp/artifacts.tar.gz" "$tarball"

(
    cd "$DIST_DIR"
    sha256sum "$tarball_name" > "$tarball_name.sha256"
)

# ---------------------------------------------------------------------------
# Source offer and release notes
# ---------------------------------------------------------------------------
sources="$DIST_DIR/SOURCES-${RELEASE_TAG}.txt"
{
    printf 'Cura %s build inputs\n' "$CURA_TAG"
    printf 'Generated: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%-24s %-44s %s\n' "Component" "Ref" "Source archive"
    printf '%-24s %-44s %s\n' "---------" "---" "--------------"
    printf '%-24s %-44s %s\n' "Cura" "$CURA_TAG" "https://github.com/Ultimaker/Cura/archive/${CURA_TAG}.tar.gz"
    printf '%-24s %-44s %s\n' "Uranium" "$URANIUM_REF" "https://github.com/Ultimaker/Uranium/archive/${URANIUM_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "CuraEngine" "$CURAENGINE_REF" "https://github.com/Ultimaker/CuraEngine/archive/${CURAENGINE_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "fdm_materials" "$FDM_MATERIALS_REF" "https://github.com/Ultimaker/fdm_materials/archive/${FDM_MATERIALS_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "libArcus" "$LIBARCUS_REF" "https://github.com/Ultimaker/libArcus/archive/${LIBARCUS_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "pyArcus" "$PYARCUS_REF" "https://github.com/Ultimaker/pyArcus/archive/${PYARCUS_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "pynest2d" "$PYNEST2D_REF" "https://github.com/Ultimaker/pynest2d/archive/${PYNEST2D_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "libnest2d" "$LIBNEST2D_REF" "https://github.com/Ultimaker/libnest2d/archive/${LIBNEST2D_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "libUvula" "$LIBUVULA_REF" "https://github.com/Ultimaker/libUvula/archive/${LIBUVULA_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "CuraFormulaeEngine" "$CURAFORMULAE_REF" "https://github.com/Ultimaker/CuraFormulaeEngine/archive/${CURAFORMULAE_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "Scripta" "$SCRIPTA_REF" "https://github.com/Ultimaker/Scripta_public/archive/${SCRIPTA_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "zeus_expected" "$ZEUS_REF" "https://github.com/zeus-cpp/expected/archive/${ZEUS_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "lexy" "$LEXY_REF" "https://github.com/foonathan/lexy/archive/${LEXY_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "geometry.hpp" "$GEOMETRY_REF" "https://github.com/mapbox/geometry.hpp/archive/${GEOMETRY_REF}.tar.gz"
    printf '%-24s %-44s %s\n' "wagyu" "$WAGYU_REF" "https://github.com/mapbox/wagyu/archive/${WAGYU_REF}.tar.gz"
    printf '\nAlpine: %s (%s), APKINDEX hash %s\n' "$ALPINE_VERSION" "$ALPINE_BRANCH" "$APKINDEX_HASH"
    if [ -n "${GITHUB_REPOSITORY:-}" ]; then
        printf 'Build patches: https://github.com/%s/tree/%s\n' "$GITHUB_REPOSITORY" "$RELEASE_TAG"
    fi
    printf '\nThe tarball also contains the license texts under /usr/share/licenses/cura-alpine/.\n'
} > "$sources"

notes="$DIST_DIR/release-notes.md"
cat > "$notes" <<EOF
Unofficial UltiMaker Cura ${CURA_TAG} build for Alpine ${ALPINE_VERSION}.

## Install

Install the Alpine runtime dependencies first:

\`\`\`sh
apk add python3 py3-qt6 py3-numpy py3-scipy py3-cryptography \\
    py3-pyclipper py3-zeroconf py3-pyserial py3-requests py3-keyring \\
    py3-networkx libstdc++ \\
    protobuf onetbb libpng clipper nlopt spdlog fmt boost-libs \\
    qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qt5compat \\
    qt6-qtimageformats qt6-qttranslations \\
    mesa-dri-gallium mesa-gl \\
    libx11 libxkbcommon libxcb libxi libxrender libsm libice libxext \\
    font-noto font-dejavu
\`\`\`

Then extract the tarball and run Cura:

\`\`\`sh
sudo tar -xzf ${tarball_name} -C /
cura
\`\`\`

Verify the download:

\`\`\`sh
sha256sum -c ${tarball_name}.sha256
\`\`\`

## Versions

| Component | Version / ref |
| --- | --- |
| Cura | ${CURA_TAG} |
| Uranium | ${URANIUM_REF} |
| CuraEngine | ${CURAENGINE_REF} |
| fdm-materials | ${FDM_MATERIALS_REF} |
| libArcus | ${LIBARCUS_VERSION} (\`${LIBARCUS_REF}\`) |
| pyArcus | \`${PYARCUS_REF}\` |
| pynest2d | \`${PYNEST2D_REF}\` |
| libnest2d | \`${LIBNEST2D_REF}\` |
| libUvula / pyUvula | ${LIBUVULA_VERSION} (\`${LIBUVULA_REF}\`) |
| CuraFormulaeEngine | ${CURAFORMULAE_VERSION} (\`${CURAFORMULAE_REF}\`) |
| Scripta | \`${SCRIPTA_REF}\` |
| Alpine | ${ALPINE_VERSION} (${ALPINE_BRANCH}), APKINDEX ${APKINDEX_HASH} |

The exact source archives are listed in \`SOURCES-${RELEASE_TAG}.txt\`.

## Licensing

Cura and Uranium are LGPL-3.0-or-later; CuraEngine is AGPL-3.0-or-later;
libUvula is LGPL-3.0 with an MIT-licensed xatlas component. License texts are in
\`/usr/share/licenses/cura-alpine/\`. This is an unofficial build, not endorsed
by UltiMaker. Cura uses the GPL-licensed PyQt6 runtime installed by the user.

The build scripts and patches are MIT-licensed.
EOF

log "wrote $tarball"
log "wrote $sources"
log "wrote $notes"

#!/usr/bin/env bash
#
# Generate the architecture-independent release metadata from versions.env:
# SOURCES-<tag>.txt and release-notes.md. Run after the matrix builds have
# placed their tarballs and checksums in $DIST_DIR.
#
# See docs/release-pipeline.md.

set -euo pipefail

VERSIONS_FILE=${VERSIONS_FILE:-versions.env}
DIST_DIR=${DIST_DIR:-dist}
ARCHS=${ARCHS:-"x86_64 x86 armv7 aarch64"}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

[ -f "$VERSIONS_FILE" ] || die "missing $VERSIONS_FILE; run scripts/resolve-versions.sh first"
# shellcheck disable=SC1090
. "$VERSIONS_FILE"

for var in CURA_TAG URANIUM_REF CURAENGINE_REF FDM_MATERIALS_REF LIBARCUS_REF \
           PYARCUS_REF PYNEST2D_REF LIBNEST2D_REF LIBUVULA_REF LIBUVULA_VERSION \
           LIBARCUS_VERSION CURAFORMULAE_REF CURAFORMULAE_VERSION SCRIPTA_REF \
           ZEUS_REF LEXY_REF GEOMETRY_REF WAGYU_REF ALPINE_VERSION ALPINE_BRANCH \
           APKINDEX_HASH RELEASE_TAG; do
    [ -n "${!var:-}" ] || die "$var is not set in $VERSIONS_FILE"
done

platform_for() {
    case "$1" in
        x86_64)  printf 'linux/amd64' ;;
        x86)     printf 'linux/386' ;;
        armv7)   printf 'linux/arm/v7' ;;
        aarch64) printf 'linux/arm64' ;;
        armhf)   printf 'linux/arm/v6' ;;
        *)       printf 'unknown' ;;
    esac
}

mkdir -p "$DIST_DIR"

for arch in $ARCHS; do
    [ -f "$DIST_DIR/cura-${RELEASE_TAG}-linux-${arch}.tar.gz" ] \
        || die "missing tarball for $arch"
    [ -f "$DIST_DIR/cura-${RELEASE_TAG}-linux-${arch}.tar.gz.sha256" ] \
        || die "missing checksum for $arch"
done

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
    printf 'Architectures: %s\n' "$ARCHS"
    if [ -n "${GITHUB_REPOSITORY:-}" ]; then
        printf 'Build patches: https://github.com/%s/tree/%s\n' "$GITHUB_REPOSITORY" "$RELEASE_TAG"
    fi
    printf '\nThe tarballs also contain the license texts under /usr/share/licenses/cura-alpine/.\n'
} > "$sources"

notes="$DIST_DIR/release-notes.md"
cat > "$notes" <<EOF
Unofficial UltiMaker Cura ${CURA_TAG} build for Alpine ${ALPINE_VERSION}.

## Artifacts

Choose the tarball for your architecture:

| Architecture | Docker platform | File |
| --- | --- | --- |
EOF
for arch in $ARCHS; do
    printf '| %s | %s | `cura-%s-linux-%s.tar.gz` |\n' \
        "$arch" "$(platform_for "$arch")" "$RELEASE_TAG" "$arch" >> "$notes"
done
cat >> "$notes" <<EOF

\`armhf\` (\`linux/arm/v6\`) is not published yet: upstream Cura and Uranium are
marked \`noarch !armhf\`.

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

Then extract the matching tarball and run Cura. For example, on \`x86_64\`:

\`\`\`sh
sha256sum -c cura-${RELEASE_TAG}-linux-x86_64.tar.gz.sha256
sudo tar -xzf cura-${RELEASE_TAG}-linux-x86_64.tar.gz -C /
cura
\`\`\`

Substitute your architecture's file name from the table above.

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
| zeus_expected | \`${ZEUS_REF}\` |
| lexy | \`${LEXY_REF}\` |
| geometry.hpp | \`${GEOMETRY_REF}\` |
| wagyu | \`${WAGYU_REF}\` |
| Alpine | ${ALPINE_VERSION} (${ALPINE_BRANCH}), APKINDEX ${APKINDEX_HASH} |

The exact source archives are listed in \`SOURCES-${RELEASE_TAG}.txt\`.

## Licensing

Cura and Uranium are LGPL-3.0-or-later; CuraEngine is AGPL-3.0-or-later;
libUvula is LGPL-3.0 with an MIT-licensed xatlas component. License texts are in
\`/usr/share/licenses/cura-alpine/\`. This is an unofficial build, not endorsed
by UltiMaker. Cura uses the GPL-licensed PyQt6 runtime installed by the user.

The build scripts and patches are MIT-licensed.
EOF

log "wrote $sources"
log "wrote $notes"

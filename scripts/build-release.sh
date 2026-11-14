#!/usr/bin/env bash
#
# Build the image from a resolved versions.env and export the release tarball.
# See docs/release-pipeline.md.
#
# Requires: bash, docker, sha256sum, tar (in the image).

set -euo pipefail

VERSIONS_FILE=${VERSIONS_FILE:-versions.env}
DIST_DIR=${DIST_DIR:-dist}
PLATFORM=${PLATFORM:-linux/amd64}
ARCH=${ARCH:-x86_64}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

[ -f "$VERSIONS_FILE" ] || die "missing $VERSIONS_FILE; run scripts/resolve-versions.sh first"
# shellcheck disable=SC1090
. "$VERSIONS_FILE"

for var in CURA_TAG CURA_VERSION URANIUM_REF CURAENGINE_REF CURAENGINE_VERSION \
           FDM_MATERIALS_REF LIBARCUS_REF LIBARCUS_VERSION PYARCUS_REF \
           PYSAVITAR_REF PYSAVITAR_VERSION LIBSAVITAR_REF LIBSAVITAR_VERSION \
           DULCIFICUM_REF DULCIFICUM_VERSION CTRE_REF \
           PYNEST2D_REF LIBNEST2D_REF LIBUVULA_REF LIBUVULA_VERSION \
           CURAFORMULAE_REF CURAFORMULAE_VERSION SCRIPTA_REF ZEUS_REF LEXY_REF \
           GEOMETRY_REF WAGYU_REF ALPINE_IMAGE BUILD_ID; do
    [ -n "${!var:-}" ] || die "$var is not set in $VERSIONS_FILE"
done

command -v docker >/dev/null 2>&1 || die "missing command: docker"

# The build id, not the git tag: artifact names must not contain the run number.
image="cura-alpine:${BUILD_ID}-${ARCH}"
tarball_name="cura-${BUILD_ID}-linux-${ARCH}.tar.gz"
tarball="$DIST_DIR/$tarball_name"

mkdir -p "$DIST_DIR"

log "building $image for $PLATFORM (arch $ARCH)"
if [ "$PLATFORM" = "linux/amd64" ]; then
    build=(docker build)
else
    docker buildx version >/dev/null 2>&1 \
        || die "docker buildx is required to build $PLATFORM"
    build=(docker buildx build --load)
fi

"${build[@]}" \
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
    --build-arg PYSAVITAR_REF="$PYSAVITAR_REF" \
    --build-arg PYSAVITAR_VERSION="$PYSAVITAR_VERSION" \
    --build-arg LIBSAVITAR_REF="$LIBSAVITAR_REF" \
    --build-arg LIBSAVITAR_VERSION="$LIBSAVITAR_VERSION" \
    --build-arg DULCIFICUM_REF="$DULCIFICUM_REF" \
    --build-arg DULCIFICUM_VERSION="$DULCIFICUM_VERSION" \
    --build-arg CTRE_REF="$CTRE_REF" \
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

sitelib=$(python3 -c 'import sysconfig; print(sysconfig.get_path("platlib"))')
sitelib=${sitelib#/}

required="
usr/bin/cura
usr/bin/CuraEngine
usr/lib/cura
usr/lib/uranium
usr/share/cura
usr/share/uranium
usr/share/locale
usr/share/licenses/cura-alpine
${sitelib}/UM
${sitelib}/cura
${sitelib}/pyArcus.so
${sitelib}/pyArcus.pyi
${sitelib}/stl
${sitelib}/trimesh
${sitelib}/python_utils
${sitelib}/typing_extensions.py
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
         'usr/lib/libSavitar.so*' \
         "${sitelib}/pynest2d*" \
         "${sitelib}/pyUvula*" \
         "${sitelib}/pySavitar*" \
         "${sitelib}/pyDulcificum*" \
         "${sitelib}/numpy_stl*"; do
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

log "wrote $tarball"

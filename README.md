# Cura on Alpine — multi-stage build

Documentation and build files for **UltiMaker Cura** on **Alpine Linux**.

The target is a multi-stage Docker image:

1. **Builder:** `FROM alpine:latest`, install the build toolchain, then download
   and compile the latest upstream UltiMaker releases from source.
2. **Runtime:** `FROM alpine:latest`, install only the libraries needed to run
   Cura, copy the built binaries/resources/Python packages from the builder, and
   run Cura as a non-root user.

The image does **not** use Alpine's `edge` Cura packages. Cura, Uranium,
CuraEngine, libArcus, pyArcus, pynest2d, libUvula and fdm-materials are all
built in the first stage. The Alpine [aports](https://gitlab.alpinelinux.org/alpine/aports) repository is
used as a reference for patches, CMake flags and install layout only.

**Status: builds and starts.** The image builds on Alpine 3.24.x with Cura
5.14.0, Uranium 5.14.0, CuraEngine 5.14.0 and pyUvula 1.1.0. The build-time
import checks pass, `CuraEngine help` reports 5.14.0, and Cura stays running in
an offscreen Qt session without a traceback.

## The blocker

Alpine does not package `pyUvula`, the Python binding of
[Ultimaker/libUvula](https://github.com/Ultimaker/libUvula). Uranium imports it
unconditionally in `UM/Mesh/MeshData.py`, and Cura's Paint tool imports it too,
so Cura exits at startup with:

```
ModuleNotFoundError: No module named 'pyUvula'
```

Because the image builds the entire Cura stack from source, `libUvula` and
`pyUvula` are built in the same builder stage and installed into the same Python
environment as Uranium and Cura. The runtime stage receives the resulting
extension and its shared-library dependencies.

## Documents

| File | Contents |
| --- | --- |
| [`docs/upstream-versions.md`](docs/upstream-versions.md) | Latest upstream releases, Cura component requirements, and unresolved version mappings. |
| [`docs/dockerfile-design.md`](docs/dockerfile-design.md) | Multi-stage Dockerfile design: stages, packages, build order, exact CMake flags, runtime setup, verification, risks. |
| [`docs/libuvula.md`](docs/libuvula.md) | Why `pyUvula` is required, upstream libUvula facts, version pinning, Alpine patches, packaging proposal. |
| [`docs/reference-apkbuilds.md`](docs/reference-apkbuilds.md) | Reference analysis of the aports APKBUILDs, retained as a patch/flag/install-layout baseline. |
| [`docs/release-plan.md`](docs/release-plan.md) | GitHub Actions release pipeline, tag scheme, tarball contents, excluded Alpine packages, install instructions and licensing rules. |

Reference sources used for the analysis:

- [testing/cura](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/cura), [testing/uranium](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/uranium), [community/curaengine](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/community/curaengine)
- [community/libarcus](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/community/libarcus), [testing/py3-arcus](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/py3-arcus), [testing/py3-pynest2d](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/py3-pynest2d), [testing/fdm-materials](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/fdm-materials)
- Upstream source repositories for Cura, Uranium, CuraEngine, libArcus, pyArcus, pynest2d, fdm-materials and libUvula

## Proposed approach

- **Base:** `alpine:latest` (currently Alpine 3.24) for both stages.
- **Builder:** install `build-base`, CMake, Ninja, Python development headers,
  Qt 6 development packages, protobuf, boost, clipper, spdlog, range-v3,
  libnest2d, nlopt, pybind11 and SIP.
- **Versions:** resolve from the latest Cura release's `conandata.yml`; pin every
  component to an exact tag or commit. The Dockerfile keeps the last verified
  refs as `--build-arg` defaults and the release workflow passes the resolved
  refs. Do not use floating `latest` source refs in the image.
- **Order:** libArcus → pyArcus → CuraEngine → pynest2d → libUvula/pyUvula →
  Uranium → fdm-materials → Cura.
- **Runtime:** only Python 3, PyQt6, Qt 6 runtime/QML modules, Mesa, X11 client
  libraries, fonts and the files copied from the builder.
- **Entrypoint:** `/usr/bin/cura`, non-root `cura` user, X11/Wayland socket
  mounts, software rendering fallback.

## Releases

[`.github/workflows/release.yml`](.github/workflows/release.yml) runs daily and
on demand. It resolves the latest Cura release, its UltiMaker dependency refs,
the Alpine version and the Alpine package-index hash, then builds and publishes:

```text
<cura-tag>-<deps-hash>-alpine-<alpine-version>-<apkindex-hash>
```

Example: `5.14.0-1a2b3c4-alpine-3.24.4-9f8e7d6`. A scheduled run skips the
build when that release already exists; a manual run rebuilds and replaces it.

The artifact is **not** a full filesystem dump. The tarball contains only the
files our build produces (Cura, Uranium, CuraEngine, the compiled Python
packages, the generated shared libraries, resources and license texts). Python,
PyQt6/Qt, Mesa, X11/Wayland libraries, fonts and the rest of the Alpine runtime
are installed by the user with `apk`, not shipped in the tarball. See
[`docs/release-plan.md`](docs/release-plan.md) for the file list, the exact
`apk add` command and the licensing obligations.

## Scope

- The release pipeline currently targets `linux/amd64` (`x86_64`) only.
- Future work may add `x86` (i386), `armhf`, `armv7` and `aarch64`. `aarch64`
  and `armv7` need a native runner or QEMU. `armhf` is currently blocked by
  upstream packaging metadata (`cura`/`uranium` are `noarch !armhf`) and needs a
  source-level check.
- The Dockerfile hardcodes Python 3.14 (`/usr/lib/python3.14/site-packages`),
  matching Alpine 3.24. Detecting the interpreter's `site-packages` path is
  planned for a future release.
- The same patches and flags should remain reusable in an APKBUILD so the
  Alpine package can eventually be fixed at the source.
- Not in scope: AppImage/Flatpak packaging, Windows/macOS, or using prebuilt
  Cura binaries.

## License

The build files in this repository (`Dockerfile`, `patches/`, `docs/`) are
released under the MIT license; see [`LICENSE`](LICENSE).

The software the image builds keeps its upstream licenses: Cura and Uranium are
LGPL-3.0-or-later, CuraEngine is AGPL-3.0-or-later, and libUvula is LGPL-3.0
(its bundled `xatlas` is MIT). The repository's MIT license does not relicense
those components; their license files must be preserved in the image.

# Dockerfile design

This document describes the implemented [`Dockerfile`](../Dockerfile) for Cura
5.14.0 on Alpine Linux. The Dockerfile is the authority for exact commands; this
page records the structure, the build arguments and the reasons behind them.

## 1. Goals

- Build Cura, Uranium and CuraEngine from source on `alpine:latest`.
- Build the missing **libUvula + pyUvula** dependency from source, because no
  Alpine package exists.
- Produce a runtime image that can actually launch Cura, not merely compile it.
- Keep the runtime image free of compilers and build headers.
- Build `linux/amd64` (`x86_64`) and `linux/386` (`x86`) natively; the amd64
  kernel runs 32-bit x86 directly. Build `linux/arm/v7` (`armv7`) and
  `linux/arm64` (`aarch64`) under QEMU user emulation. The Dockerfile is
  architecture neutral. `armhf` (`linux/arm/v6`) is not built because upstream
  marks Cura/Uranium `noarch !armhf`; it needs a source-level check first.

Non-goals:

- Producing an `.apk` package (that is a separate aports contribution).
- Shipping `cura-binary-data`, firmware blobs or a full printer-definition
  bundle beyond what the Cura source tree contains.
- Running CuraEngine as a separate service; the binary is installed into the
  image and found through `PATH`.

## 2. Stages

```text
┌──────────────────────────────────────────────────────────────┐
│ builder (FROM ${ALPINE_IMAGE})                               │
│   build-base, cmake, samurai, python3-dev, Qt dev, protobuf  │
│   builds every component and installs into /usr              │
│   keeps the source trees in /src for license collection      │
└───────────────────────────┬──────────────────────────────────┘
                            │ COPY --from=builder <allowlist>
┌───────────────────────────▼──────────────────────────────────┐
│ runtime (FROM ${ALPINE_IMAGE})                               │
│   python3, PyQt6, Qt6 runtime/QML, Python runtime deps,      │
│   Mesa, X11 client libraries, fonts, shared C++ libraries    │
│   non-root user, entrypoint /usr/bin/cura                    │
└──────────────────────────────────────────────────────────────┘
```

The builder installs directly into `/usr`; it does not use a staging prefix.
CMake package discovery, Python `site-packages` and the Uranium/Cura configure
steps therefore see a normal system installation. The runtime stage copies an
explicit allowlist of paths, which is what keeps build tools out of the final
image.

`ALPINE_IMAGE` is a build argument. A plain `docker build .` uses
`alpine:latest`; the release workflow passes `alpine:<version>` from Alpine's
`latest-releases.yaml` so the image matches the version in the release tag.

## 3. Build arguments

All source refs are build arguments with pinned defaults. GitHub's
`/archive/<ref>.tar.gz` endpoint accepts both tags and commit SHAs, so one
argument per component is enough.

| Argument | Default | Notes |
| --- | --- | --- |
| `CURA_REF` / `CURA_VERSION` | `5.14.0` | tag |
| `URANIUM_REF` | `5.14.0` | tag |
| `CURAENGINE_REF` / `CURAENGINE_VERSION` | `5.14.0` | tag; the version flag is separate because Conan normally injects it |
| `FDM_MATERIALS_REF` | `5.14.0` | tag |
| `LIBARCUS_REF` / `LIBARCUS_VERSION` | `339c85a1...` / `5.11.1` | no matching tag |
| `PYARCUS_REF` | `72d052a2...` | no matching tag |
| `PYNEST2D_REF` | `73235af5...` | no matching tag |
| `LIBNEST2D_REF` | `1c9dc3c0...` | headers only |
| `LIBUVULA_REF` / `LIBUVULA_VERSION` | `d15219e...` / `1.1.0` | no tags or releases |
| `CURAFORMULAE_REF` / `CURAFORMULAE_VERSION` | `c1257dd6...` / `1.2.1` | no tags |
| `SCRIPTA_REF` | `b96045c...` | no 1.1.0 tag |
| `ZEUS_REF` | `v1.4.0` | non-UltiMaker |
| `LEXY_REF` | `v2025.05.0` | non-UltiMaker |
| `GEOMETRY_REF` | `v2.0.3` | mapbox/geometry.hpp |
| `WAGYU_REF` | `0.5.0` | mapbox/wagyu |

The release workflow overrides these with the resolved upstream refs; see
[`release-pipeline.md`](release-pipeline.md). The defaults are the last manually
verified set and are what a plain `docker build .` uses. The workflow resolves
`ZEUS_REF`, `LEXY_REF`, `GEOMETRY_REF` and `WAGYU_REF` from each project's
GitHub `releases/latest` tag (or the newest git tag when it is newer), like Cura
itself.

## 4. Builder packages

```dockerfile
build-base cmake samurai git patch pkgconf curl tar xz
python3 python3-dev py3-pip py3-wheel py3-setuptools
py3-sip py3-qt6
gettext gettext-dev
boost-dev clipper-dev libpng-dev onetbb-dev protobuf-dev
range-v3-dev rapidjson-dev spdlog-dev fmt-dev stb
nlopt-dev
qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtsvg-dev
qt6-qt5compat-dev qt6-qtimageformats-dev
```

`pybind11==3.0.1` is installed with pip, not from `py3-pybind11`: Alpine's
CMake config points at `site-packages/pybind11/include`, while the headers are
in the separate `py3-pybind11-dev` package. The pip wheel ships both.

Notes:

- `samurai` provides `/usr/bin/ninja`.
- `gettext` supplies `msginit`, required by Uranium and Cura. Both are
  configured with `-DGETTEXT_MSGINIT_EXECUTABLE=msginit`.
- `clipper-dev` installs `clipper.hpp` and `libpolyclipping` but no CMake config.
  CuraEngine's aports patch provides `FindClipper.cmake`; libUvula and pynest2d
  reuse it.
- Alpine 3.24 does not package `libnest2d`, `zeus_expected`, `lexy` or
  `cura-formulae-engine`; they are built from source.

## 5. Build order

```text
1. zeus_expected              (tag v1.4.0)
2. lexy                       (tag v2025.05.0)
3. CuraFormulaeEngine 1.2.1   (main c1257dd6, needs zeus_expected + lexy)
4. libArcus 5.11.1            (main 339c85a1)
5. pyArcus 5.12.0             (main 72d052a2, needs libArcus)
6. CuraEngine 5.14.0          (needs libArcus + CuraFormulaeEngine + bundled Scripta)
7. libnest2d 5.11.0-alpha.0   (main 1c9dc3c0, headers only)
8. pynest2d 5.11.0-alpha.0    (main 73235af5, needs clipper, libnest2d, boost, nlopt, sip)
9. libUvula + pyUvula 1.1.0   (main d15219eb, needs spdlog, range-v3, clipper, pybind11)
10. Uranium 5.14.0            (needs Python; runtime needs pyUvula/pyArcus)
11. fdm-materials 5.14.0
12. Cura 5.14.0               (needs Uranium resources at configure time)
```

Cura is configured with `-DURANIUM_DIR=/usr/share/uranium`, so Uranium is
installed first. fdm-materials installs JSON into Cura's resource tree; it runs
before Cura so Cura's install does not overwrite it.

## 6. Per-component adaptations

| Component | Flags / patches |
| --- | --- |
| zeus_expected | `-DZEUS_EXPECTED_BUILD_TESTS=OFF` |
| lexy | tests/examples/benchmarks/docs off |
| CuraFormulaeEngine | `patches/cura-formulae-engine/cmake.patch`; `-DCURA_FORMULA_VERSION_VERSION`; installs `cura-formulae-engineConfig.cmake` |
| libArcus | aports patches `cmake-build.patch`, `ArcusConfig.patch`, `protobuf-31.patch`; `-DARCUS_VERSION`; shared library |
| pyArcus | aports patches plus `pyproject.patch`; SIP 6; installs `pyArcus.so` and `.pyi` |
| CuraEngine | aports `cmake.patch` + `cmake-helpers.patch` + our `32bit-min.patch` (32-bit `std::min` type fix); bundles Scripta, geometry.hpp and wagyu; `-DCURA_ENGINE_VERSION`; plugins/curaviz/sentry off |
| libnest2d | headers copied to `/usr/include/libnest2d` |
| pynest2d | aports patches plus `FindClipper.cmake`; shared library |
| libUvula | `patches/libuvula/cmake.patch`; `-DUVULA_VERSION`/`-DPYUVULA_VERSION`; Python bindings on, JS/CLI off; C++20 and PIC. Linked statically into `pyUvula` (the only consumer; a shared library would add a file without reducing size or improving performance) |
| Uranium | aports `cmake.patch`, `fix-logger-used-but-not-imported.patch`, `qt-try-ints-then-bytes.patch`, `cmake-helpers.patch`; `-DPython_VERSION=<major.minor from python3>`; `MinSizeRel` |
| fdm-materials | `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` (upstream CMake minimum is too old for CMake 4) |
| Cura | aports `AppDesktopData.patch`, `CuraVersion.patch`, `cmake-helpers.patch`, `cmake.patch`; `-DCURA_VERSION`; `cura_app.py` renamed to `cura`; `SliceInfoPlugin` removed; translations moved to `/usr/share/locale` |

The libUvula patch removes `standardprojectsettings` and its helper calls,
switches to Alpine's `Clipper::Clipper`, and adds the install rules upstream
lacks. See [`libuvula.md`](libuvula.md).

## 7. Installed layout

| Path | Contents |
| --- | --- |
| `/usr/bin/cura` | launcher, renamed from `cura_app.py` |
| `/usr/bin/CuraEngine` | slicing engine |
| `/usr/lib/cura/` | Cura plugins, QML and application data |
| `/usr/lib/uranium/` | Uranium plugins and QML |
| `/usr/lib/libArcus.so*` | libArcus |
| `/usr/lib/libcura-formulae-engine.so*` | CuraFormulaeEngine |
| `/usr/share/cura/` | Cura resources, definitions, QML, materials |
| `/usr/share/uranium/` | Uranium resources and CMake modules |
| `/usr/share/locale/` | Cura translations |
| `/usr/share/licenses/cura-alpine/` | license texts collected from every source tree, plus this repository's `LICENSE` |
| `<sitelib>/UM/` | Uranium Python package |
| `<sitelib>/cura/` | Cura Python package |
| `<sitelib>/pyArcus.so` | pyArcus (import name `pyArcus`) |
| `<sitelib>/pynest2d*` | pynest2d |
| `<sitelib>/pyUvula*` | libUvula bindings |
| `<sitelib>/stl/`, `numpy_stl*` | numpy-stl |
| `<sitelib>/trimesh/` | trimesh |
| `<sitelib>/python_utils/`, `typing_extensions.py` | numpy-stl runtime dependencies |

`<sitelib>` is not hardcoded. The builder runs
`python3 -c 'import sysconfig; print(sysconfig.get_path("platlib"))'`, copies the
Python packages into `/staging/python`, and the runtime stage runs the same
query and copies them into the detected directory. On Alpine 3.24 that is
`/usr/lib/python3.14/site-packages`. A new Alpine minor with a different Python
therefore needs no `COPY` path changes; the runtime import check verifies the
ABI match.

## 8. Runtime stage

Runtime packages:

```dockerfile
python3 py3-qt6 py3-numpy py3-scipy py3-cryptography
py3-pyclipper py3-zeroconf py3-pyserial py3-requests py3-keyring
py3-networkx
libstdc++ protobuf onetbb libpng clipper nlopt spdlog fmt boost-libs
qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qt5compat
qt6-qtimageformats qt6-qttranslations
mesa-dri-gallium mesa-gl
libx11 libxkbcommon libxcb libxi libxrender libsm libice libxext
font-noto font-dejavu
```

The shared C++ libraries must be present or the runtime `ldd` check fails:
`protobuf`, `onetbb`, `libpng`, `clipper`, `nlopt`, `spdlog`, `fmt`,
`boost-libs`. `libstdc++` is needed by every compiled component.

The stage creates a non-root `cura` user, sets `HOME`, defaults
`QT_QPA_PLATFORM=xcb`, forces software rendering with
`LIBGL_ALWAYS_SOFTWARE=1`, and uses `/usr/bin/cura` as the entrypoint.

## 9. Verification

Build-time checks in the Dockerfile:

```sh
python3 -c "import pyUvula; assert pyUvula.__version__ == '<LIBUVULA_VERSION>'"
python3 -c "import UM, cura, pyArcus, pynest2d"
python3 -c "import cura.ApplicationMetadata as m; print(m.CuraVersion)"
CuraEngine help | grep -m1 'Cura_SteamEngine version'
```

Runtime smoke test:

```sh
docker run --rm -e QT_QPA_PLATFORM=offscreen --entrypoint timeout \
  cura-alpine 30s cura
```

Exit code `124` (GNU `timeout`) or `143` (BusyBox `timeout` after `SIGTERM`)
with no Python traceback means Cura stayed alive for 30 seconds. Any Python
traceback is a failure. Cura may ignore `SIGTERM` and keep running; if the
command does not return, start it in the background, wait 30 seconds, and kill
it explicitly. A successful compile is not proof that the image runs.

## 10. Risks and open questions

| Risk | Impact | Mitigation |
| --- | --- | --- |
| No libUvula tags; exact 1.1.0 commit unknown | Build may not match Cura 5.14's expected ABI/version | Pin `d15219e`; force version 1.1.0; assert `pyUvula.__version__` at build time |
| Python 3.14 vs upstream 3.12 | Cura/Uranium may hit removed APIs or C-extension ABI issues | Build and smoke-test; the current build passes |
| Qt 6.11 vs upstream 6.10 | QML or PyQt6 API changes | Smoke-test the UI |
| musl libc | Native extensions may assume glibc | Build everything from source against musl |
| `cura-binary-data` absent | Some firmware/precompiled resources missing | Documented limitation; add only if a feature needs it |
| armhf unsupported | Build fails or produces a broken image | Not built now; needs a source-level check (upstream metadata marks Cura/Uranium `noarch !armhf`) |
| QEMU builds are slow or time out | An emulated matrix job exceeds the runner limit | `fail-fast: false`, 360-minute job timeout; native `aarch64` runners remain the fallback |
| Large image | Cura resources are ~137 MB before compression | Slim runtime stage; release tarball excludes Alpine packages |
| New Alpine minor changes Python/Qt | Detected paths avoid `COPY` churn, but a Python minor change still changes the C-extension ABI | Runtime import check fails loudly; rebuild and smoke-test |

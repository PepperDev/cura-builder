# Reference APKBUILDs (5.13.0 baseline)

> **This is a baseline, not the target version set.** The recipes below are
> Cura 5.13.0 / libArcus 5.3.0. The Dockerfile targets the latest upstream Cura
> 5.14.0 stack and must resolve component refs from Cura's `conandata.yml`.
> Use this document for patches, flags and install layout, not for version
> pins. See [`upstream-versions.md`](upstream-versions.md).

Condensed reference for the seven packages the reference Dockerfile has to reproduce.
Everything below is taken from the APKBUILDs in the Alpine
[aports repository](https://gitlab.alpinelinux.org/alpine/aports) (observed November 2026). When the Dockerfile and the APKBUILD disagree, the
APKBUILD is the authority for Alpine-specific patches and install layout.

| Package | Version | aports path |
| --- | --- | --- |
| `cura` | 5.13.0 | [`testing/cura`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/cura) |
| `uranium` | 5.13.0 | [`testing/uranium`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/uranium) |
| `curaengine` | 5.13.0 | [`community/curaengine`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/community/curaengine) |
| `libarcus` | 5.3.0 | [`community/libarcus`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/community/libarcus) |
| `py3-arcus` | 5.3.0 | [`testing/py3-arcus`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/py3-arcus) |
| `py3-pynest2d` | 5.3.0 | [`testing/py3-pynest2d`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/py3-pynest2d) |
| `fdm-materials` | 5.13.0 | [`testing/fdm-materials`](https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/testing/fdm-materials) |

---

## 1. `cura` (testing/cura)

| Field | Value |
| --- | --- |
| `pkgver` / `pkgrel` | 5.13.0 / 0 |
| `arch` | `noarch !armhf` (armhf blocked by Uranium) |
| `license` | LGPL-3.0-or-later |
| `subpackages` | `cura-lang` |
| `options` | `!check` (tests broken since Cura 5.x) |
| `builddir` | `Cura-5.13.0` |

### Runtime dependencies

```
curaengine fdm-materials uranium py3-arcus py3-keyring py3-numpy-stl
py3-pyclipper py3-pynest2d py3-pyserial py3-qt6 py3-requests py3-trimesh
py3-zeroconf
```

`cura-binary-data` is intentionally absent. The APKBUILD comments: *"add
cura-binary-data to depends when packaged"*.

### Build dependencies

```
samurai cmake gettext gettext-dev
```

`gettext` is needed for `msginit`, which the patched CMake files invoke.

### Sources

- `https://github.com/Ultimaker/Cura/archive/refs/tags/5.13.0.tar.gz`
- `AppDesktopData.patch`
- `CuraVersion.patch`
- `cmake-helpers.patch`
- `cmake.patch`

### Configure flags

```sh
cmake -B build -G Ninja \
    -DCURA_VERSION=5.13.0 \
    -DPython_VERSION=<major.minor from python3> \
    -DURANIUM_DIR=/usr/share/uranium \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DGETTEXT_MSGINIT_EXECUTABLE=msginit \
    -DCURA_BINARY_DATA_DIRECTORY=/usr/share/cura \
    -DCMAKE_BUILD_TYPE=minsizerel
```

### Package steps

```sh
DESTDIR="$pkgdir" cmake --install build
mv "$pkgdir/usr/bin/cura_app.py" "$pkgdir/usr/bin/cura"

# Do not send user/print information to UltiMaker.
rm -rf "$pkgdir/usr/lib/cura/plugins/SliceInfoPlugin"

install -d "$pkgdir/usr/share/locale"
mv "$pkgdir/usr/share/cura/resources/i18n/"* "$pkgdir/usr/share/locale/"
```

### What the patches do

- `cmake.patch` — the important one. Upstream's CMake only builds translations.
  The patch adds version configuration, installation of the `cura` Python
  package into `Python_SITELIB`, resources into `/usr/share/cura`, the
  `cura_app.py` launcher into `bin`, desktop/icon/appdata/mime files, and
  includes `CuraPluginInstall.cmake`.
- `CuraVersion.patch` — adds `cura/CuraVersion.py.in` (app name, display name,
  version, build type, debug mode, cloud roots).
- `AppDesktopData.patch` — adds `com.ultimaker.cura.desktop.in`
  (`Exec=@CMAKE_INSTALL_FULL_BINDIR@/cura`, `Icon=cura-icon`,
  `StartupWMClass=cura.real`) and the AppStream metadata.
- `cmake-helpers.patch` — adds `cmake/CuraPluginInstall.cmake`, which installs
  each `plugins/*/plugin.json` directory to `lib${LIB_SUFFIX}/cura/<parent>`,
  honors `CURA_NO_INSTALL_PLUGINS`, and filters `__pycache__`/`.qmlc`.

---

## 2. `uranium` (testing/uranium)

| Field | Value |
| --- | --- |
| `pkgver` / `pkgrel` | 5.13.0 / 0 |
| `arch` | `noarch !armhf` (blocked by py3-qt6) |
| `license` | LGPL-3.0-or-later |
| `options` | `!check` (checks broken since 5.x) |
| `builddir` | `Uranium-5.13.0` |

### Runtime dependencies

```
py3-cryptography py3-numpy py3-qt6 py3-scipy python3
```

Note the missing `py3-uvula`: this is the packaging bug. Uranium's Python code
imports `pyUvula` unconditionally, so `py3-uvula` belongs in this list.

### Build dependencies

```
samurai cmake doxygen gettext-dev graphviz
```

`doxygen` and `graphviz` are only for documentation; they can be dropped from a
Docker build if the docs target is not run.

### Sources

- `https://github.com/Ultimaker/Uranium/archive/refs/tags/5.13.0.tar.gz`
- `cmake.patch`
- `fix-logger-used-but-not-imported.patch`
- `qt-try-ints-then-bytes.patch`
- `cmake-helpers.patch`

### Configure flags

```sh
cmake -B build -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DGETTEXT_MSGINIT_EXECUTABLE=msginit \
    -DCURA_BINARY_DATA_DIRECTORY=/usr/share/cura
```

Cross builds add:

```sh
-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_HOST_SYSTEM_NAME=Linux
```

### Package steps

```sh
DESTDIR="$pkgdir" cmake --install build
mkdir "$pkgdir/usr/share/uranium/cmake"
mv "$pkgdir"/usr/share/cmake-*/Modules/* "$pkgdir/usr/share/uranium/cmake/"
```

The move keeps Uranium's CMake modules under its own prefix instead of
polluting the global CMake module directory.

### What the patches do

- `cmake.patch` — adds `find_package(Python REQUIRED COMPONENTS Interpreter)`,
  installs the `UM` package into `Python_SITELIB`, and includes
  `UraniumPluginInstall`.
- `cmake-helpers.patch` — adds `UraniumPluginInstall.cmake` (plugins to
  `lib${LIB_SUFFIX}/uranium/<parent>`) and `UraniumTranslationTools.cmake`.
- `fix-logger-used-but-not-imported.patch` — adds
  `from UM.Logger import Logger` in `UM/View/SelectionPass.py`.
- `qt-try-ints-then-bytes.patch` — wraps `glDepthMask`/`glColorMask` arguments
  in `try`/`except`, trying `int` first and `bytes` second, in
  `UM/View/RenderBatch.py` and `UM/View/RenderPass.py`. This is a
  Fedora-sourced PyQt6 compatibility fix.

---

## 3. `curaengine` (community/curaengine)

| Field | Value |
| --- | --- |
| `pkgver` / `pkgrel` | 5.13.0 / 0 |
| `arch` | `all` |
| `license` | AGPL-3.0-or-later |
| `options` | `!check` |
| `builddir` | `CuraEngine-5.13.0` |

### Bundled dependency versions

| Dependency | Version / commit |
| --- | --- |
| Scripta | `b96045cd9b531d97f42dec8c9a0ef52f773f6b90` |
| mapbox `geometry.hpp` | 2.0.3 |
| mapbox `wagyu` | 0.5.0 |

### Build dependencies

```
boost-dev clipper-dev cmake libarcus-dev libpng-dev onetbb-dev protobuf-dev
range-v3-dev rapidjson-dev samurai spdlog-dev stb
```

### Sources

- `https://github.com/Ultimaker/CuraEngine/archive/5.13.0/CuraEngine-5.13.0.tar.gz`
- `https://github.com/Ultimaker/Scripta_public/archive/<scripta-commit>/Scripta_public-<scripta-commit>.tar.gz`
- `https://github.com/mapbox/geometry.hpp/archive/refs/tags/v2.0.3/geometry.hpp-2.0.3.tar.gz`
- `https://github.com/mapbox/wagyu/archive/refs/tags/0.5.0/wagyu-0.5.0.tar.gz`
- `cmake.patch`, `cmake-helpers.patch`, `32bit-arm.patch`, `32bit-min.patch`
- `mapbox-wagyuConfig.cmake`, `scriptaConfig.cmake`

### `prepare()`

The three vendored libraries are copied into a fake prefix:

```sh
mkdir -p "$builddir/bundled/include"
mkdir -p "$builddir/bundled/lib/cmake/mapbox-wagyu"
mkdir -p "$builddir/bundled/lib/cmake/scripta"

cp -r "$srcdir/wagyu-0.5.0/include/mapbox" "$builddir/bundled/include/"
cp -r "$srcdir/geometry.hpp-2.0.3/include/mapbox/geometry" \
      "$builddir/bundled/include/mapbox/"
cp -r "$srcdir/Scripta_public-<commit>/include/scripta" \
      "$builddir/bundled/include/"

cp "$srcdir/mapbox-wagyuConfig.cmake" \
   "$builddir/bundled/lib/cmake/mapbox-wagyu/"
cp "$srcdir/scriptaConfig.cmake" \
   "$builddir/bundled/lib/cmake/scripta/"
```

### Configure flags

```sh
cmake -G Ninja -B build \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$builddir/bundled" \
    -DENABLE_PLUGINS=OFF \
    -DENABLE_REMOTE_PLUGINS=OFF \
    -DENABLE_SENTRY=OFF
```

The comment in the APKBUILD explains that plugins require
`https://github.com/Tradias/asio-grpc`, which Alpine does not package. Disabling
them is required, not optional.

### Package steps

```sh
DESTDIR="$pkgdir" cmake --install build
```

### What the patches do

- `cmake.patch` — removes `standardprojectsettings` and
  `AssureOutOfSourceBuilds`, appends the source `cmake/` directory to the module
  path, fixes `Protobuf`/`Arcus` find-package casing, removes
  `use_threads()`/`enable_sanitizers()`/`set_project_warnings()`, switches
  `clipper` to `Clipper::Clipper`, drops `stb`, links `Boost::boost` and
  `TBB::tbb`, and adds `install(TARGETS CuraEngine)`.
- `cmake-helpers.patch` — adds `cmake/FindClipper.cmake`, which finds
  `clipper.hpp` and `libpolyclipping` and defines `Clipper::Clipper`. Reuse this
  file for libUvula.
- `32bit-arm.patch` — changes `std::min(..., 1UL)` to `size_t(1)` in
  `TreeSupport.cpp`; apply only for armv7.

---

## 4. `libarcus` (community/libarcus)

| Field | Value |
| --- | --- |
| `pkgver` / `pkgrel` | 5.3.0 / 0 |
| `arch` | `all` |
| `license` | LGPL-3.0-or-later |
| `subpackages` | `libarcus-dev` |
| `options` | `!check` (no test suite) |
| `builddir` | `libArcus-5.3.0` |

### Build dependencies

```
cmake protobuf-dev py3-sip python3-dev samurai
```

### Sources

- `https://github.com/Ultimaker/libArcus/archive/5.3.0/libArcus-5.3.0.tar.gz`
- `cmake-build.patch`
- `ArcusConfig.patch`
- `pb-errorcollector.patch`
- `protobuf-31.patch`
- `gcc15-cstdint.patch`

### Configure flags

```sh
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_INCLUDEDIR=/usr/include \
    -DBUILD_SHARED_LIBS=ON \
    -DARCUS_VERSION=5.3.0
```

### Package steps

```sh
DESTDIR="$pkgdir" cmake --install build
```

The shared library is intentional: `py3-arcus` links against it, and Cura uses
the Arcus socket protocol.

---

## 5. `py3-arcus` (testing/py3-arcus)

| Field | Value |
| --- | --- |
| `pkgver` / `pkgrel` | 5.3.0 / 8 |
| `arch` | `all` |
| `license` | LGPL-3.0-only |
| `options` | `!check` (no tests) |
| `builddir` | `pyArcus-5.3.0` |

This is a **separate upstream repository** (`Ultimaker/pyArcus`), not a
subdirectory of libArcus.

### Build dependencies

```
cmake libarcus-dev protobuf-dev py3-sip python3-dev samurai
```

### Sources

- `https://github.com/Ultimaker/pyArcus/archive/refs/tags/5.3.0.tar.gz`
- `cmake.patch`
- `cmake-helpers.patch`
- `protobuf-31.patch`
- `pyproject.patch`

### Configure flags

```sh
cmake -G Ninja -B build \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release
```

The APKBUILD does not pass `CMAKE_INSTALL_PREFIX`; the patched CMake files
install into Python's site-packages. In a Dockerfile it is safer to pass
`-DCMAKE_INSTALL_PREFIX=/usr` explicitly and stage with `DESTDIR`.

### Package steps

```sh
DESTDIR="$pkgdir" cmake --install build
```

---

## 6. `py3-pynest2d` (testing/py3-pynest2d)

| Field | Value |
| --- | --- |
| `pkgver` / `pkgrel` | 5.3.0 / 0 |
| `arch` | `all` |
| `license` | LGPL-3.0-or-later |
| `options` | `!check` |
| `builddir` | `pynest2d-5.3.0` |

### Build dependencies

```
samurai cmake libnest2d-dev clipper-dev py3-sip nlopt-dev boost-dev python3-dev
```

### Sources

- `https://github.com/Ultimaker/pynest2d/archive/refs/tags/5.3.0.tar.gz`
- `cmake.patch`
- `cmake-helpers.patch`
- `pyproject.patch`

### `prepare()`

```sh
mv ./python ./src
```

This must happen before `cmake` runs; the patched CMake expects the bindings
under `src/`.

### Configure flags

```sh
cmake -B build -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_SHARED_LIBS=True \
    -DCMAKE_BUILD_TYPE=Release
```

Cross builds add the same `CMAKE_SYSTEM_NAME`/`CMAKE_HOST_SYSTEM_NAME` pair as
Uranium.

### Package steps

```sh
DESTDIR="$pkgdir" cmake --install build
```

### Version note

Cura 5.13's Conan data asks for `pynest2d/5.10.0`, while the latest GitHub tag
is 5.3.0. The aports package uses 5.3.0 and Cura's `Nest2DArrange` code works
against it. Treat the Conan number as an internal build number, not a source
tag.

---

## 7. `fdm-materials` (testing/fdm-materials)

| Field | Value |
| --- | --- |
| `pkgver` / `pkgrel` | 5.13.0 / 0 |
| `arch` | `noarch` |
| `license` | CC0-1.0 |
| `options` | `!check` (no checks) |
| `builddir` | `fdm_materials-5.13.0` |

### Build dependencies

```
cmake samurai
```

### Source

- `https://github.com/Ultimaker/fdm_materials/archive/refs/tags/5.13.0.tar.gz`

### Configure flags

```sh
cmake3.5 -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr
```

`cmake3.5` is an aports compatibility wrapper; Alpine's normal `cmake` works.
The package installs material and quality JSON files under Cura's resource
tree.

### Package steps

```sh
DESTDIR="$pkgdir" cmake --install build
```

---

## 8. Cross-package constraints

1. **Version lockstep in the baseline.** The Cura APKBUILD warns that `cura`,
   `uranium` and `curaengine` must be updated together. `libarcus` and
   `py3-arcus` are also a pair. The target stack keeps the same lockstep rule,
   but with 5.14.0 / 5.11.1 / 5.12.0 versions from the target conandata.
2. **armhf is not viable.** Cura says armhf is blocked by Uranium; Uranium says
   it is blocked by py3-qt6. Do not add armv7 to the build matrix.
3. **Python version detection.** Cura computes `Python_VERSION` from the
   interpreter running the build. In a Dockerfile, hard-code the value that
   matches the runtime image (3.14 on current Alpine edge) or derive it with the
   same `python3 -c` expression.
4. **Install prefixes.** Every component expects `/usr`. Cura's
   `-DURANIUM_DIR=/usr/share/uranium` and CuraEngine's runtime search path both
   assume the standard prefix; using `/usr/local` requires extra flags.
5. **`py3-uvula` is the missing edge.** Add it to Uranium's `depends` when the
   package is created; otherwise the dependency chain looks complete while the
   runtime is still broken.

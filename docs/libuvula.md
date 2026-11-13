# The missing `pyUvula` dependency

This document explains why Cura needs `pyUvula`, what `libUvula` is, how it is
built upstream, and how the Dockerfile builds it from source on Alpine. The
image does not use Alpine's packaged Cura stack.

## 1. Failure chain

### 1.1 Uranium imports `pyUvula` at module load

`Uranium/UM/Mesh/MeshData.py`, line 20 (Uranium 5.14.0 and earlier):

```python
import pyUvula as uvula
```

There is no `try`/`except` around the import. The module is imported by Uranium
core code, so any tool that imports `UM.Mesh.MeshData` — including Cura's
startup path — fails immediately:

```
File ".../UM/Mesh/MeshData.py", line 20, in <module>
    import pyUvula as uvula
ModuleNotFoundError: No module named 'pyUvula'
```

`calculateUnwrappedUVCoordinates()` calls `uvula.unwrap(...)`; the UV unwrap
operation is required by the Paint tool and by any workflow that needs
unwrapped UVs.

### 1.2 Cura's PaintTool imports it too

`Cura/plugins/PaintTool/PaintTool.py`, line 10:

```python
import pyUvula as uvula
```

`PaintTool` calls `uvula.project(...)`. Cura loads plugin modules during
startup, so even if Uranium's import were made lazy, PaintTool would still fail.

### 1.3 The reference Alpine packages omit it

The aports reference packages (still at Cura 5.13.0) show the gap. Alpine edge
`testing` contains:

- `cura` 5.13.0-r0 (built 2026-09-30, aports commit `be83622f`)
- `uranium` 5.13.0-r0 (aports commit `cda1d27a`)
- `curaengine` 5.13.0-r0
- `py3-arcus` 5.3.0, `py3-pynest2d` 5.3.0, `fdm-materials` 5.13.0

There is **no** `uvula`, `libuvula`, `py3-uvula`, or `pyUvula` package in
`aports` or in the Alpine binary repositories. The `uranium` APKBUILD does not
list `py3-uvula` in `depends`, and the `cura` APKBUILD does not either. The
package therefore builds but cannot run. This is the reported failure.

## 2. What libUvula is

Repository: <https://github.com/Ultimaker/libUvula>

- Standalone UV-unwrapping library extracted from Cura's mesh code.
- License: **LGPL-3.0** (the bundled `src/xatlas.cpp` is MIT, Jonathan Young).
- C++20, CMake >= 3.23.
- Directories: `include/`, `src/`, `pyUvula/`, `UvulaJS/`, `cli/`.
- Outputs:
  - static library `libuvula.a`
  - Python extension `pyUvula` (pybind11 + NumPy)
  - optional JavaScript bindings (`UvulaJS`)
  - optional CLI (`cli`, needs assimp and cxxopts)

### 2.1 Upstream build system

Top-level `CMakeLists.txt`:

- `find_package(standardprojectsettings REQUIRED)`
- `find_package(spdlog REQUIRED)`
- `find_package(range-v3 REQUIRED)`
- `find_package(clipper REQUIRED)`
- `option(WITH_PYTHON_BINDINGS ... ON)`
- `option(WITH_JS_BINDINGS ... OFF)`
- `option(WITH_CLI ... OFF)`
- Requires `UVULA_VERSION` (fatal error if not passed).
- Calls Ultimaker helper functions `use_threads()`, `enable_sanitizers()`, and
  `set_project_warnings()`.
- Builds a **static** `libuvula`.
- **Has no `install()` rules.**

`pyUvula/CMakeLists.txt`:

- `find_package(Python COMPONENTS Interpreter Development REQUIRED)`
- `find_package(pybind11 REQUIRED)`
- `pybind11_add_module(pyUvula pyUvula.cpp)`
- links `libuvula` and `stdc++`
- applies `pybind11_strip`
- **Has no `install()` rules either.**

`pyUvula` exposes:

- `__version__` (`PYUVULA_VERSION`)
- `unwrap(...)`
- `project(...)`
- `connectFaces(...)`
- `checkDownwardsFeatures(...)`
- `getConnectedFaces(...)`

### 2.2 Upstream dependencies

From libUvula's Conan data and recipe:

| Dependency | Upstream version |
| --- | --- |
| spdlog | 1.17.0 |
| range-v3 | 0.12.0 |
| clipper | 6.4.2 (`@ultimaker/stable`) |
| pybind11 | 2.11.1 |
| CPython (bindings) | 3.12.7 |
| assimp, cxxopts | CLI only |

Conan >= 2.7 is required upstream. Building with Conan on Alpine/musl would
compile CPython and all dependencies from source (no binary cache), which is
slow and fragile. The Dockerfile should use Alpine's system packages instead.

## 3. Version pinning problem

`libUvula` has **no git tags and no GitHub releases**. Uranium 5.14.0's
`conandata.yml` requires `uvula/1.1.0`, and `main` currently reports `1.1.0`,
but there is no tag to pin. The exact source commit is therefore not directly
discoverable.

Known `conandata.yml` history on `main`:

| Version | Date | Commit |
| --- | --- | --- |
| 1.0.0 | 2025-07-08 | `282cd4b` |
| 1.0.1 | 2026-02-11 | `b33686b` |
| 1.1.0 | 2026-03-01 | `dfb8ec9` |

Cura 5.14.0 uses the 1.1.0 line. The 1.0.1 entries in the table above are kept
as history. The current `main` commit (`d15219e`, October 2026) reports 1.1.0;
use that tree unless a build log identifies the exact commit packaged for Cura
5.14.0.

**Recommendation:** pin the 1.1.0 tree and pass the version explicitly:

```
-DUVULA_VERSION=1.1.0
-DPYUVULA_VERSION=1.1.0
```

Then verify:

```sh
python3 -c 'import pyUvula; print(pyUvula.__version__)'
# must print 1.1.0
```

Do not move to a newer `main` without checking compatibility against Uranium
5.14.0 and Cura 5.14.0.

Open item: confirm the exact source commit from the Cura 5.14 AppImage's
`pyUvula` binary, or from Ultimaker's build logs, before freezing the
Dockerfile. If that is not possible, `d15219e` is the best-supported starting
point and must be recorded with its SHA in the Dockerfile.

## 4. Alpine adaptation

Alpine does not ship `standardprojectsettings`; CuraEngine's APKBUILD already
works around this. libUvula needs a similar patch set.

### 4.1 Required changes

1. **Remove the Ultimaker helper package**
   - Delete `find_package(standardprojectsettings REQUIRED)`.
   - Remove `use_threads()`, `enable_sanitizers()`, and
     `set_project_warnings()`.
   - `standardprojectsettings` also set the C++ standard. Without it the build
     falls back to the compiler default and `pyUvula.cpp` fails on `std::span`
     (`only available from C++20 onwards`). Add explicitly:
     ```cmake
     set(CMAKE_CXX_STANDARD 20)
     set(CMAKE_CXX_STANDARD_REQUIRED ON)
     set(CMAKE_CXX_EXTENSIONS OFF)
     set(CMAKE_POSITION_INDEPENDENT_CODE ON)
     ```
   - `libuvula` is a static library that is linked into the `pyUvula` shared
     module. Without `CMAKE_POSITION_INDEPENDENT_CODE` the link fails with
     `relocation R_X86_64_TPOFF32 ... can not be used when making a shared
     object; recompile with -fPIC`.
   - Link `Threads::Threads` explicitly (via `find_package(Threads REQUIRED)`)
     if the code uses `std::thread`.

2. **Use Alpine's clipper**
   - Alpine's `clipper` package installs `clipper.hpp` and `libpolyclipping`,
     but no CMake config and no `clipper::clipper` target.
   - Reuse `cmake/FindClipper.cmake` from the CuraEngine APKBUILD
     (`cmake-helpers.patch`). It defines `Clipper::Clipper`.
   - Replace `find_package(clipper REQUIRED)` with
     `find_package(Clipper REQUIRED)` and link `Clipper::Clipper`.

3. **Add install rules**
   - Top level: install headers and `libuvula.a` only if a `libuvula-dev`
     package is planned; for the Dockerfile only the Python module is required.
   - `pyUvula/CMakeLists.txt`:
     ```cmake
     include(GNUInstallDirs)
     install(TARGETS pyUvula
             LIBRARY DESTINATION ${Python_SITELIB}
             RUNTIME DESTINATION ${Python_SITELIB})
     ```
     `${Python_SITELIB}` comes from Uranium's patched `FindPython` usage; if it
     is not defined, compute it:
     ```cmake
     execute_process(
       COMMAND ${Python_EXECUTABLE} -c
               "import sysconfig; print(sysconfig.get_path('platlib'))"
       OUTPUT_VARIABLE Python_SITELIB
       OUTPUT_STRIP_TRAILING_WHITESPACE)
     ```

4. **Pass all required defines**
   ```
   -DUVULA_VERSION=1.1.0
   -DPYUVULA_VERSION=1.1.0
   -DWITH_PYTHON_BINDINGS=ON
   -DWITH_JS_BINDINGS=OFF
   -DWITH_CLI=OFF
   -DEXTENSIVE_WARNINGS=OFF
   -DCMAKE_BUILD_TYPE=Release
   -DCMAKE_INSTALL_PREFIX=/usr
   ```

5. **Python 3.14 / pybind11 3.x**
   - Upstream targets pybind11 2.11.1; Alpine has 3.0.4. The basic
     `pybind11_add_module` + NumPy API used by `pyUvula.cpp` should compile, but
     this must be verified.
   - If a compatibility patch is needed, keep it separate
     (`pybind11-3.patch`) so it can be dropped later.

### 4.2 Suggested patch layout

| Patch | Purpose |
| --- | --- |
| `cmake.patch` | Remove `standardprojectsettings` and helper calls; set C++20; switch to `Clipper::Clipper`; add `Threads::Threads` |
| `cmake-install.patch` | Add `install()` for the `pyUvula` extension (and optionally headers/library) |
| `pybind11-3.patch` | Only if pybind11 3.x requires source changes |

The `FindClipper.cmake` file can be copied verbatim from
[community/curaengine/cmake-helpers.patch](https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/community/curaengine/cmake-helpers.patch).

### 4.3 Install layout

```
/usr/lib/python3.14/site-packages/pyUvula.cpython-314-x86_64-linux-musl.so
```

Confirm the exact filename and directory with:

```sh
python3 -c 'import sysconfig; print(sysconfig.get_path("platlib"))'
```

PyUvula statically links `libuvula.a`, so there is no `libuvula.so` runtime
dependency. The extension does depend on `libstdc++`, `libgcc`, `libm`, and
`libc` (musl), all present in the runtime image.

### 4.4 Static vs shared linking

The Dockerfile keeps the static link. `pyUvula` is the only consumer of
`libUvula`, so a shared `libuvula.so` would add a separate file and a dynamic
dependency without reducing the total tarball size or improving runtime
performance measurably. The release `SOURCES-<tag>.txt` publishes the exact
libUvula source ref, and the patches live in this repository, which is the
relinking path required by the LGPL. Switching to a shared library later means
building libUvula with `BUILD_SHARED_LIBS=ON`, installing the shared object, and
adding it to the release export allowlist.

## 5. Packaging proposal for Alpine

The clean fix is two new APKBUILDs (or one split package), not a Docker-only
hack:

- `libuvula` (LGPL-3.0-or-later)
  - `makedepends`: `cmake samurai spdlog-dev range-v3-dev clipper-dev`
  - `depends`: `so:libstdc++.so.6`, `so:libgcc_s.so.1`
  - Build static library; install headers and CMake config only in `-dev`.
- `py3-uvula`
  - `depends`: `libuvula`, `python3`, `py3-numpy`
  - `makedepends`: `libuvula-dev py3-pybind11 python3-dev cmake samurai`
  - Install the extension into Python's `platlib`.
- `uranium` should then add `py3-uvula` to `depends`.
- `cura` inherits it through `uranium`.

This is also the right place for the patches: keep them in the APKBUILD, and
let the Dockerfile consume the same patch files so the two do not diverge.

## 6. Verification

Build-time:

```sh
python3 -c 'import pyUvula; print(pyUvula.__version__)'
python3 -c 'import pyUvula; print(pyUvula.unwrap.__doc__)'
python3 -c 'from UM.Mesh.MeshData import MeshData; print("UM import ok")'
python3 -c 'import cura; print("Cura import ok")'
```

Functional smoke test (small mesh, no GUI needed):

```python
import numpy as np, pyUvula
# signature/argument details to be taken from pyUvula.cpp; the goal is to
# exercise unwrap() and confirm it returns finite UVs.
```

Runtime:

```sh
QT_QPA_PLATFORM=offscreen timeout 30 cura
```

A successful startup should show no `ModuleNotFoundError` and no traceback.
Because Cura is a GUI application, a clean offscreen run may still exit with a
Qt platform error on some images; treat any Python traceback as a failure and
platform-plugin errors separately. Cura may ignore `SIGTERM`, so if `timeout`
does not return, start Cura in the background and kill it after 30 seconds.

## 7. Open questions

1. **Exact source commit**: is `d15219e` the tree Ultimaker built for Cura 5.14?
   The version string alone (`1.1.0`) does not identify the commit.
2. **pybind11 3.x**: does `pyUvula.cpp` compile unchanged against 3.0.4?
3. **Python 3.14**: any removed C-API or NumPy 2.x issues?
4. **musl**: static `libuvula.a` + C++20 should be fine, but xatlas uses
   `std::thread`; confirm threading works in the Alpine build.
5. **LGPL compliance**: `pyUvula` statically links LGPL code. The exact source
   and patches are published with each release; a shared `libuvula` remains an
   option if relinking needs to be simpler.

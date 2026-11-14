# Upstream versions

The image builds the latest upstream releases from source. This page records the
versions observed during implementation and the mapping rules. The Dockerfile
keeps these as `--build-arg` defaults; the release workflow re-resolves them
from the Cura/Uranium/CuraEngine `conandata.yml` files on every run. See
[`release-pipeline.md`](release-pipeline.md).

## Base image

`alpine:latest` currently resolves to **Alpine 3.24.3**, which is what the
manually verified image uses. Alpine's `latest-stable` release feed reports
**3.24.4** (`branch: v3.24`); the release workflow builds with
`ALPINE_IMAGE=alpine:3.24.4` so the base matches the version in the release tag.
The Cura stack is built against the Python, Qt 6, compiler and libraries shipped
by that Alpine branch.

## Latest UltiMaker release

The latest Cura GitHub release at the time of writing is **5.14.0**.

Cura 5.14.0's `conandata.yml` requires:

| Component | Version |
| --- | --- |
| Cura | 5.14.0 |
| Uranium | 5.14.0 |
| CuraEngine | 5.14.0 |
| fdm-materials | 5.14.0 |
| cura_binary_data | 5.14.0 |
| cura_resources | 5.14.0 |
| pynest2d | 5.11.0-alpha.0 |
| pysavitar | 5.12.0 |
| dulcificum | 5.11.0-alpha.0 |
| shapely | 2.1.2 |

Uranium 5.14.0 requires:

| Component | Version |
| --- | --- |
| pyArcus | 5.12.0 |
| libUvula | 1.1.0 |
| Qt | 6.10.0 (upstream build) |

CuraEngine 5.14.0 requires:

| Component | Version |
| --- | --- |
| Arcus | 5.11.1 |
| Scripta | >= 1.1.0 |
| libpng | 1.6.48 |
| oneTBB | 2022.3.0 |
| zeus_expected | >= 1.1.1 |
| cura-formulae-engine | 1.2.1 |

## libUvula

libUvula has no tags or GitHub releases. Its `main` `conandata.yml` currently
declares **1.1.0**, matching Uranium 5.14.0. The observed `main` HEAD is
`d15219eb49b7eedb7c2a03ab627e1415c04f79f6` (2026-10-13). Pin this or a later
1.1.0-era commit and verify `pyUvula.__version__ == "1.1.0"`.

## Source refs used by the image

Cura 5.14.0, Uranium, CuraEngine and fdm-materials have public tags. libArcus,
pyArcus, pynest2d and libUvula do not expose the required versions as tags, so
they are pinned to commits whose `conandata.yml` declares the required version.

| Component | Version | Ref | Commit |
| --- | --- | --- | --- |
| Cura | 5.14.0 | tag `5.14.0` | `16c219ec22c2ae4bb6beb3f6c464fb43c618373b` |
| Uranium | 5.14.0 | tag `5.14.0` | `1da09067406231d057e5415a4f3638dcc43754ce` |
| CuraEngine | 5.14.0 | tag `5.14.0` | `05c5d9b0286d14af7c8b9d4081b245c2e3ab1ef8` |
| fdm-materials | 5.14.0 | tag `5.14.0` | `55830cd7dc340e8c03f9c1c2e5e824372e584f19` |
| libArcus | 5.11.1 | `main` | `339c85a1abc7554e6c19bd36bbbc4c2d6f9f40b6` |
| pyArcus | 5.12.0 | `main` | `72d052a24b9ecaba8821182cd6e84c04d9b3f3fe` |
| pynest2d | 5.11.0-alpha.0 | `main` | `73235af569bd36bb8c60e659f75057bd559426d8` |
| libnest2d | 5.11.0-alpha.0 | `main` | `1c9dc3c05005cadcbc2b49062c3d37b60e962c7f` |
| libUvula | 1.1.0 | `main` | `d15219eb49b7eedb7c2a03ab627e1415c04f79f6` |
| CuraFormulaeEngine | 1.2.1 | `main` | `c1257dd638dc7dc86377bb5aadd27803de008a59` |
| Scripta | 1.1.0-alpha.0 | `main` | `b96045cd9b531d97f42dec8c9a0ef52f773f6b90` |
| zeus_expected | 1.4.0 | tag `v1.4.0` | tag |
| lexy | 2025.05.0 | tag `v2025.05.0` | tag |
| geometry.hpp | 2.0.3 | tag `v2.0.3` | tag |
| wagyu | 0.5.0 | tag `0.5.0` | tag |

Each commit was verified against the `conandata.yml` it contains: libArcus
declares `5.11.1`, pyArcus `5.12.0`, pynest2d and libnest2d
`5.11.0-alpha.0`, libUvula `1.1.0`, CuraFormulaeEngine `1.2.1`. Scripta's
`main` declares `1.1.0-alpha.0`; there is no `1.1.0` tag on
`Ultimaker/Scripta_public` (only `0.1.0`). Because these are `main` commits,
re-verify them when bumping Cura and record the new SHA in the Dockerfile and
in this table.

## Additional build dependencies

CuraEngine 5.14.0 links `cura-formulae-engine`, which upstream distributes only
through its private Conan channel. The source is public as
[`Ultimaker/CuraFormulaeEngine`](https://github.com/Ultimaker/CuraFormulaeEngine),
so the Dockerfile builds commit `c1257dd6` (declared version `1.2.1`) and
installs a small CMake package config for the imported target CuraEngine
expects.

CuraFormulaeEngine needs two libraries that Alpine does not package:

- [`zeus-cpp/expected`](https://github.com/zeus-cpp/expected) `v1.4.0`
  (package `zeus_expected`, exported target `zeus::expected`).
- [`foonathan/lexy`](https://github.com/foonathan/lexy) `v2025.05.0`
  (exported target `foonathan::lexy`).

libnest2d is not packaged by Alpine 3.24 (`libnest2d`/`libnest2d-dev` are
absent; the 0.4 recipe in aports is the old tamasmeszaros fork and does not
match pynest2d 5.11's `libnest2d/backends/...` include layout). The Dockerfile
uses `Ultimaker/libnest2d` `main`, which is header-only at this commit, and
copies `include/libnest2d` into `/usr/include`.

Alpine 3.24 also lacks `py3-numpy-stl` and `py3-trimesh`. Uranium requires
numpy-stl, and Cura's TrimeshReader plugin imports trimesh, so the builder
installs both with pip (`--no-deps`) together with numpy-stl's own runtime
requirements, `python-utils` and `typing-extensions`. The runtime stage copies
their site-packages directories.

Alpine's `py3-pybind11` package is split: the main package ships
`pybind11Config.cmake` under site-packages, but the headers are in
`py3-pybind11-dev` under `/usr/include`. The config hardcodes
`site-packages/pybind11/include`, so CMake fails with "includes non-existent
path". The Dockerfile therefore installs the `pybind11==3.0.1` pip wheel, which
ships the CMake config and the headers in the same directory, and passes
`-Dpybind11_DIR="$(python3 -m pybind11 --cmakedir)"` when configuring libUvula.

Cura 5.14.0's `conandata.yml` lists `pysavitar/5.12.0` and
`dulcificum/5.11.0-alpha.0`; the bundled 3MFWriter and MakerbotWriter plugins
import them at startup. Neither component nor its C++ dependency has a usable
5.12.0/5.11.0 tag, so the Dockerfile pins the `main` commits that declare those
versions:

| Component | Repository | Version | Pinned commit |
| --- | --- | --- | --- |
| libSavitar | `Ultimaker/libSavitar` | 5.12.0 | `c513049b0866d6903826c9be46dd84deb12ffcba` |
| pySavitar | `Ultimaker/pySavitar` | 5.12.0 | `74cbe2bd365c6f3397b385e879139b012059c487` |
| dulcificum | `Ultimaker/synsepalum-dulcificum` | 5.11.0-alpha.0 | `f81c0ea950cdd2f24195620e7eb8fd057b6c194e` |

Dulcificum needs `ctre/3.7.2`, which Alpine 3.24 does not package. The build
uses tag `v3.7.2` of `hanickadot/compile-time-regular-expressions`; keep it in
sync with the `ctre` requirement in Dulcificum's `conanfile.py`.

libSavitar and pySavitar ship no install rules or `savitarConfig.cmake`, so the
build patches add a package config, the shared library and the headers. The
exported target is `savitar::savitar`, which is what pySavitar links, and the
config re-finds `pugixml` because the library is linked against it publicly.
Dulcificum has no license file; its source archive is published in the release
`SOURCES` file.

## fdm-materials

Cura 5.14.0 requires `fdm_materials/5.14.0`, which corresponds to source tag
`5.14.0` on `Ultimaker/fdm_materials`. The GitHub "latest release" API reports
an older `v10.9.1-0`; the source tag is the authoritative reference.

## Pinning policy

- The Dockerfile defaults pin Cura, Uranium, CuraEngine and fdm-materials to
  their exact `5.14.0` tags, and libArcus, pyArcus, libSavitar, pySavitar,
  dulcificum, pynest2d, libnest2d, libUvula, CuraFormulaeEngine and Scripta to
  the exact commits that satisfy the Conan versions above.
- ctre is pinned to `v3.7.2`, the version Dulcificum's `conanfile.py` requires.
- zeus_expected, lexy, geometry.hpp and wagyu are resolved from their GitHub
  `releases/latest` tag, or the newest git tag when that is newer. They are
  included in the release dependency hash because the Dockerfile builds them
  from source.
- The release workflow resolves the same components from the current
  `conandata.yml` chain: use the exact tag when it exists, otherwise the head of
  `main`/`master`. It never commits the resolved refs back.
- Re-verify the commit/`conandata.yml` mapping whenever Cura publishes a new
  release; component versions are not independent.

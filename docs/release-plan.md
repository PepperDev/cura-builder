# Release pipeline

The repository publishes prebuilt Cura tarballs from GitHub Actions. The
workflow is [`.github/workflows/release.yml`](../.github/workflows/release.yml);
the version-resolution and packaging logic lives in [`scripts/`](../scripts).

Releases are **not tied to commits in this repository**. They track external
resources: the latest Cura release, its dependencies, the Alpine release and the
Alpine package indexes. Several releases can therefore point at the same
repository commit. GitHub allows multiple tags and releases on one commit; each
release carries its own assets.

Deleting a release happens only for manual runs, where replacing the existing
release is intentional. Scheduled runs never delete a release or tag.

## Triggers

| Trigger | Behaviour |
| --- | --- |
| `schedule` (daily cron, `17 4 * * *` UTC) | Resolve the current tag. If a release with that tag already exists, stop. Otherwise build and publish. |
| `workflow_dispatch` (manual) | Resolve the current tag, skip the existence check, build, and replace any existing release/tag with the same name. |

The cron expression is deliberately off the top of the hour to avoid GitHub's
scheduler congestion.

## Tag scheme

```text
<cura-tag>-<deps-hash>-alpine-<alpine-version>-<apkindex-hash>
```

Example:

```text
5.14.0-1a2b3c4-alpine-3.24.4-9f8e7d6
```

### Cura tag

```sh
gh api repos/UltiMaker/Cura/releases/latest --jq .tag_name
```

### Dependency hash

Seven hex characters of the SHA-256 of the resolved refs of every dependency,
one per line, excluding Cura itself:

```text
Uranium, CuraEngine, fdm_materials, pynest2d, libArcus, pyArcus,
libnest2d, libUvula, CuraFormulaeEngine, Scripta,
zeus_expected, lexy, geometry.hpp, wagyu
```

The last four are not UltiMaker projects, but the Dockerfile downloads and
builds them from source, so their refs are part of the hash. Dependencies that
come from Alpine repositories (`python3`, PyQt6/Qt, protobuf, boost, clipper,
nlopt, spdlog, fmt, oneTBB, ...) are covered by the APKINDEX hash below; their
changes already produce a new tag.

### Alpine version and repository hash

The workflow fetches:

```text
https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml
```

and reads the first `version:` and `branch:` fields (currently `3.24.4` and
`v3.24`). The branch selects the package repositories:

```text
https://dl-cdn.alpinelinux.org/alpine/<branch>/main/x86_64/APKINDEX.tar.gz
https://dl-cdn.alpinelinux.org/alpine/<branch>/community/x86_64/APKINDEX.tar.gz
```

The repository hash is the first seven hex characters of the SHA-256 of the two
`APKINDEX.tar.gz` files concatenated in that order:

```sh
(
  curl -fsSL .../main/x86_64/APKINDEX.tar.gz
  curl -fsSL .../community/x86_64/APKINDEX.tar.gz
) | sha256sum | cut -c1-7
```

This makes the tag change when Alpine publishes updated packages, even if the
Alpine version string stays the same.

## Dependency resolution

The workflow does **not** use `releases/latest` blindly for the UltiMaker
dependencies: several of those repositories have stale releases or no tags at
all. Instead:

1. Read the Cura `conandata.yml` at the Cura tag. It declares the required
   versions (`uranium/5.14.0`, `curaengine/5.14.0`, `fdm_materials/5.14.0`,
   `pynest2d/5.11.0-alpha.0`, ...).
2. For each dependency, use the exact version as a git tag if
   `refs/tags/<version>` exists. Otherwise use the head commit of `main`
   (falling back to `master`).
3. Read the Uranium and CuraEngine `conandata.yml` files to obtain the pyArcus,
   libUvula, libArcus and Scripta requirements.
4. Warn when a resolved `main` commit declares a different version from the one
   the parent component requires.

Current consequences of that rule:

| Component | Resolution |
| --- | --- |
| Cura, Uranium, CuraEngine, fdm_materials | release tag (`5.14.0`) |
| libArcus, pyArcus, pynest2d, libnest2d, libUvula, CuraFormulaeEngine | `main` commit (no matching tag) |
| Scripta | `main` commit (no 1.1.0 tag) |
| zeus_expected, lexy, geometry.hpp, wagyu | latest GitHub release tag; the newest git tag wins when it is newer |

The last row is resolved with `gh api .../releases/latest --jq .tag_name`, then
checked against the newest git tag. `mapbox/wagyu` publishes `0.5.0` as a tag
but its latest GitHub release is `0.2.1`; CuraEngine requires `0.5.0`, so the
newest tag is used. These components are not UltiMaker projects, but they are
built from source and are part of the dependency hash.

The Dockerfile keeps the last manually verified refs as build-argument
defaults. The workflow passes the resolved refs with `--build-arg`; nothing is
committed back to the repository.

## Build

The workflow builds the final stage only, with the resolved arguments:

```sh
docker build \
  --build-arg ALPINE_IMAGE=alpine:<alpine-version> \
  --build-arg CURA_REF=<cura-tag> \
  --build-arg CURA_VERSION=<cura-tag> \
  ... \
  -t cura-alpine:<tag> .
```

`ALPINE_IMAGE` is pinned to `alpine:<version>` from `latest-releases.yaml`, not
to the floating `alpine:latest` tag. If that image tag is not available yet,
the build fails rather than silently using a different base.

## Artifact

```text
cura-<tag>-linux-x86_64.tar.gz
cura-<tag>-linux-x86_64.tar.gz.sha256
SOURCES-<tag>.txt
```

The tarball contains only files produced by the build:

| Path | Origin |
| --- | --- |
| `/usr/bin/cura` | Cura install (`cura_app.py` renamed) |
| `/usr/bin/CuraEngine` | CuraEngine install |
| `/usr/lib/cura/` | Cura plugins, QML and application data |
| `/usr/lib/uranium/` | Uranium plugins and QML |
| `/usr/lib/libArcus.so*` | libArcus |
| `/usr/lib/libcura-formulae-engine.so*` | CuraFormulaeEngine |
| `/usr/lib/python3.14/site-packages/UM/` | Uranium Python package |
| `/usr/lib/python3.14/site-packages/cura/` | Cura Python package |
| `/usr/lib/python3.14/site-packages/pyArcus.so`, `.pyi` | pyArcus |
| `/usr/lib/python3.14/site-packages/pynest2d*` | pynest2d |
| `/usr/lib/python3.14/site-packages/pyUvula*` | pyUvula |
| `/usr/lib/python3.14/site-packages/stl/`, `numpy_stl*` | numpy-stl |
| `/usr/lib/python3.14/site-packages/trimesh/` | trimesh |
| `/usr/lib/python3.14/site-packages/python_utils/`, `typing_extensions.py` | numpy-stl runtime deps |
| `/usr/share/cura/` | Cura resources, definitions, materials |
| `/usr/share/uranium/` | Uranium resources and CMake helpers |
| `/usr/share/locale/` | Cura translations |
| `/usr/share/licenses/cura-alpine/` | license texts of everything built |

The export uses `docker create` + `tar` + `docker cp` with that allowlist. It
must **never** use `docker export` of the whole container: that would include
every Alpine package installed in the runtime stage.

## What the tarball does not contain

The runtime image installs these with `apk`; they are third-party packages and
are excluded from the artifact:

- `python3` and the Python standard library;
- `py3-qt6`, `PyQt6`, `py3-numpy`, `py3-scipy`, `py3-cryptography`,
  `py3-pyclipper`, `py3-zeroconf`, `py3-pyserial`, `py3-requests`,
  `py3-keyring`, `py3-networkx`;
- Qt 6 runtime, QML, SVG, translations and image-format modules;
- Mesa (`mesa-gl`, `mesa-dri-gallium`);
- X11/Wayland client libraries;
- fonts (`font-noto`, `font-dejavu`);
- `libstdc++`, `protobuf`, `onetbb`, `libpng`, `clipper`, `nlopt`, `spdlog`,
  `fmt`, `boost-libs` and other transitive runtime dependencies.

Release notes instruct users to install them first:

```sh
apk add python3 py3-qt6 py3-numpy py3-scipy py3-cryptography \
    py3-pyclipper py3-zeroconf py3-pyserial py3-requests py3-keyring \
    py3-networkx libstdc++ \
    protobuf onetbb libpng clipper nlopt spdlog fmt boost-libs \
    qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qt5compat \
    qt6-qtimageformats qt6-qttranslations \
    mesa-dri-gallium mesa-gl \
    libx11 libxkbcommon libxcb libxi libxrender libsm libice libxext \
    font-noto font-dejavu
```

Then:

```sh
sudo tar -xzf cura-<tag>-linux-x86_64.tar.gz -C /
cura
```

The tarball uses absolute `/usr/...` paths, so extraction requires root.

## Platforms

The pipeline currently builds `linux/amd64` (`x86_64`) only. The Dockerfile
itself is architecture-neutral, but the workflow runs on `ubuntu-latest` and
names the artifact accordingly.

Future targets, in no particular order: `x86` (i386), `armhf`, `armv7` and
`aarch64`. `aarch64` and `armv7` need a native runner or QEMU; `armhf` is
currently blocked by upstream packaging metadata (`cura`/`uranium` are
`noarch !armhf`) and would need a source-level check. Each architecture must
produce its own artifact name and its own APKINDEX hash.

## Python version

The Dockerfile and the tarball paths hardcode Python 3.14
(`/usr/lib/python3.14/site-packages`), because that is what Alpine 3.24 ships.
A future release should detect the interpreter's `site-packages` path during
the build and use it for the runtime `COPY` steps and the export allowlist
instead of hardcoding it. Until then, an Alpine minor that changes Python
fails the build at those `COPY` steps, which is the intended loud failure.

## Licensing requirements

The repository's MIT license covers only the build files. The tarball
redistributes LGPL-3.0-or-later (Cura, Uranium, libArcus, pynest2d, libUvula),
AGPL-3.0-or-later (CuraEngine), and other upstream code. The pipeline must:

- ship `/usr/share/licenses/cura-alpine/`, populated by the Dockerfile from
  every built source tree, plus this repository's `LICENSE`;
- attach `SOURCES-<tag>.txt` with the exact tags/commits and upstream URLs, and
  point at the repository tag for the patches used;
- satisfy the AGPL for CuraEngine by providing its complete corresponding
  source;
- keep the LGPL relinking possibility. `pyUvula` currently links `libUvula`
  statically. That is retained because `pyUvula` is the only consumer: a shared
  `libUvula.so` would add a separate file and a dynamic-link dependency without
  reducing the total tarball size or improving runtime performance measurably.
  Relinking is supported by publishing the exact libUvula source ref in
  `SOURCES-<tag>.txt` and the patches in this repository. If a shared library is
  wanted later, build `libUvula` with `BUILD_SHARED_LIBS=ON`, install it, and
  add it to the export allowlist;
- note that Cura runs with GPL-licensed PyQt6 installed by the user. The Cura
  application as distributed must be usable under GPL-3.0-compatible terms; do
  not add restrictions that conflict with that;
- use a distinct project name and state that the build is unofficial and not
  endorsed by UltiMaker. The licenses do not grant trademark rights.

## Limitations and open questions

- A new Alpine minor release can change Python or Qt in a way that breaks the
  hardcoded `python3.14` paths. The build fails loudly; the Dockerfile and the
  tarball paths must then be updated (see "Python version").
- Manual runs delete and recreate an existing release with the same tag. This is
  intentional: it is how a rebuild of the same external version set is
  published. The deletion only happens for manual runs; scheduled runs never
  delete anything.
- Several release tags can point at the same repository commit. That is
  expected: releases track external resources, not commits in this repository.
  GitHub allows multiple tags and releases on one commit, each with its own
  assets.
- The first release for a new architecture needs the workflow matrix and
  artifact naming extended; the current job builds one platform.
- Switch `pyUvula` to a shared `libUvula` to simplify LGPL relinking?

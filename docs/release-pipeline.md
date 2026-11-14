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
| `schedule` (daily cron, `17 4 * * *` UTC) | Resolve the current build id. If a published release already contains `cura-<build-id>-linux-x86_64.tar.gz`, stop. Otherwise build and publish. |
| `workflow_dispatch` (manual) | Resolve the current build id, skip the existence check, build, and replace any existing release/tag with the same name (a re-run of the same workflow run reuses its run number, so the tag can already exist). |

The cron expression is deliberately off the top of the hour to avoid GitHub's
scheduler congestion.

## Tag scheme

Two strings are derived from the resolved inputs:

```text
release tag:  <cura-tag>-<run-number>-<deps-hash>-alpine-<alpine-version>-<apkindex-hash>
build id:     <cura-tag>-<deps-hash>-alpine-<alpine-version>-<apkindex-hash>
```

Example:

```text
tag:       5.14.0-128-1a2b3c4-alpine-3.24.4-9f8e7d6
build id:  5.14.0-1a2b3c4-alpine-3.24.4-9f8e7d6
```

`<run-number>` is `github.run_number`. It exists only in the git tag. The two
hashes are random, so sorting releases by tag name would otherwise put builds of
the same Cura version in an arbitrary order; the run number makes that order
match the order in which the builds ran. Everything else — artifact file names,
image tags, `SOURCES-*.txt` and the release title — uses the build id, so the
same external inputs always produce the same file names.

`RUN_NUMBER` can be overridden in the environment (the scripts fall back to
`GITHUB_RUN_NUMBER` and then to `0`) for local runs.

### Cura tag

```sh
gh api repos/UltiMaker/Cura/releases/latest --jq .tag_name
```

### Dependency hash

Seven hex characters of the SHA-256 of the resolved refs of every dependency,
one per line, excluding Cura itself:

```text
Uranium, CuraEngine, fdm_materials, pynest2d, libArcus, pyArcus,
libSavitar, pySavitar, dulcificum, ctre,
libnest2d, libUvula, CuraFormulaeEngine, Scripta,
zeus_expected, lexy, geometry.hpp, wagyu
```

The last five are not UltiMaker projects, but the Dockerfile downloads and
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

This makes the build id change when Alpine publishes updated packages, even if
the Alpine version string stays the same.

## Dependency resolution

The workflow does **not** use `releases/latest` blindly for the UltiMaker
dependencies: several of those repositories have stale releases or no tags at
all. Instead:

1. Read the Cura `conandata.yml` at the Cura tag. It declares the required
   versions (`uranium/5.14.0`, `curaengine/5.14.0`, `fdm_materials/5.14.0`,
   `pynest2d/5.11.0-alpha.0`, `pysavitar/5.12.0`, `dulcificum/5.11.0-alpha.0`,
   ...).
2. For each dependency, use the exact version as a git tag if
   `refs/tags/<version>` exists. Otherwise use the head commit of `main`
   (falling back to `master`).
3. Read the Uranium and CuraEngine `conandata.yml` files to obtain the pyArcus,
   libUvula, libArcus and Scripta requirements, and pySavitar's own file for
   libSavitar.
4. Warn when a resolved `main` commit declares a different version from the one
   the parent component requires.

Current consequences of that rule:

| Component | Resolution |
| --- | --- |
| Cura, Uranium, CuraEngine, fdm_materials | release tag (`5.14.0`) |
| libArcus, pyArcus, pynest2d, libnest2d, libUvula, CuraFormulaeEngine | `main` commit (no matching tag) |
| libSavitar, pySavitar | `main` commit (public tags stop at 5.3.0) |
| dulcificum | `main` commit (no 5.11.0-alpha.0 tag) |
| ctre | tag `v3.7.2` (version required by Dulcificum) |
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

The workflow resolves the versions once, in the `resolve` job, and uploads the
resulting `versions.env` as a build artifact. The `build` job then fans out in
parallel:

| Docker platform | Arch | Emulation | Artifact suffix |
| --- | --- | --- | --- |
| `linux/amd64` | `x86_64` | native | `linux-x86_64` |
| `linux/386` | `x86` | native (32-bit on amd64) | `linux-x86` |
| `linux/arm/v7` | `armv7` | QEMU | `linux-armv7` |
| `linux/arm64` | `aarch64` | QEMU | `linux-aarch64` |

`armhf` (`linux/arm/v6`) is deliberately absent: upstream Cura and Uranium are
marked `noarch !armhf`, so it needs a source-level check before it is added.
It remains an explicit future target.

Each matrix job:

1. downloads `versions.env`;
2. for the QEMU rows (`armv7`, `aarch64`), pulls `tonistiigi/binfmt:latest`
   and registers the emulators:
   ```sh
   docker run --privileged --rm tonistiigi/binfmt:latest --install all
   ```
   then verifies the `qemu-aarch64` and `qemu-arm` entries under
   `/proc/sys/fs/binfmt_misc/`;
3. creates a Buildx container builder with
   `docker buildx create --driver docker-container`;
4. runs `PLATFORM=<platform> ARCH=<arch> ./scripts/build-release.sh`, which
   builds with `docker buildx build --load` for non-amd64 platforms and
   `docker build` for amd64;
5. starts the image offscreen, waits 45 seconds and fails on a Python
   traceback;
6. uploads `dist/cura-*.tar.gz` and its checksum as `dist-<arch>`.

The builder stage and runtime stage both use `ALPINE_IMAGE=alpine:<version>`,
pinned from `latest-releases.yaml`, not the floating `alpine:latest` tag. Under
QEMU the same Dockerfile runs unchanged; `apk` selects the target architecture
repositories from the platform.

The build id is shared by every architecture. It is computed from the `x86_64`
APKINDEX only (see above), so an Alpine package change that touches another
architecture without touching `x86_64` would not produce a new build id. That is
an accepted risk; the build still uses the current repositories for its target
architecture.

## Artifact

Users download the package from the
[GitHub releases page](https://github.com/PepperDev/cura-builder/releases).
Each release publishes one tarball per architecture:

```text
cura-<build-id>-linux-x86_64.tar.gz
cura-<build-id>-linux-x86_64.tar.gz.sha256
cura-<build-id>-linux-x86.tar.gz
cura-<build-id>-linux-x86.tar.gz.sha256
cura-<build-id>-linux-armv7.tar.gz
cura-<build-id>-linux-armv7.tar.gz.sha256
cura-<build-id>-linux-aarch64.tar.gz
cura-<build-id>-linux-aarch64.tar.gz.sha256
SOURCES-<build-id>.txt
```

`SOURCES-<build-id>.txt` and `release-notes.md` are generated once in the
`publish` job by `scripts/release-metadata.sh`, after all matrix jobs have
uploaded their packages.

The tarball contains only files produced by the build:

| Path | Origin |
| --- | --- |
| `/usr/bin/cura` | Cura install (`cura_app.py` renamed) |
| `/usr/bin/CuraEngine` | CuraEngine install |
| `/usr/lib/cura/` | Cura plugins, QML and application data |
| `/usr/lib/uranium/` | Uranium plugins and QML |
| `/usr/lib/libArcus.so*` | libArcus |
| `/usr/lib/libcura-formulae-engine.so*` | CuraFormulaeEngine |
| `/usr/lib/libSavitar.so*` | libSavitar |
| `<sitelib>/UM/` | Uranium Python package |
| `<sitelib>/cura/` | Cura Python package |
| `<sitelib>/pyArcus.so`, `.pyi` | pyArcus |
| `<sitelib>/pySavitar*` | pySavitar |
| `<sitelib>/pyDulcificum*` | pyDulcificum |
| `<sitelib>/pynest2d*` | pynest2d |
| `<sitelib>/pyUvula*` | pyUvula |
| `<sitelib>/stl/`, `numpy_stl*` | numpy-stl |
| `<sitelib>/trimesh/` | trimesh |
| `<sitelib>/python_utils/`, `typing_extensions.py` | numpy-stl runtime deps |
| `/usr/share/cura/` | Cura resources, definitions, materials |
| `/usr/share/uranium/` | Uranium resources and CMake helpers |
| `/usr/share/locale/` | Cura translations |
| `/usr/share/licenses/cura-alpine/` | license texts of everything built |

`<sitelib>` is resolved inside the runtime container with
`python3 -c 'import sysconfig; print(sysconfig.get_path("platlib"))'`. On Alpine
3.24 it is `/usr/lib/python3.14/site-packages`.

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

Then, for the artifact matching the machine's architecture:

```sh
sudo tar -xzf cura-<build-id>-linux-<arch>.tar.gz -C /
cura
```

`<arch>` is one of `x86_64`, `x86`, `armv7` or `aarch64`. The tarball uses
absolute `/usr/...` paths, so extraction requires root.

## Verification

The `x86_64` artifact has been extracted into a clean `alpine:3.24.4` container
with only the `apk` packages listed above. `pyUvula` reports 1.1.0, Cura reports
5.14.0, `CuraEngine help` reports 5.14.0, and Cura stays alive in an offscreen
Qt session without a Python traceback.

The `x86` artifact is built natively as a 32-bit binary on the amd64 kernel. The
built image has been checked in place: `getconf LONG_BIT` reports 32, all Python
modules import, `CuraEngine help` reports 5.14.0, and Cura starts offscreen. It
has not been extracted into a separate clean container yet.

The `armv7` and `aarch64` artifacts are built under QEMU and get the same
in-image smoke test, but they have not been extracted into a clean container on
real hardware. Treat them as untested until that is done.

Every matrix job repeats the startup check before uploading its package: it
starts the built image with `QT_QPA_PLATFORM=offscreen`, waits 45 seconds
(longer for the QEMU builds), requires the container to still be running, and
fails on a Python traceback in the logs. A missing or failed architecture stops
the `publish` job, so a release never contains a partial set of tarballs.

## Platforms

The workflow builds four Docker platforms on `ubuntu-latest`:

| Platform | Arch | How |
| --- | --- | --- |
| `linux/amd64` | `x86_64` | native |
| `linux/386` | `x86` | native (32-bit on amd64) |
| `linux/arm/v7` | `armv7` | QEMU user emulation |
| `linux/arm64` | `aarch64` | QEMU user emulation |

`armhf` (`linux/arm/v6`) is skipped for now. Upstream Cura and Uranium are
`noarch !armhf`; adding it requires a source-level check first.

QEMU user emulation is registered with `tonistiigi/binfmt` on the disposable
runner. The registration is kernel-global on that VM, which is acceptable
because the runner is discarded after the job. Native arm64 GitHub runners are
an alternative for `aarch64`; the current matrix intentionally uses QEMU so one
runner label covers every architecture.

Emulated builds are substantially slower than native ones, especially
CuraEngine and the C++ Python bindings. The build job timeout is 360 minutes and
`fail-fast` is disabled so one slow or failing architecture does not cancel the
others.

## Python version

The Python version is not hardcoded. The builder computes
`sysconfig.get_path("platlib")`, installs Uranium/Cura with
`-DPython_VERSION=<major.minor from python3>`, and stages the Python packages in
`/staging/python`. The runtime stage computes the same path with its own Python
and copies the staged packages there. The release export script queries the
path in the runtime container too, so `<sitelib>` follows whatever Python
Alpine installs.

On Alpine 3.24 that path is `/usr/lib/python3.14/site-packages`. An Alpine minor
that changes Python still changes the C-extension ABI, but it no longer needs
edits to `COPY` lines or the export allowlist; the runtime import check fails
the build if the artifacts do not match.

## Licensing requirements

The repository's MIT license covers only the build files. The tarball
redistributes LGPL-3.0-or-later (Cura, Uranium, libArcus, pySavitar, libSavitar,
pynest2d, libUvula), AGPL-3.0-or-later (CuraEngine), Apache-2.0 (ctre), and
other upstream code. Dulcificum's repository declares no license, so the exact
source archive is published and its license status is stated in the release
notes. The pipeline must:

- ship `/usr/share/licenses/cura-alpine/`, populated by the Dockerfile from
  every built source tree, plus this repository's `LICENSE`;
- attach `SOURCES-<build-id>.txt` with the exact tags/commits and upstream URLs, and
  point at the repository tag for the patches used;
- satisfy the AGPL for CuraEngine by providing its complete corresponding
  source;
- keep the LGPL relinking possibility. `pyUvula` currently links `libUvula`
  statically. That is retained because `pyUvula` is the only consumer: a shared
  `libUvula.so` would add a separate file and a dynamic-link dependency without
  reducing the total tarball size or improving runtime performance measurably.
  Relinking is supported by publishing the exact libUvula source ref in
  `SOURCES-<build-id>.txt` and the patches in this repository. If a shared library is
  wanted later, build `libUvula` with `BUILD_SHARED_LIBS=ON`, install it, and
  add it to the export allowlist;
- note that Cura runs with GPL-licensed PyQt6 installed by the user. The Cura
  application as distributed must be usable under GPL-3.0-compatible terms; do
  not add restrictions that conflict with that;
- use a distinct project name and state that the build is unofficial and not
  endorsed by UltiMaker. The licenses do not grant trademark rights.

## Limitations and open questions

- A new Alpine minor release can change Python or Qt. The site-packages path is
  detected, but the C-extension ABI can change; the runtime import check fails
  loudly before a release is published.
- Manual runs delete and recreate an existing release with the same tag. With
  the run number in the tag that only matches when the same workflow run is
  re-run, which is exactly when a stale release has to be replaced. The deletion
  only happens for manual runs; scheduled runs never delete anything.
- Releases of the same Cura version accumulate one per run, because the tag
  carries the run number. The dependency and APKINDEX hashes still identify
  whether the inputs changed, and the scheduled run skips when a release for the
  computed build id already exists.
- Several release tags can point at the same repository commit. That is
  expected: releases track external resources, not commits in this repository.
  GitHub allows multiple tags and releases on one commit, each with its own
  assets.
- The build-id hash uses only the `x86_64` Alpine package indexes. The other
  architectures could theoretically change without changing the build id; this
  is an accepted risk because an index change on only one architecture is
  unlikely.
- QEMU builds are slow. The job timeout is 360 minutes and `fail-fast` is off;
  a very slow architecture can still hit the limit.
- `armhf` (`linux/arm/v6`) is not published. Upstream Cura/Uranium are
  `noarch !armhf`; revisit only after a source-level check.
- The `x86`, `armv7` and `aarch64` packages are not yet manually verified in a
  clean container on real hardware.
- Switch `pyUvula` to a shared `libUvula` to simplify LGPL relinking?

# AGENTS.md

Guidance for agents working in this repository.

## What this project is

This repository builds **UltiMaker Cura** for **Alpine Linux** as a multi-stage
Docker image.

- Stage 1 is `FROM alpine:latest`. It installs the build toolchain and compiles
  the latest upstream UltiMaker releases from source.
- Stage 2 is `FROM alpine:latest`. It installs only the runtime libraries and
  copies the built binaries, plugins, resources and Python packages from stage 1.
- Do **not** use Alpine `edge` Cura packages. Do not `apk add cura uranium
  curaengine py3-arcus py3-pynest2d`. Those packages are reference material only.

Implementation is complete. The Dockerfile builds the latest upstream release
and Cura starts in the runtime image. The release workflow is in
`.github/workflows/release.yml`; its helper scripts are in `scripts/`.

## Repository layout

| Path | Purpose |
| --- | --- |
| `README.md` | Project goal, blocker, document index, approach |
| `docs/upstream-versions.md` | Latest upstream releases and component version mapping |
| `docs/dockerfile-design.md` | Multi-stage design, packages, build order, flags, runtime |
| `docs/libuvula.md` | Why `pyUvula` is required, upstream facts, Alpine patches |
| `docs/reference-apkbuilds.md` | aports APKBUILDs retained as a patch/flag/install-layout baseline |
| `docs/release-plan.md` | Release workflow, tag scheme, tarball contents, excluded Alpine packages, install steps, licensing |
| `Dockerfile` | Multi-stage build, all source refs as `--build-arg` with pinned defaults |
| `patches/` | Per-component patches derived from aports plus the libUvula patch |
| `.github/workflows/release.yml` | Daily/manual release workflow |
| `scripts/resolve-versions.sh` | Resolves Cura, dependencies, Alpine version and tag |
| `scripts/build-release.sh` | Builds the image and exports the release tarball |

The Alpine [aports repository](https://gitlab.alpinelinux.org/alpine/aports) is the reference for patches and
install layout. Link to it; do not vendor a checkout into this repository.

## Current target

- Base image: `alpine:latest` for both stages.
- Latest Cura GitHub release at the time of writing: **5.14.0**.
- Resolve the other components from Cura 5.14.0's `conandata.yml`:
  Uranium 5.14.0, CuraEngine 5.14.0, fdm-materials 5.14.0,
  pynest2d 5.11.0-alpha.0, pysavitar 5.12.0, dulcificum 5.11.0-alpha.0.
- Uranium 5.14.0 requires `pyarcus/5.12.0` and `uvula/1.1.0`.
- CuraEngine 5.14.0 requires `arcus/5.11.1`, Scripta `>=1.1.0` and
  `cura-formulae-engine/1.2.1`, which pulls in `zeus_expected` and `lexy`.
- Public GitHub tags for libArcus, pyArcus and pynest2d stop at 5.3.0. Their
  `main` branches declare exactly the Conan versions above, so the Dockerfile
  pins these commits: libArcus `339c85a1`, pyArcus `72d052a2`, pynest2d
  `73235af5`. See [`docs/upstream-versions.md`](docs/upstream-versions.md).
  Never silently fall back to the 5.3.0 tags.

Never commit floating `latest` source refs. Every downloaded component must be
pinned to an exact tag, commit SHA, or recorded version from `conandata.yml`.
The Dockerfile defaults are the last manually verified set; the release
workflow overrides them with `--build-arg` after resolving the current upstream
refs.

## Release workflow

- Triggers: daily cron (`17 4 * * *` UTC) and `workflow_dispatch`.
- Scheduled runs stop when the computed release tag already exists. Manual runs
  always build and replace an existing release with the same tag.
- Tag: `<cura-tag>-<deps-hash>-alpine-<alpine-version>-<apkindex-hash>`, for
  example `5.14.0-1a2b3c4-alpine-3.24.4-9f8e7d6`. Both hashes are the first
  seven hex characters of a SHA-256.
- Dependency refs come from the Cura/Uranium/CuraEngine `conandata.yml` files:
  use the exact tag when it exists, otherwise the head of `main`/`master`.
  `zeus_expected`, `lexy`, `geometry.hpp` and `wagyu` are resolved from their
  GitHub `releases/latest` tag, or the newest git tag when that is newer
  (`wagyu` 0.5.0 is a tag, while its latest release is 0.2.1). They are included
  in the dependency hash because they are built from source.
- The pipeline currently builds `linux/amd64` only. Future targets: `x86`,
  `armhf`, `armv7`, `aarch64`; each needs its own runner and artifact name.
- Python 3.14 and `/usr/lib/python3.14/site-packages` are hardcoded for now.
  Detecting the interpreter's site-packages path is planned for a future
  release.
- Deleting a release/tag happens only on manual runs and is intentional.
  Multiple release tags may point at the same commit; GitHub supports that and
  each release has its own assets.
- Use `gh` for GitHub API calls and releases. Do not add third-party release
  actions.
- The release tarball is allowlisted: only build outputs and license texts. Do
  not replace it with `docker export` of the runtime container.
- Details: [`docs/release-plan.md`](docs/release-plan.md).

## The blocker

Uranium imports `pyUvula` unconditionally in `UM/Mesh/MeshData.py`, and Cura's
Paint tool imports it too. Alpine has no `pyUvula` package, so the image must
build libUvula and its Python bindings and install them into the same Python
environment as Uranium and Cura.

libUvula has no git tags or GitHub releases. Its current `main` conandata
declares **1.1.0**, which matches Uranium 5.14.0. Pin a commit on the 1.1.0 line
and pass `-DUVULA_VERSION=1.1.0 -DPYUVULA_VERSION=1.1.0`; verify
`pyUvula.__version__ == "1.1.0"`.

Required Alpine adaptations are in `docs/libuvula.md`: remove
`standardprojectsettings` and its helper calls, use `FindClipper.cmake` with
`Clipper::Clipper`, and add install rules for the `pyUvula` extension.

## Build order

```text
zeus_expected -> lexy -> CuraFormulaeEngine
libArcus -> pyArcus
libnest2d -> pynest2d
CuraEngine (needs libArcus + CuraFormulaeEngine + bundled Scripta)
libUvula/pyUvula -> Uranium -> fdm-materials -> Cura
```

All components install under `/usr`. The builder may install directly into
`/usr` and the runtime stage should copy only the required paths, or the builder
may use a staging prefix. Apply the aports patches described in
`docs/reference-apkbuilds.md`; update them when upstream versions move.

## Documentation rules

- Keep `README.md`, `AGENTS.md` and `docs/*.md` consistent with each other.
- When a version, flag, patch, or install path changes, update every affected
  document in the same change.
- Prefer exact paths, package names, versions and commands over prose.
- Mark unresolved items explicitly as open questions; do not present guesses as
  facts.
- `docs/reference-apkbuilds.md` records the 5.13.0/5.3.0 aports baseline. Its
  versions are not the target; its patches and install layout are.

## Verification

Build-time checks:

```sh
python3 -c "import pyUvula; print(pyUvula.__version__)"
python3 -c "import UM, cura; print('ok')"
python3 -c "import cura.ApplicationMetadata as m; print(m.CuraVersion)"
CuraEngine help | grep -m1 'Cura_SteamEngine version'
```

Runtime smoke test:

```sh
QT_QPA_PLATFORM=offscreen timeout 30s cura
```

A timeout exit code of `124` means Cura stayed alive. Any Python traceback is a
failure. Cura may ignore `SIGTERM` and keep running; if the command does not
return, start it in the background, wait 30 seconds, and kill it explicitly. A
successful compile is not proof that the image runs.

## Licensing

The build files in this repository (`Dockerfile`, `patches/`, `docs/`, this
guide) are **MIT-licensed**; see [`LICENSE`](LICENSE). Add the MIT header only
where it does not conflict with an upstream file: files copied or derived from
aports or from UltiMaker upstream keep their original license and headers.

The software built by the image keeps its own licenses: Cura and Uranium are
LGPL-3.0-or-later; CuraEngine is AGPL-3.0-or-later; libUvula is LGPL-3.0 with
an MIT-licensed `xatlas` component. Preserve license files and comply with the
LGPL relinking requirements. `pyUvula` links `libUvula` statically; that is kept
because it is the only consumer, so a shared library would add a file and a
dynamic dependency without reducing the tarball or improving performance. The
exact libUvula source is published in the release `SOURCES` file so the library
can be relinked. The MIT license of this repository does not relicense those
components.

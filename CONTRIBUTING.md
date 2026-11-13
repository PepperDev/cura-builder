# Contributing

Thanks for helping improve this unofficial Cura-on-Alpine build. The project
compiles the latest upstream UltiMaker stack from source and publishes a
runtime tarball, so changes usually touch the `Dockerfile`, `patches/`,
`scripts/` and the documentation together.

By participating you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- Read [`AGENTS.md`](AGENTS.md) for the repository rules and the exact build
  order.
- Security issues go through [`SECURITY.md`](SECURITY.md), not a public issue.
- The Alpine [aports](https://gitlab.alpinelinux.org/alpine/aports) tree is a
  reference for patches and flags only. Do not add an `apk add cura uranium
  curaengine py3-arcus py3-pynest2d` dependency.

## Requirements

- Linux with Docker. Cross-architecture builds also need `docker buildx` and
  QEMU user emulation (see below).
- `bash`, `curl`, `git`, `sha256sum`, `tar`, and the GitHub CLI (`gh`) for the
  release scripts.
- About 8 GB of free disk space. A native build takes 20–40 minutes; an
  emulated cross-build is much slower.
- Network access to GitHub, `dl-cdn.alpinelinux.org` and the Alpine package
  mirrors.

## Build locally

The Dockerfile defaults are the last verified refs, so a plain build needs no
arguments:

```sh
git clone https://github.com/PepperDev/cura-builder.git
cd cura-builder
docker build -t cura-alpine .
```

To build the exact set the release workflow would publish:

```sh
gh auth login
./scripts/resolve-versions.sh       # writes versions.env
./scripts/build-release.sh          # builds and writes dist/
```

`resolve-versions.sh` reads Cura's `conandata.yml`, resolves the dependency
refs and writes `versions.env`; `build-release.sh` consumes that file. Do not
commit `versions.env` or `dist/`.

`build-release.sh` defaults to `PLATFORM=linux/amd64` and `ARCH=x86_64`. Build
another matrix entry by setting both:

```sh
PLATFORM=linux/arm64 ARCH=aarch64 ./scripts/build-release.sh
```

Cross-architecture builds require a Buildx builder and QEMU user emulation:

```sh
docker run --privileged --rm tonistiigi/binfmt:latest --install all
docker buildx create --name cura-builder --driver docker-container --use
docker buildx inspect --bootstrap
```

Registering `binfmt_misc` changes the host kernel, even from Docker-in-Docker.
Run this only on a disposable VM or CI runner, not on a workstation you care
about. Native `x86_64` builds do not need QEMU or Buildx. `x86` needs Buildx
but not QEMU; `armv7` and `aarch64` need both.

`release-metadata.sh` is only needed when assembling all architectures:

```sh
ARCHS="x86_64 x86 armv7 aarch64" ./scripts/release-metadata.sh
```

## Smoke test

A successful compile is not proof that the image runs. Check the imports and
start Cura offscreen:

```sh
docker run --rm --entrypoint /bin/sh cura-alpine -c '
  python3 -c "import pyUvula, UM, cura, pyArcus, pynest2d; print(pyUvula.__version__)"
  QT_QPA_PLATFORM=offscreen timeout 30s cura
'
```

`timeout` returning `124` (GNU) or `143` (BusyBox after `SIGTERM`) with no
Python traceback means Cura stayed alive until the timeout. Any traceback is a
failure.

The release workflow uses a stronger check: it starts each architecture's
container, waits 45 seconds, verifies it is still running, and fails on any
`Traceback` in the logs. The image tag there is
`cura-alpine:<tag>-<arch>`.

## Changing the build

- Keep every downloaded component pinned to an exact tag or commit. The
  workflow resolves refs; the Dockerfile defaults must stay buildable.
- Keep the build order:
  libArcus → pyArcus → CuraEngine → pynest2d → libUvula/pyUvula → Uranium →
  fdm-materials → Cura.
- Put Alpine adaptations in `patches/<component>/` and apply them in the same
  order as the `Dockerfile`. Prefer a minimal patch over editing the installed
  result.
- Python packages are staged in `/staging/python`; the site-packages path is
  detected with `sysconfig.get_path("platlib")`. Do not hardcode
  `/usr/lib/python3.X`.
- The runtime image must stay free of compilers, headers and source archives.
- New runtime files must be added to the export allowlist in
  `scripts/build-release.sh`, otherwise they will not appear in the release.

## Changing the release pipeline

- The tag is
  `<cura-tag>-<deps-hash>-alpine-<alpine-version>-<apkindex-hash>`.
- Everything that is built from source but is not Cura belongs in the
  dependency hash, including `zeus_expected`, `lexy`, `geometry.hpp` and
  `wagyu`. Alpine packages are covered by the APKINDEX hash.
- Scheduled runs must never delete a release. Only manual runs replace one.
- Use `gh` for GitHub API and release operations. Do not add third-party
  release actions.
- Run the shell syntax check before pushing:
  ```sh
  bash -n scripts/resolve-versions.sh
  bash -n scripts/build-release.sh
  ```

## Documentation

- Update `README.md`, `AGENTS.md` and the affected `docs/*.md` in the same
  change as the code.
- Prefer exact paths, package names, versions and commands over prose.
- Mark unresolved items as open questions. Do not present guesses as facts.
- The release document is [`docs/release-pipeline.md`](docs/release-pipeline.md);
  the build design/flags live in
  [`docs/dockerfile-design.md`](docs/dockerfile-design.md).

## Pull requests

Please include:

- what changed and why;
- the upstream versions affected, if any;
- the build and smoke-test commands you ran, with the result;
- doc updates for every changed version, flag, path or behavior.

Keep commits focused and use a short imperative subject, for example
`build: detect Python site-packages` or `docs: record release asset names`.

## License

The build files (`Dockerfile`, `patches/`, `docs/`, scripts and workflows) are
MIT-licensed; see [`LICENSE`](LICENSE). By contributing you agree that your
changes are provided under that license. Upstream components keep their own
licenses; do not relicense them.

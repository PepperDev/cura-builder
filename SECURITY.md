# Security Policy

## Supported versions

Only the **latest GitHub release** of this project is supported. Releases are
built from the latest upstream Cura stack and the current Alpine repositories,
and the daily workflow replaces the tag when a new fingerprint appears. Older
`cura-*` releases are kept for reproducibility but do not receive fixes.

| Version | Supported |
| --- | --- |
| Latest release on the [releases page](https://github.com/PepperDev/cura-builder/releases) | Yes |
| Any older release | No |

## Reporting a vulnerability

Do **not** open a public issue for an undisclosed vulnerability.

Report it privately through GitHub:

<https://github.com/PepperDev/cura-builder/security/advisories/new>

If private reporting is unavailable, contact the repository owner
[`@PepperDev`](https://github.com/PepperDev) through GitHub and ask for a
private channel. Do not include exploit details in a public issue.

Please include:

- the affected release tag and artifact name;
- the affected file, script, workflow or bundled component;
- steps to reproduce, or a minimal proof of concept;
- the impact you believe the issue has;
- any suggested fix or mitigation.

## Scope

In scope:

- the `Dockerfile`, `patches/`, `.github/workflows/` and `scripts/`;
- the published release tarball and its `SOURCES-<tag>.txt` / checksum files;
- build or packaging behavior that makes a release weaker than its upstream
  components, for example a missing security flag or an unexpectedly old
  dependency.

Out of scope for this repository:

- vulnerabilities in Cura, Uranium, CuraEngine, libArcus, pyArcus, pynest2d,
  libUvula, Qt, Python or Alpine packages. Report those to the upstream
  project. If this build pins a vulnerable version, a report here is still
  useful so the pin can be updated, but the fix belongs upstream.
- issues that require a modified local build, a compromised Docker daemon, or
  running the image as root.
- the documented licensing and trademark status of the unofficial build.

## Response

Maintainers review reports on a best-effort basis and aim to acknowledge a
complete report within seven days. There is no bug-bounty program and no
guaranteed response time. Valid reports are fixed in the build files, published
in a new release, and credited unless you ask to remain anonymous.

## Release integrity

Each release publishes one tarball and checksum per architecture:

- `cura-<tag>-linux-<arch>.tar.gz`
- `cura-<tag>-linux-<arch>.tar.gz.sha256`
- `SOURCES-<tag>.txt`

`<arch>` is `x86_64`, `x86`, `armv7` or `aarch64`; `armhf` is not published.
Verify the download before extracting it:

```sh
sha256sum -c cura-<tag>-linux-<arch>.tar.gz.sha256
```

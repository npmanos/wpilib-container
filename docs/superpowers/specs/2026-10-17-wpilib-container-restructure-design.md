# WPILib container restructure: design

Date: 2026-10-17
Status: draft, awaiting review

## Goal

Make the repo easier to maintain. Today it scrapes another repo's Groovy build
script with regexes, constructs download URLs and filenames by hand, spreads one
version key across four files, and has no tests. After this change it has one
pin (the WPILib version), one Dockerfile that extracts what it needs from
WPILib's own installer bundle, and CI that verifies the image before
publishing.

## Scope

- Build only the current WPILib release. Already-published images (for example
  the 2026 tags on ghcr) are untouched. Pre-2027 build logic is removed because
  it is never built again.
- The installer bundle layout used here (an `*-artifacts.tar.gz` inside the
  installer tarball) is the 2027 layout. This design depends on it.

Non-goals: checksum verification of downloads, supporting multiple seasons in
one Dockerfile, running the installer CLI, any change to the image name.

## Design

### Data flow

```
wpilib.version   (one line, e.g. 2027.0.0-alpha-7)
      |  Renovate (hosted app) opens a bump PR
      v
Dockerfile (single stage): one streaming RUN downloads the installer bundle,
      pulls the artifacts tarball out of it, and extracts only the keep list
      into ~/.local/share/wpilib/<WpilibYear>
      v
CI: build per arch, smoke test, multi-arch manifest
```

### `wpilib.version`

A single line holding the WPILib version, matching the installer repo tag
without the leading `v`. It is the only version input to the build.

### Dockerfile

Base image stays `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`, with the
existing apt packages. Build args are `WPILIB_VERSION` and `TARGETARCH`
(`amd64` or `arm64`). The Dockerfile sets `SHELL ["/bin/bash", "-o", "pipefail",
"-c"]` so a failed download inside a pipe fails the build.

The installer CLI is not run. The artifacts tarball inside the installer bundle
already contains every directory the image keeps (verified by listing the
alpha-7 amd64 tarball: paths are relative to the install root, with no year
prefix).

One `RUN`, as `vscode`, does the following in a single pass:

1. Stream
   `https://packages.wpilib.workers.dev/installer/v${WPILIB_VERSION}/WPILib_Linux-${ARCH}-${WPILIB_VERSION}.tar.gz`
   (`ARCH` is `x64` for amd64 and `Arm64` for arm64) through `tar`, extracting
   only the `*-artifacts.tar.gz` member to stdout.
2. Pipe that into a second `tar` that extracts only the keep list into a
   staging directory, `~/.local/share/wpilib/.staging`.
3. Read `WpilibYear` from `.staging/installUtils/upgradeConfig.json` and move
   the staging directory to `~/.local/share/wpilib/<WpilibYear>`. The year
   directory name is not derivable from the version string: alpha-2 and alpha-6
   use `2027_alpha1` and `2027_alpha5`.
4. Create `~/.local/share/wpilib/.current` as a symlink to the year directory.

Because the bundle is streamed, no large file is written to an image layer.

**Keep list** (everything else is never extracted): `jdk`, `systemcore`,
`vsCodeExtensions`, `wpilibcode`, `vendordeps`, `documentation`,
`tools/tools.json`, `installUtils`. Not extracted: `maven`, `advantagescope`,
`elastic`, `icons`, and the rest of `tools`. Estimated image contribution is
about 2.2 GB for amd64, from sizes measured on a local install.

Environment:

```
ENV JAVA_HOME=/home/vscode/.local/share/wpilib/.current/jdk
ENV PATH=${JAVA_HOME}/bin:$PATH:/home/vscode/.local/share/wpilib/.current/systemcore/bin
```

`.current` exists because `ENV` needs a literal path and the year directory name
is only known after extraction.

The OCI labels stay (`source`, `base.name`, `version`).

### Version tracking

Renovate (hosted GitHub app, no self-hosting, no `postUpgradeTasks`) with a
custom regex manager on `wpilib.version` and the `github-tags` datasource on
`wpilibsuite/WPILibInstaller-Avalonia`. That repo's tag push is what triggers
the bundle upload, so tracking its tags is more precise than tracking
`allwpilib` releases. Renovate opens a PR; required checks must pass; it
automerges to `develop`. Renovate also keeps GitHub Actions SHA pins current.

No scheduled workflow remains in this repo, so GitHub's 60-day disabling of
scheduled workflows does not apply.

### Workflows

`docker-publish.yml` (push to `develop` touching `Dockerfile`,
`wpilib.version`, or the workflow; plus `workflow_dispatch`):

- Check out the triggering commit (replaces the `git clone` in `merge`).
- Build per arch (amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm`) with
  `docker/build-push-action`, passing `WPILIB_VERSION` and `TARGETARCH`; push by
  digest as now.
- Run the smoke test against each arch image before the manifest is created.
- `merge` creates the manifest. Tags come from `docker/metadata-action` on
  `wpilib.version`: the full version always; the major version (`2027`) and
  `latest` only for stable versions (no `alpha`/`beta` in the version).
- Actions are pinned by commit SHA.

`pr.yml` (pull requests): build amd64 without pushing, then run the smoke test.
No Docker builds are done on developer machines; CI is the test loop.

`check-versions.yml`, `scripts/update_versions.py`, and `.versions` are deleted.

### Smoke test

A script in `scripts/` run inside each built image:

- `java -version` succeeds and `JAVA_HOME` resolves through `.current`.
- The cross-compiler under `.current/systemcore/bin` runs with `--version`.
- A `vscode-wpilib-*.vsix` exists under `.current/vsCodeExtensions`.
- `.current/tools/tools.json` exists and `.current/maven` does not.

### Docs

`README.md`, `sample-devcontainer.json`, and `CLAUDE.md` are rewritten for the
new layout: install root `/home/vscode/.local/share/wpilib`, the `.current`
symlink, the new tags, and the `postCreateCommand` path to the `.vsix`.

## Risks and unverified assumptions

All of these can only be confirmed in CI; the PR workflow is where they surface.

- The arm64 bundle's artifacts tarball is assumed to have the same layout as
  amd64 (verified for amd64 only), with an arm64 JDK and toolchain.
- The extraction path list for the second `tar` must match the tarball's member
  names exactly; a typo silently drops a directory, which the smoke test is
  there to catch.
- Renovate's ordering of prerelease versions: plain semver compares
  `alpha-10` before `alpha-7`. Check with Renovate's config validator before
  relying on automerge.
- The tag scheme changes: alphas were previously tagged `2027_alpha7` and are
  now tagged by full version only. This was proposed during review and not
  explicitly confirmed.
- Whether a merge made by the Renovate app triggers `docker-publish` as
  expected; the first real bump confirms it.
- The bundle host is a single site and each build downloads about 2.8 GB per
  arch. Docker layer caching covers repeat builds of the same version.
- The 2027 bundle URL layout (`installer/v<ver>/WPILib_Linux-{x64|Arm64}-<ver>.tar.gz`)
  is confirmed for alpha-7 only.

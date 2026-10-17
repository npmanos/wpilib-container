# WPILib container restructure: design

Date: 2026-10-17
Status: draft, awaiting review

## Goal

Make the repo easier to maintain. Today it scrapes another repo's Groovy build
script with regexes, constructs download URLs and filenames by hand, spreads one
version key across four files, and has no tests. After this change it has one
pin (the WPILib version), one Dockerfile that installs from WPILib's own
installer bundle, and CI that verifies the image before publishing.

## Scope

- Build only the current WPILib release. Already-published images (for example
  the 2026 tags on ghcr) are untouched. Pre-2027 build logic is removed because
  it is never built again.
- The installer CLI (`WPILibInstaller-CLI`) exists from 2027 onward. This design
  depends on it.

Non-goals: checksum verification of downloads, supporting multiple seasons in
one Dockerfile, any change to the image name.

## Design

### Data flow

```
wpilib.version   (one line, e.g. 2027.0.0-alpha-7)
      |  Renovate (hosted app) opens a bump PR
      v
Dockerfile
  stage "base":  download bundle, run installer CLI in tools mode,
                 extract the artifacts tarball over the install, prune
  stage "final": devcontainers base + apt deps + COPY --from=base
      v
CI: build per arch, smoke test, multi-arch manifest
```

### `wpilib.version`

A single line holding the WPILib version, matching the installer repo tag
without the leading `v`. It is the only version input to the build.

### Dockerfile

Base image stays `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`. Build args
are `WPILIB_VERSION` and `TARGETARCH` (`amd64` or `arm64`).

**Stage `base`** (runs as `vscode`):

1. Download
   `https://packages.wpilib.workers.dev/installer/v${WPILIB_VERSION}/WPILib_Linux-${ARCH}-${WPILIB_VERSION}.tar.gz`,
   where `ARCH` is `x64` for amd64 and `Arm64` for arm64, and extract it.
2. Run `WPILibInstaller-CLI --install-mode tools --force`. The CLI installs to
   `~/.local/share/wpilib/<WpilibYear>` (its default on Linux when
   `XDG_DATA_HOME` is unset); the Dockerfile does not override this.
3. Extract `WPILib_Linux-*-artifacts.tar.gz` over that directory. This is the
   same procedure that was done by hand for the local alpha-7 install.
4. Prune everything not on the keep list.
5. Create `~/.local/share/wpilib/.current` as a symlink to the year directory.
   The year directory name is the installer's `WpilibYear`
   (`installUtils/upgradeConfig.json`). It is not derivable from the version
   string: alpha-2 and alpha-6 use `2027_alpha1` and `2027_alpha5`.

**Keep list** (everything else is deleted): `jdk`, `systemcore`,
`vsCodeExtensions`, `wpilibcode`, `vendordeps`, `documentation`,
`tools/tools.json`, `installUtils`. Dropped: `maven`, `advantagescope`,
`elastic`, `icons`, and the rest of `tools`. Estimated image contribution is
about 2.2 GB for amd64, from sizes measured on a local install.

**Stage `final`:** the existing base image and apt packages, then
`COPY --from=base --chown=vscode:vscode` of `~/.local/share/wpilib`, then:

```
ENV JAVA_HOME=/home/vscode/.local/share/wpilib/.current/jdk
ENV PATH=${JAVA_HOME}/bin:$PATH:/home/vscode/.local/share/wpilib/.current/systemcore/bin
```

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
- `.current/maven` does not exist.

### Docs

`README.md`, `sample-devcontainer.json`, and `CLAUDE.md` are rewritten for the
new layout: install root `/home/vscode/.local/share/wpilib`, the `.current`
symlink, the new tags, and the `postCreateCommand` path to the `.vsix`.

## Risks and unverified assumptions

All of these can only be confirmed in CI; the PR workflow is where they surface.

- The CLI may need runtime libraries (for example ICU or OpenSSL) that the
  devcontainers base image lacks.
- Whether `tools/tools.json` is produced by the CLI's tool setup or comes from
  the tarball. If it comes from the CLI, that is why the CLI is run at all
  rather than only extracting the tarball.
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

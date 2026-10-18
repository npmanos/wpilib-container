# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker image (published to `ghcr.io/npmanos/devcontainer_wpilib`) used as a VS Code Dev Container / Codespaces base for FRC robot code. It contains a subset of WPILib's official install (JDK, systemcore toolchain, the WPILib VS Code `.vsix`, and a few support directories), extracted from the installer bundle. Only the current WPILib release is built; already-published images are not touched.

## Commands

```sh
bash tests/run-all.sh   # local tests for the three scripts; no Docker needed
```

Docker builds are not run locally. CI is the test loop: `pr.yml` builds the amd64 image and runs `scripts/smoke-test.sh` inside it.

Maintainers push to `develop` directly; `check` (from `pr.yml`) is the required status for PRs. `gh workflow run docker-publish.yml --ref <branch>` builds and publishes from a branch, and re-tags that version in ghcr, so only do it deliberately (it is the only way to test the publish path before merging).

## Architecture

1. `wpilib.version` holds one line, the WPILib version (the `WPILibInstaller-Avalonia` tag without the leading `v`). It is the only version input.
2. Renovate (hosted GitHub app, config in `renovate.json`) opens PRs bumping `wpilib.version` and automerges them when checks pass. GitHub Actions pin bumps are not automerged; merge them by hand. `renovate.json` sets `versioningTemplate` to a regex because the default versioning ignores `-alpha-N`/`-beta-N`/`-rc-N` suffixes. No scheduled workflow exists.
3. The `Dockerfile` takes `WPILIB_VERSION` and `TARGETARCH` build args. One `RUN` streams `https://packages.wpilib.workers.dev/installer/v<ver>/WPILib_Linux-{x64|Arm64}-<ver>.tar.gz`, pulls out the `*-artifacts.tar.gz` member, and pipes it to `scripts/extract-artifacts.sh`.
4. `scripts/extract-artifacts.sh INSTALL_ROOT` extracts only the keep list (`jdk`, `systemcore`, `vsCodeExtensions`, `wpilibcode`, `vendordeps`, `documentation`, `tools/tools.json`, `installUtils`), reads `WpilibYear` from `installUtils/upgradeConfig.json`, moves the result to `INSTALL_ROOT/<WpilibYear>`, and links `INSTALL_ROOT/.current` to it. The year directory name cannot be derived from the version (alpha-5 and alpha-6 use `2027_alpha5`).
5. `docker-publish.yml` (push to `develop`) builds amd64 (`ubuntu-latest`) and arm64 (`ubuntu-24.04-arm`) natively, pushes by digest, smoke-tests each pushed digest, then `merge` creates the manifest. `scripts/version-info.sh` decides stability: the full version is always a tag; the major version and `latest` only for versions with no `-suffix`.

To change the keep list, edit `KEEP` in `scripts/extract-artifacts.sh` and the fixture in `tests/test_extract_artifacts.sh`.

`scripts/*.sh` must be committed executable (mode 100755): the workflows run them directly, and `tests/test_scripts_executable.sh` enforces it.

## Install layout in the image

`/home/vscode/.local/share/wpilib/<WpilibYear>/` with `.current` as a symlink to it. `JAVA_HOME=.../.current/jdk`; `PATH` gets `.../.current/systemcore/bin`. The `.vsix` is at `.current/vsCodeExtensions/vscode-wpilib-*.vsix`; consumers install it via `postCreateCommand` (see `sample-devcontainer.json`). `maven` is deliberately absent.

## Unverified

Whether a merge made by Renovate triggers `docker-publish`; the first `wpilib.version` bump will show it.

## TODO (deferred review findings)

- `tests/test_extract_artifacts.sh`, in `make_artifacts`: the first `tar -czf "$out" -C "$dir" .` is dead code. The second `tar` overwrites its output.
- `docker-publish.yml`: the `build` job's `digest` output is unused. With a matrix, the last job to finish overwrites it.
- `docker-publish.yml` has no `concurrency` group, and a manual dispatch from an older ref could move `latest` or the major tag backwards.
- Decide whether Actions pin bumps should automerge. The Renovate rule only matches the `wpilib.version` manager.

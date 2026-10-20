# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker image (published to `ghcr.io/npmanos/devcontainer_wpilib`) used as a VS Code Dev Container / Codespaces base for FRC robot code. It contains a subset of WPILib's official install (JDK, systemcore toolchain, the WPILib VS Code `.vsix`, and a few support directories), extracted from the installer bundle. Only the current WPILib release is built; already-published images are not touched.

## Commands

```sh
bash tests/run-all.sh   # local tests for the scripts; no Docker needed
```

Docker builds are not run locally. CI is the test loop: `pr.yml` builds both variants for arm64 (`ubuntu-24.04-arm`) and runs `scripts/smoke-test.sh java|full` inside each.

Maintainers push to `develop` directly; `check` (from `pr.yml`) is the required status for PRs. `gh workflow run docker-publish.yml --ref <branch>` builds and publishes from a branch, and re-tags that version in ghcr, so only do it deliberately (it is the only way to test the publish path before merging).

## Architecture

1. `wpilib.version` holds one line, the WPILib version (the `WPILibInstaller-Avalonia` tag without the leading `v`). It is the only version input.
2. Renovate (hosted GitHub app, config in `renovate.json`) opens PRs bumping `wpilib.version` and automerges them when checks pass. GitHub Actions pin bumps are not automerged; merge them by hand. `renovate.json` sets `versioningTemplate` to a regex because the default versioning ignores `-alpha-N`/`-beta-N`/`-rc-N` suffixes. No scheduled workflow exists.
3. The `Dockerfile` takes `WPILIB_VERSION` and `TARGETARCH` build args and has four stages: `base` (Microsoft base image plus apt packages), `fetch` (throwaway: one `RUN` streams `https://packages.wpilib.workers.dev/installer/v<ver>/WPILib_Linux-{x64|Arm64}-<ver>.tar.gz`, pulls out the `*-artifacts.tar.gz` member, pipes it to `scripts/extract-artifacts.sh`, then runs `install-gradle.sh` and `split-cpp.sh`), `java` (copies the install and `~/.gradle` from `fetch`, no C++ parts) and `full` (last stage, so the default target: `java` plus `build-essential cmake gdb`, `systemcore` and the C++ `.vsix`).
4. `scripts/extract-artifacts.sh INSTALL_ROOT` extracts only the keep list (`jdk`, `systemcore`, `vsCodeExtensions`, `vendordeps`, `tools/tools.json`, `installUtils`), reads `WpilibYear` from `installUtils/upgradeConfig.json`, moves the result to `INSTALL_ROOT/<WpilibYear>`, and links `INSTALL_ROOT/.current` to it. The year directory name cannot be derived from the version (alpha-5 and alpha-6 use `2027_alpha5`).
5. `scripts/install-gradle.sh INSTALL_ROOT GRADLE_USER_HOME` unpacks the Gradle zip named in `installUtils/fullConfig.json` to `GRADLE_USER_HOME/permwrapper/dists/<name>/<Hash>/`, writes the `.ok` marker, and deletes the zip. `scripts/split-cpp.sh INSTALL_ROOT OUT_ROOT` moves `<year>/systemcore` and the `ms-vscode.cpptools` `.vsix` (name read from `installUtils/vscodeConfig.json`; it differs per architecture) to `OUT_ROOT/<year>/`, leaving `INSTALL_ROOT` untouched on failure.
6. `docker-publish.yml` (push to `develop`) builds amd64 (`ubuntu-latest`) and arm64 (`ubuntu-24.04-arm`) natively, building `java` then `full` per architecture, pushes by digest, smoke-tests each pushed digest, then a `merge` matrix creates one manifest per variant. Tags are `<version>`, `<major>`, `latest` for `full` and the same with a `-java` suffix for `java`. `scripts/version-info.sh` decides stability: the full version is always a tag; the major version and `latest` only for versions with no `-suffix`, and only on runs from `develop` (a dispatch from another branch cannot move them). A `concurrency` group (`docker-publish`, no cancel) serialises runs.

To change the keep list, edit `KEEP` in `scripts/extract-artifacts.sh` and the fixture in `tests/test_extract_artifacts.sh`.

`scripts/*.sh` must be committed executable (mode 100755): the workflows run them directly, and `tests/test_scripts_executable.sh` enforces it.

## Install layout in the image

`/home/vscode/.local/share/wpilib/<WpilibYear>/` with `.current` as a symlink to it. `JAVA_HOME=.../.current/jdk`; `PATH` gets `.../.current/systemcore/bin` in `full` only. The Gradle distribution is at `~/.gradle/permwrapper/dists/<name>/<Hash>/`. The `.vsix` is at `.current/vsCodeExtensions/vscode-wpilib-*.vsix`; consumers install it via `postCreateCommand` (see `sample-devcontainer.json`). `maven`, `documentation` and `wpilibcode` are deliberately absent.

## Unverified

Whether a merge made by Renovate triggers `docker-publish`; the first `wpilib.version` bump will show it.

## TODO (deferred review findings)

- Decide whether Actions pin bumps should automerge. The Renovate rule only matches the `wpilib.version` manager.

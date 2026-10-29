# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker image (published to `ghcr.io/npmanos/devcontainer-wpilib`, and also to the old name `ghcr.io/npmanos/devcontainer_wpilib` for backwards compatibility) used as a VS Code Dev Container / Codespaces base for FRC robot code. It contains a subset of WPILib's official install (JDK, cross-compiler toolchain, the WPILib VS Code `.vsix`, and a few support directories), extracted from the installer bundle. `wpilib.version` (the current release) is what gets built on every push; seasons 2024 to 2026 can also be built by dispatching with `wpilib_version`. Already-published images are not touched.

## Commands

```sh
bash tests/run-all.sh   # local tests for the scripts; no Docker needed
```

Docker builds are not run locally. CI is the test loop: `pr.yml` builds both variants for arm64 (`ubuntu-24.04-arm`) and runs `scripts/smoke-test.sh java|full` inside each.

Maintainers push to `develop` directly; `check` (from `pr.yml`) is the required status for PRs. `gh workflow run docker-publish.yml --ref <branch>` builds and publishes from a branch, and re-tags that version in ghcr, so only do it deliberately (it is the only way to test the publish path before merging).

## Architecture

1. `wpilib.version` holds one line, the WPILib version (the `WPILibInstaller-Avalonia` tag without the leading `v`). It is the only version input.
2. Renovate (hosted GitHub app, config in `renovate.json`) opens PRs bumping `wpilib.version` and automerges them when checks pass. GitHub Actions pin bumps are not automerged; merge them by hand. `renovate.json` sets `versioningTemplate` to a regex because the default versioning ignores `-alpha-N`/`-beta-N`/`-rc-N` suffixes. No scheduled workflow exists.
3. The `Dockerfile` takes `WPILIB_VERSION` and `TARGETARCH` build args and has four stages: `base` (Microsoft base image plus apt packages), `fetch` (throwaway: one `RUN` asks `scripts/installer-info.sh` for the bundle URL and cross-compiler directory, streams the bundle, pulls out the `*-artifacts.tar.gz` member, pipes it to `scripts/extract-artifacts.sh`, then runs `install-gradle.sh` and `split-cpp.sh`), `java` (copies the install and `~/.gradle` from `fetch`, no C++ parts) and `full` (last stage, so the default target: `java` plus `build-essential cmake gdb`, the cross-compiler and the C++ `.vsix`).

   `scripts/installer-info.sh VERSION TARGETARCH` prints `url=` and `toolchain=` for the season. 2027 and later: `packages.wpilib.workers.dev/installer/v<ver>/WPILib_Linux-{x64|Arm64}-<ver>.tar.gz`, toolchain `systemcore`. 2024 to 2026: `.../v<ver>/{Linux|LinuxArm64}/WPILib_{Linux|LinuxArm64}-<ver>.tar.gz` (a per-platform directory, no arch suffix), toolchain `roborio`. 2023 and earlier are rejected: they were GitHub release assets (arm64 Linux starts in 2024). The 2024 to 2026 layout was read from the arm64 bundles of 2024.3.2, 2025.3.2 and 2026.2.1; 2026.1.1 (both architectures) has built and passed the smoke test, the x64 bundles of 2024 and 2025 are assumed to match.
4. `scripts/extract-artifacts.sh INSTALL_ROOT [TOOLCHAIN]` extracts only the keep list (`jdk`, the toolchain directory, `vsCodeExtensions`, `vendordeps`, `tools/tools.json`, `installUtils`), reads `WpilibYear` (2027+) or `FrcYear` (2024 to 2026) from `installUtils/upgradeConfig.json`, moves the result to `INSTALL_ROOT/<year>`, and links `INSTALL_ROOT/.current` to it. `TOOLCHAIN` defaults to `systemcore`; it is an argument because GNU tar fails on a member that is not in the archive and the stream cannot be read twice. The year directory name cannot be derived from the version (alpha-5 and alpha-6 use `2027_alpha5`).
5. `scripts/install-gradle.sh INSTALL_ROOT GRADLE_USER_HOME` unpacks the Gradle zip named in `installUtils/fullConfig.json` to `GRADLE_USER_HOME/permwrapper/dists/<name>/<Hash>/`, writes the `.ok` marker, and deletes the zip. `scripts/split-cpp.sh INSTALL_ROOT OUT_ROOT` moves the toolchain directory (`CppToolchain.Directory` in `installUtils/fullConfig.json`, `systemcore` if absent) and the `ms-vscode.cpptools` `.vsix` (name read from `installUtils/vscodeConfig.json`; it differs per architecture and season, and 2024/2025 names contain `@`) to `OUT_ROOT/<year>/`, leaving `INSTALL_ROOT` untouched on failure.
6. `docker-publish.yml` (push to `develop`, or `workflow_dispatch`) builds amd64 (`ubuntu-latest`) and arm64 (`ubuntu-24.04-arm`) natively, building `java` then `full` per architecture, pushes by digest, smoke-tests each pushed digest, then a `merge` matrix creates one manifest per variant. Tags are `<version>`, `<major>`, `latest` for `full` and the same with a `-java` suffix for `java`. `scripts/version-info.sh` decides stability: the full version is always a tag; the major version and `latest` only for versions with no `-suffix`, and only on runs from `develop` (a dispatch from another branch cannot move them). A dispatch takes two optional inputs: `wpilib_version` (default: `wpilib.version`) and `moving_tags` (`none` by default, `major`, or `major-and-latest`), which decides which moving tags a dispatch updates; pushes always update both. A `concurrency` group (`docker-publish`, no cancel) serialises runs.

To change the keep list, edit `KEEP` in `scripts/extract-artifacts.sh` and the fixture in `tests/test_extract_artifacts.sh`.

`scripts/*.sh` must be committed executable (mode 100755): the workflows run them directly, and `tests/test_scripts_executable.sh` enforces it.

## Install layout in the image

`/home/vscode/.local/share/wpilib/<year>/` (`WpilibYear`, or `FrcYear` for 2024 to 2026) with `.current` as a symlink to it. `JAVA_HOME=.../.current/jdk`; `PATH` gets `.../.current/systemcore/bin` and `.../.current/roborio/bin` in `full` only (only the directory for that season exists). The Gradle distribution is at `~/.gradle/permwrapper/dists/<name>/<Hash>/`. The `.vsix` is at `.current/vsCodeExtensions/vscode-wpilib-*.vsix`; consumers install it via `postCreateCommand` (see `sample-devcontainer.json`). `maven`, `documentation` and `wpilibcode` are deliberately absent.

## Unverified

- Only 2026.1.1 has been built for 2024 to 2026 (dispatch run #26, all jobs green). 2024 and 2025 have not: the layout for them comes from the arm64 bundle listings of 2024.3.2 and 2025.3.2, and the Gradle wrapper path inside their `vscode-wpilib` `.vsix` (checked by `smoke-test.sh`) is unchecked. The first dispatch for each will show it (use `moving_tags: none`).
- Whether 2027's `fullConfig.json` carries `CppToolchain.Directory` (`split-cpp.sh` and `smoke-test.sh` fall back to `systemcore`).

## TODO (deferred review findings)

- `docker-publish.yml`: the `merge` matrix jobs are independent, so one variant can be published while the other's merge fails; re-run the failed job.
- `docker-publish.yml`: a `workflow_dispatch` from another branch can cancel a queued `develop` run (a concurrency group keeps one pending run). Consider `github.ref` in the group name.
- `Dockerfile`: `ARG WPILIB_VERSION` sits above the apt `RUN` in `base`, so that layer may rebuild on every version bump. Move the `ARG` and `LABEL` below the `RUN`.
- Decide whether Actions pin bumps should automerge. The Renovate rule only matches the `wpilib.version` manager.

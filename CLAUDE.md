# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker image (published to `ghcr.io/npmanos/devcontainer_wpilib`) used as a VS Code Dev Container / Codespaces base for FRC robot code. It bundles the WPILib JDK, the cross-compiler toolchain, and the WPILib VS Code `.vsix`. There is no application code and no test suite; the repo is the Dockerfile, a version-scraping script, and two GitHub workflows.

## Commands

Build locally (build args normally come from `.versions`; `TARGETARCH` is `amd64` or `arm64` and must be passed explicitly, since the Dockerfile does not rely on BuildKit's automatic value in CI):

```sh
set -a; . ./.versions; set +a
docker build \
  --build-arg TARGETARCH=amd64 \
  --build-arg WPILIB_YEAR --build-arg GCC_VERSION --build-arg TOOLCHAIN_VERSION \
  --build-arg VSCODE_WPILIB_VERSION --build-arg JDK_TAG --build-arg JDK_TAG_CLEAN \
  -t wpilib-test .
```

Refresh `.versions` from upstream (needs network; overwrites the file):

```sh
python3 scripts/update_versions.py
```

## Architecture: how versions flow

1. `scripts/update_versions.py` fetches `gradle.properties` from `wpilibsuite/WPILibInstaller-Avalonia` (`main`) for `gradleRioVersion`, then fetches `scripts/versions.gradle` at the matching `v<version>` tag and regex-extracts GCC, toolchain tag, JDK, year, and tool versions. It writes everything to `.versions` (a flat `KEY=VALUE` file).
2. `.github/workflows/check-versions.yml` runs that script daily (and on dispatch). If `.versions` changed, it commits `chore: bump WPILib version to <ver>` and pushes.
3. `.github/workflows/docker-publish.yml` triggers on pushes to `develop` touching `Dockerfile`, `.versions`, or the workflow itself. It does `cat .versions >> $GITHUB_ENV`, then builds amd64 (`ubuntu-latest`) and arm64 (`ubuntu-24.04-arm`) natively in parallel, pushes each by digest, and a `merge` job creates a multi-arch manifest tagged `latest`, `$WPILIB_YEAR`, and `$VSCODE_WPILIB_VERSION`.

Things that must stay in sync when adding or renaming a version key:
- The key in `update_versions.py`'s `output_lines`.
- The `build-args` block in `docker-publish.yml` (only a subset of `.versions` keys is passed: `WPILIB_YEAR`, `GCC_VERSION`, `TOOLCHAIN_VERSION`, `VSCODE_WPILIB_VERSION`, `JDK_TAG`, `JDK_TAG_CLEAN`).
- The matching `ARG` in the `Dockerfile`.

`WPILIB_YEAR` determines the install path (`/home/vscode/wpilib/<year>/`) and the image tag. For pre-releases the value is not just a year (e.g. `2027_alpha7`), so the path and tag follow it.

## Dockerfile specifics

- Base is `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`; everything is installed as the `vscode` user under `/home/vscode/wpilib/<year>/{jdk,tools,maven,systemcore|roborio}`.
- The toolchain branch is chosen from the year parsed out of `TOOLCHAIN_VERSION`: 2027 or later uses the `arm64-systemcore` target (arm64 host triple `aarch64-trixie-linux-gnu`); earlier years use `cortexa9_vfpv3-roborio-academic` (`aarch64-bullseye-linux-gnu`). The `roborio` and `systemcore` directories are symlinked to each other so tooling paths work for either.
- The JDK is a Temurin tarball whose major version and filename are derived from `JDK_TAG_CLEAN`; `JDK_TAG` is the URL-encoded form (`+` as `%2B`) and `JDK_TAG_CLEAN` uses `_` in place of `+`.
- The `.vsix` is only downloaded to `/home/vscode/wpilib/vscode-wpilib.vsix`; consumers install it via `postCreateCommand` (see `sample-devcontainer.json`).

## Known doc drift

`README.md` and `sample-devcontainer.json` still describe the 2026 season (JDK 17, GCC 12.1, roboRIO toolchain, `.../wpilib/2026/jdk` paths), while `.versions` and the Dockerfile now target 2027 alpha (JDK 25, GCC 14.3, systemcore). The README also says the check runs at 04:00 UTC, but the workflow cron is `47 3 * * *`. Treat the workflows and Dockerfile as authoritative.

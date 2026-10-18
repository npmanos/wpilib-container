# WPILib container restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the version-scraping pipeline with a single `wpilib.version` pin and a Dockerfile that extracts what it needs from WPILib's installer bundle, verified by CI before publishing.

**Architecture:** Three small bash scripts hold all logic that can be tested without Docker (extraction, smoke test, version classification), each with a local test. The Dockerfile and workflows only wire those scripts together. Renovate (hosted app) bumps `wpilib.version`; CI is the only place Docker builds run.

**Tech Stack:** bash, GNU tar, python3 (JSON read), Docker BuildKit, GitHub Actions, Renovate.

**Spec:** `docs/superpowers/specs/2026-10-17-wpilib-container-restructure-design.md`

## Global Constraints

- Base image: `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`; image name `ghcr.io/npmanos/devcontainer_wpilib`.
- Build args are `WPILIB_VERSION` and `TARGETARCH` (`amd64` or `arm64`) only.
- Install root is `/home/vscode/.local/share/wpilib`; the year directory is the installer's `WpilibYear` (never derived from the version string); `.current` is a symlink to it; no `XDG_DATA_HOME` override.
- Keep list (only these are extracted): `jdk`, `systemcore`, `vsCodeExtensions`, `wpilibcode`, `vendordeps`, `documentation`, `tools/tools.json`, `installUtils`. `maven` must not exist in the image.
- Bundle URL: `https://packages.wpilib.workers.dev/installer/v${WPILIB_VERSION}/WPILib_Linux-${ARCH}-${WPILIB_VERSION}.tar.gz`, `ARCH` = `x64` (amd64) or `Arm64` (arm64). The installer CLI is never run.
- The Dockerfile sets `SHELL ["/bin/bash", "-o", "pipefail", "-c"]`.
- No Docker builds on the developer machine; CI is the test loop. Everything in Tasks 1-3 and 6 is testable locally without Docker.
- No scheduled workflow remains in the repo. GitHub Actions are pinned by commit SHA.
- Tags: full version always; major version (e.g. `2027`) and `latest` only for stable versions.
- Commit messages follow conventional commits; no attribution lines.

## Review Focus

Each line has its test in the named task.

1. Artifacts stream is missing a keep-list member (e.g. `tools/tools.json`): must fail the build, not ship an image without it. (Task 1)
2. Truncated or corrupt download mid-stream: must fail, leaving no half-installed year directory. (Task 1)
3. `WpilibYear` containing path separators or starting with `.`: must be rejected before any `mv`. (Task 1)
4. A pre-release that is neither alpha nor beta (e.g. `2027.1.1-rc-1`, which exists in WPILib history) must not take `latest` or the major tag. (Task 3)
5. `.current` dangling, or `JAVA_HOME` pointing somewhere other than `.current/jdk`: smoke test must fail rather than pass on a different Java. (Task 2)

Run all local tests with `bash tests/run-all.sh` (created in Task 1).

---

### Task 1: Artifact extraction script

**Files:**
- Create: `tests/lib.sh`, `tests/run-all.sh`, `tests/test_extract_artifacts.sh`, `scripts/extract-artifacts.sh`

**Interfaces:**
- Produces `tests/lib.sh` (sourced by every test): `assert_eq EXPECTED ACTUAL LABEL`, `assert_ok LABEL CMD...`, `assert_fails LABEL CMD...`, `finish` (exits non-zero if any assertion failed), and `$TMP` (a fresh temp dir removed on exit).
- Produces `tests/run-all.sh`: runs every `tests/test_*.sh`, exits non-zero if any fail.
- Produces `scripts/extract-artifacts.sh INSTALL_ROOT`: reads a gzip tar stream on stdin (the `*-artifacts.tar.gz`), extracts only the keep list into `INSTALL_ROOT/.staging`, reads `WpilibYear` from `.staging/installUtils/upgradeConfig.json`, moves staging to `INSTALL_ROOT/<WpilibYear>`, and creates symlink `INSTALL_ROOT/.current -> <WpilibYear>`. Exit non-zero with a message on stderr on any failure; on failure `.staging` is removed and no year directory or `.current` is left behind.

- [ ] **Step 1: Write `tests/lib.sh` and `tests/run-all.sh`.** Plain bash, `set -u`, counts failures, prints `ok`/`FAIL` per assertion.

- [ ] **Step 2: Write `tests/test_extract_artifacts.sh`.** A helper `make_artifacts OUT YEAR [OMIT_PATH...]` builds a fixture tar.gz containing every keep-list path with a small file each, plus unwanted `maven/x`, `advantagescope/x`, `elastic/x`, `icons/x`, `tools/artifacts/Glass.zip`, and `installUtils/upgradeConfig.json` holding `{"WpilibYear": "<YEAR>"}`. Cases, each running the script with the fixture on stdin and `$TMP/root` as install root:
  - good fixture, year `2027_alpha7`: `assert_eq 2027_alpha7 "$(readlink $TMP/root/.current)"`; `tools/tools.json`, `jdk/x`, `installUtils/upgradeConfig.json` exist under the year dir; `maven`, `advantagescope`, `tools/artifacts` do not.
  - fixture omitting `tools/tools.json`: `assert_fails`; `$TMP/root/.current` and `.staging` do not exist.
  - fixture omitting `installUtils/upgradeConfig.json`: `assert_fails`; no year directory.
  - good fixture truncated with `head -c 200` of the gz: `assert_fails`; no year directory, no `.staging`.
  - year `../evil` and year `.hidden`: `assert_fails`; `$TMP/evil` does not exist.

- [ ] **Step 3: Run `bash tests/run-all.sh`.** Expected: FAIL (script does not exist).

- [ ] **Step 4: Implement `scripts/extract-artifacts.sh`.** `set -euo pipefail`; a `trap` removes `.staging` on any failure. Use `tar -xz -C "$root/.staging"` with the keep-list members as arguments (GNU tar exits non-zero for a member not in the archive, which is what makes Review Focus 1 fail). Read the year with `python3 -c` (python3 is already in the image's apt list). Accept the year only if it matches `^[A-Za-z0-9][A-Za-z0-9_.-]*$`.

- [ ] **Step 5: Run `bash tests/run-all.sh`.** Expected: all `ok`, exit 0.

- [ ] **Step 6: Commit** `feat: add artifacts extraction script with tests`.

---

### Task 2: Smoke test script

**Files:**
- Create: `scripts/smoke-test.sh`, `tests/test_smoke_test.sh`

**Interfaces:**
- Consumes: `tests/lib.sh` (Task 1).
- Produces `scripts/smoke-test.sh [INSTALL_ROOT]` (default `$HOME/.local/share/wpilib`): exit 0 only if all hold, else non-zero with the failing check named on stderr: `INSTALL_ROOT/.current` resolves to a directory; `$JAVA_HOME` is set and resolves (realpath) to `INSTALL_ROOT/.current/jdk`; `java -version` via `PATH` exits 0; the first `INSTALL_ROOT/.current/systemcore/bin/*g++` runs `--version` and exits 0; a `vscode-wpilib-*.vsix` exists in `.current/vsCodeExtensions`; `.current/tools/tools.json` exists; `.current/maven` does not exist.

- [ ] **Step 1: Write `tests/test_smoke_test.sh`.** A helper `make_tree ROOT` builds a fake install: year dir `2027_alpha7`, `.current` symlink, stub executable `jdk/bin/java` (prints a version, exit 0), stub `systemcore/bin/arm64-g++` (exit 0), `vsCodeExtensions/vscode-wpilib-2027.0.0-alpha-7.vsix`, `tools/tools.json`. Each case runs the script with `JAVA_HOME=$ROOT/.current/jdk` and `PATH=$JAVA_HOME/bin:$PATH` unless stated. Cases: good tree passes; each of these fails (`assert_fails`): vsix removed; `maven/` directory added; `tools.json` removed; `.current` pointing at a nonexistent directory; `JAVA_HOME` set to a different directory containing a working `bin/java`; compiler stub exiting 1.

- [ ] **Step 2: Run `bash tests/run-all.sh`.** Expected: the smoke-test cases FAIL (script missing).

- [ ] **Step 3: Implement `scripts/smoke-test.sh`** per the Interfaces block, `set -u`, one function per check so the failing check is named.

- [ ] **Step 4: Run `bash tests/run-all.sh`.** Expected: all `ok`, exit 0.

- [ ] **Step 5: Commit** `feat: add image smoke test script with tests`.

---

### Task 3: Version classification script

**Files:**
- Create: `scripts/version-info.sh`, `tests/test_version_info.sh`

**Interfaces:**
- Consumes: `tests/lib.sh`.
- Produces `scripts/version-info.sh VERSION`: prints exactly two lines, `stable=true|false` and `major=<leading digits>`, suitable for appending to `$GITHUB_OUTPUT`. `stable` is true only for `^[0-9]+\.[0-9]+\.[0-9]+$` (any `-suffix` is a pre-release; this is deliberately broader than the spec's "alpha/beta" so `rc` is covered). Exits 1 with a message for input not matching `^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$`.

- [ ] **Step 1: Write `tests/test_version_info.sh`** with `assert_eq` on the exact two-line output for: `2027.0.0-alpha-7` → `stable=false`/`major=2027`; `2027.1.1-beta-1` → false/2027; `2027.1.1-rc-1` → false/2027; `2026.2.1` → true/2026; and `assert_fails` for `foo` and an empty string.

- [ ] **Step 2: Run `bash tests/run-all.sh`.** Expected: new cases FAIL.

- [ ] **Step 3: Implement `scripts/version-info.sh`** with a single regex match in bash.

- [ ] **Step 4: Run `bash tests/run-all.sh`.** Expected: all `ok`.

- [ ] **Step 5: Commit** `feat: add version classification script with tests`.

---

### Task 4: Dockerfile and version pin

**Files:**
- Create: `wpilib.version` (content: `2027.0.0-alpha-7`, one line)
- Modify (rewrite): `Dockerfile`

**Interfaces:**
- Consumes: `scripts/extract-artifacts.sh` (Task 1) via a BuildKit bind mount.
- Produces: an image where `JAVA_HOME=/home/vscode/.local/share/wpilib/.current/jdk` and `PATH` includes `$JAVA_HOME/bin` and `/home/vscode/.local/share/wpilib/.current/systemcore/bin`, passing `scripts/smoke-test.sh`.

- [ ] **Step 1: Rewrite the `Dockerfile`** keeping the base image, the two `source`/`base.name` labels, the existing apt package list, and `USER vscode` / `WORKDIR /home/vscode`. Add `ARG WPILIB_VERSION`, `ARG TARGETARCH`, `LABEL org.opencontainers.image.version="$WPILIB_VERSION"`, and the `SHELL` line from Global Constraints. One `RUN --mount=type=bind,source=scripts/extract-artifacts.sh,target=/tmp/extract-artifacts.sh` that: maps `TARGETARCH` to `ARCH` (`amd64`→`x64`, `arm64`→`Arm64`, anything else prints an error and exits 1); then `curl -fsSL <bundle URL> | tar -xzO --wildcards '*-artifacts.tar.gz' | bash /tmp/extract-artifacts.sh "$HOME/.local/share/wpilib"`. Then the two `ENV` lines from the spec and `CMD ["/bin/bash"]`. Remove the old JDK/toolchain/vsix steps, the `chown` step, and the `roborio`/`systemcore` PATH entries.

- [ ] **Step 2: Create `wpilib.version`.**

- [ ] **Step 3: Static check.** Run `docker run --rm -i hadolint/hadolint < Dockerfile` only if Docker is available; otherwise skip (no local builds are expected). Check by reading that every `ARG` used is declared and that `scripts/extract-artifacts.sh` is the mounted path.

- [ ] **Step 4: Commit** `refactor: build image from installer bundle artifacts`.

---

### Task 5: Workflows and removal of the old pipeline

**Files:**
- Create: `.github/workflows/pr.yml`
- Modify (rewrite): `.github/workflows/docker-publish.yml`
- Delete: `.github/workflows/check-versions.yml`, `scripts/update_versions.py`, `.versions`

**Interfaces:**
- Consumes: `scripts/version-info.sh` (Task 3), `scripts/smoke-test.sh` (Task 2), `tests/run-all.sh` (Task 1), `wpilib.version` and the `Dockerfile` (Task 4).

- [ ] **Step 1: Write `pr.yml`.** Trigger `pull_request`. Job `check`: checkout; `bash tests/run-all.sh`; read `wpilib.version` into `WPILIB_VERSION`; `docker/build-push-action` for `linux/amd64` with `push: false`, `load: true`, `build-args: WPILIB_VERSION=... TARGETARCH=amd64`; then `docker run --rm -v "$PWD/scripts:/scripts:ro" <image> /scripts/smoke-test.sh`. Job name must be a stable string (`check`), because Task 8's branch protection requires it.

- [ ] **Step 2: Rewrite `docker-publish.yml`.** Triggers: push to `develop` with paths `Dockerfile`, `wpilib.version`, `scripts/**`, `.github/workflows/docker-publish.yml`; plus `workflow_dispatch`. Keep the per-arch matrix (amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm`), push-by-digest, and digest artifact upload as in the current file. Changes: read `wpilib.version` (not `.versions`); pass only `WPILIB_VERSION` and `TARGETARCH` build args; after the build step, `docker run` the pushed digest (`ghcr.io/npmanos/devcontainer_wpilib@<digest>`) with the scripts mounted and `/scripts/smoke-test.sh`, failing the job on error; in `merge`, replace the `git clone` with `actions/checkout`, run `scripts/version-info.sh "$(cat wpilib.version)"` and write its output to `$GITHUB_OUTPUT`, then `docker/metadata-action` with `type=raw,value=<version>`, `type=raw,value=<major>,enable=<stable>`, and `type=raw,value=latest,enable=<stable>` (`flavor: latest=false`), and create the manifest with `docker buildx imagetools create $(jq -cr '.tags | map("-t " + .) | join(" ")' <<< "$DOCKER_METADATA_OUTPUT_JSON") <digest refs>`.

- [ ] **Step 3: Pin every action by commit SHA** with a trailing `# vX` comment: `actions/checkout`, `docker/setup-buildx-action`, `docker/login-action`, `docker/metadata-action`, `docker/build-push-action`, `actions/upload-artifact`, `actions/download-artifact`. Resolve each SHA with `gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object` and dereference annotated tags (`.object.type == "tag"` means fetch that object's `.sha` commit).

- [ ] **Step 4: Delete the three files** with `git rm`.

- [ ] **Step 5: Lint.** Run `pip install actionlint-py && actionlint .github/workflows/*.yml`. Expected: no output, exit 0.

- [ ] **Step 6: Commit** `ci: publish from wpilib.version and add PR checks`.

---

### Task 6: Renovate configuration

**Files:**
- Create: `renovate.json`

- [ ] **Step 1: Write `renovate.json`.** `baseBranches: ["develop"]`; `extends: ["config:recommended", "helpers:pinGitHubActionDigests"]`; a `customManagers` regex entry with `managerFilePatterns: ["/^wpilib\\.version$/"]`, `matchStrings: ["^(?<currentValue>\\S+)\\s*$"]`, `depNameTemplate: "wpilibsuite/WPILibInstaller-Avalonia"`, `datasourceTemplate: "github-tags"`, `extractVersionTemplate: "^v(?<version>.+)$"`; a `packageRules` entry with `matchManagers: ["custom.regex"]` and `automerge: true`; `ignoreUnstable: false` for that dependency so alphas are proposed.

- [ ] **Step 2: Validate the config.** Run `npx --yes --package renovate renovate-config-validator renovate.json`. Expected: `Config validated successfully`.

- [ ] **Step 3: Check prerelease ordering.** Run `LOG_LEVEL=debug npx --yes renovate --platform=local --dry-run=lookup 2>&1 | grep -iE 'wpilib|newVersion|currentVersion'` from the repo root. Expected: with `wpilib.version` set to `2027.0.0-alpha-5`, the proposed update is `2027.0.0-alpha-7`, not `alpha-6`. If the proposed version is wrong (plain semver sorts `alpha-10` before `alpha-7`), set `versioning` on the custom manager to a `regex:` scheme that parses `-alpha-N` / `-beta-N` as a numeric build component, and rerun this step until it passes. Restore `wpilib.version` afterwards (`git checkout wpilib.version`).

- [ ] **Step 4: Commit** `ci: add Renovate config for wpilib.version`.

---

### Task 7: Documentation

**Files:**
- Modify (rewrite as needed): `README.md`, `sample-devcontainer.json`, `CLAUDE.md`

- [ ] **Step 1: Rewrite `sample-devcontainer.json`** for the new layout: image `ghcr.io/npmanos/devcontainer_wpilib:2027.0.0-alpha-7`; every path under `/home/vscode/.local/share/wpilib/.current/` (`jdk` for `java.home`, `java.import.gradle.java.home`, the runtime path, and `JAVA_HOME`); runtime name `JavaSE-25`; `postCreateCommand` `code --install-extension /home/vscode/.local/share/wpilib/.current/vsCodeExtensions/vscode-wpilib-*.vsix`; name `WPILib 2027`.

- [ ] **Step 2: Rewrite `README.md`** to describe the current behavior: what the image contains (the keep list), the install root and `.current`, the tag scheme (version always; major and `latest` for stable only), the sample devcontainer, and that updates are proposed by Renovate against `wpilib.version`. Remove the stale 2026 / JDK 17 / GCC 12.1 / 04:00 UTC claims.

- [ ] **Step 3: Rewrite `CLAUDE.md`** so "What this repo is", "Commands", "Architecture", "Dockerfile specifics" and "Known doc drift" describe the new pipeline; delete "Known doc drift" if nothing drifts. Commands section: `bash tests/run-all.sh`; builds happen in CI only.

- [ ] **Step 4: Verify.** Run `python3 -m json.tool sample-devcontainer.json > /dev/null` (expected: no output) and `grep -rniE 'roborio|update_versions|\.versions|2026|jdk 17|XDG_DATA_HOME' README.md CLAUDE.md sample-devcontainer.json` (expected: no matches, except historical mentions deliberately kept; justify any that remain in the commit body).

- [ ] **Step 5: Commit** `docs: update README, sample devcontainer and CLAUDE.md`.

---

### Task 8: CI verification and handoff

**Files:** none (verification and repo settings).

- [ ] **Step 1: Push the branch and open a PR to `develop`** (`git push -u origin HEAD`, `gh pr create --base develop`). Ask the user before pushing.

- [ ] **Step 2: Watch the `check` job.** `gh run watch`. Expected: green. If it fails, the likely causes are the unverified items in the spec's Risks section; fix on the branch and push again. Specifically confirm in the job log that the `docker run` smoke test ran and printed each check.

- [ ] **Step 3: Verify the arm64 layout** by running the `docker-publish` workflow on the branch (`gh workflow run docker-publish.yml --ref <branch>`, only if the user approves pushing an image by digest), or by watching the first post-merge run. Expected: both arch jobs pass the smoke test.

- [ ] **Step 4: Report the owner-only prerequisites** to the user; they cannot be done from the repo: install the Renovate GitHub App on `npmanos/wpilib-container`; add a branch-protection rule on `develop` requiring the `check` job, so Renovate's automerge waits for it; after the first Renovate bump merges, confirm `docker-publish` ran (the spec lists this as unverified).

- [ ] **Step 5: Confirm tags after the first publish.** `gh api /users/npmanos/packages/container/devcontainer_wpilib/versions --jq '.[].metadata.container.tags'` shows the full version and, since the current version is an alpha, neither the `2027` tag nor `latest` moved.

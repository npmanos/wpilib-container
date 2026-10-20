# Java Variant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a Java-only image variant (`-java` tags) alongside the full image from one multi-stage Dockerfile, with the Gradle distribution pre-installed and unused directories dropped.

**Architecture:** Two new single-purpose bash scripts (`install-gradle.sh`, `split-cpp.sh`) and a variant-aware `smoke-test.sh` hold all logic that can be tested without Docker. The Dockerfile's throwaway `fetch` stage runs the scripts; `java` copies the result minus the C++ parts; `full` builds on `java` and adds them back. Workflows build both targets per architecture and publish a manifest per variant.

**Tech Stack:** bash, GNU tar, unzip, python3 (JSON read, test zip fixtures), Docker BuildKit multi-stage builds, GitHub Actions (`docker/build-push-action`, `docker/metadata-action`).

**Spec:** `docs/superpowers/specs/2026-10-19-java-variant-design.md`

## Global Constraints

- Variants: `full` (last Dockerfile stage, default target) and `java`. No C++-only variant.
- Tags: `<version><suffix>` always; `<major><suffix>` and `latest<suffix>` only when the version is stable **and** `github.ref == 'refs/heads/develop'`. Suffix is `""` for `full`, `-java` for `java`.
- Keep list: `jdk systemcore vsCodeExtensions vendordeps tools/tools.json installUtils`. `maven`, `documentation`, `wpilibcode` must not exist in either image.
- Gradle: unpack `Gradle.ZipName` from `installUtils/fullConfig.json` into `$GRADLE_USER_HOME/permwrapper/dists/<ZipName without .zip>/<Gradle.Hash>/`, create empty `<ZipName>.ok` there, delete the zip. Only `permwrapper/dists`.
- C++ split: `<year>/systemcore` and the `.vsix` of the `thirdPartyExtensions` entry named `ms-vscode.cpptools` in `installUtils/vscodeConfig.json`.
- Install root `/home/vscode/.local/share/wpilib`, `.current` symlink, base image `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`, `vscode` user unchanged. No `XDG_DATA_HOME` override.
- Filename validation: `ZipName` `^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$`, `.vsix` name `^[A-Za-z0-9][A-Za-z0-9_.-]*\.vsix$`, both without `..`; `Hash` `^[A-Za-z0-9]+$`.
- Smoke tests run with `docker run --rm --network none`.
- `pr.yml` job stays named `check`, runs on `ubuntu-24.04-arm`, builds `linux/arm64`.
- `scripts/*.sh` committed with mode 100755. Actions stay pinned by commit SHA (reuse the SHAs already in the workflows).
- Docker builds are not run on the developer machine; CI is the test loop for Tasks 5–7.
- Conventional commits; no attribution lines. Do not push or open PRs without asking the user.

## Review Focus

Each line has its test in the named task.

1. The arm64 bundle names the C++ extension `.vsix` differently from amd64: `split-cpp.sh` must follow `vscodeConfig.json`, not a hard-coded name. (Task 3: fixture uses `cpptools-linux-arm64.vsix`.)
2. A WPILib release drops or renames the Gradle zip, or its `fullConfig.json` lacks the `Gradle` block: the build must fail, not ship an image that downloads Gradle at runtime. (Task 2: missing zip, missing key.)
3. `vscodeConfig.json` has no `ms-vscode.cpptools` entry: `split-cpp.sh` must fail rather than silently ship a `java` image with the C++ extension or a `full` image without it. (Task 3.)
4. `smoke-test.sh` called with no variant or an unknown one (a workflow typo): must exit non-zero with usage, not run a partial check set and pass. (Task 4.)
5. A failed script must not leave half-moved state that a later step treats as success (e.g. `split-cpp.sh` moving `systemcore` then failing on the `.vsix`). (Task 3: on failure, `INSTALL_ROOT` is unchanged.)

---

### Task 1: Trim the extract keep list

**Files:**
- Modify: `scripts/extract-artifacts.sh` (the `KEEP=` line)
- Test: `tests/test_extract_artifacts.sh`

**Interfaces:**
- Produces: `INSTALL_ROOT/<year>/` containing only `jdk systemcore vsCodeExtensions vendordeps tools/tools.json installUtils`; `INSTALL_ROOT/.current -> <year>` (unchanged contract).

- [ ] **Step 1: Update the test.** In `tests/test_extract_artifacts.sh`: set the fixture `KEEP` to `(jdk/x systemcore/x vsCodeExtensions/x vendordeps/x tools/tools.json)`; add `wpilibcode/x documentation/x` to the list of dropped paths created in `make_artifacts` (next to `maven/x`); delete the dead first `tar -czf "$out" -C "$dir" .` line. Add after the existing "maven dropped" assertion:

```bash
assert_fails "wpilibcode dropped" test -e "$Y/wpilibcode"
assert_fails "documentation dropped" test -e "$Y/documentation"
```

- [ ] **Step 2: Run** `bash tests/test_extract_artifacts.sh`. Expected: the two new assertions FAIL (the fixture still contains both directories and the script still extracts them).

- [ ] **Step 3: Change `KEEP`** in `scripts/extract-artifacts.sh` to `(jdk systemcore vsCodeExtensions vendordeps tools/tools.json installUtils)`.

- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: all `ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/extract-artifacts.sh tests/test_extract_artifacts.sh
git commit -m "build: drop documentation and wpilibcode from the keep list"
```

### Task 2: `install-gradle.sh`

**Files:**
- Create: `scripts/install-gradle.sh` (mode 100755: `git add --chmod=+x`)
- Create: `tests/test_install_gradle.sh`

**Interfaces:**
- Consumes: `INSTALL_ROOT/.current/installUtils/fullConfig.json` with `{"Gradle": {"Hash": str, "ZipName": str, ...}}` and the zip beside it.
- Produces: `install-gradle.sh INSTALL_ROOT GRADLE_USER_HOME` → exit 0 and `GRADLE_USER_HOME/permwrapper/dists/<name>/<Hash>/{<unzipped top dir>, <ZipName>.ok}`; zip removed from `installUtils`. Exit non-zero (message on stderr naming the problem) on: wrong arg count, missing/invalid JSON or keys, invalid `ZipName`/`Hash`, missing zip, unzip failure.

- [ ] **Step 1: Write `tests/test_install_gradle.sh`** (source `lib.sh`, same style as `test_extract_artifacts.sh`). Fixture helper `make_install ROOT [ZIPNAME] [HASH]`: creates `ROOT/2027_alpha7/installUtils/`, `ROOT/.current -> 2027_alpha7`, writes `fullConfig.json` with the given values (defaults `gradle-9.4.1-bin.zip`, `arn2x92ynaizyzdaamcbpbhtj`), and builds the zip with python3 `zipfile` containing `gradle-9.4.1/bin/gradle` (text `stub`). Cases:

```bash
# good
G="$R/gh"; D="$G/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj"
assert_ok "good install" run "$R" "$G"
assert_ok "unpacked" test -f "$D/gradle-9.4.1/bin/gradle"
assert_ok "ok marker" test -f "$D/gradle-9.4.1-bin.zip.ok"
assert_eq 0 "$(stat -c %s "$D/gradle-9.4.1-bin.zip.ok")" "marker empty"
assert_fails "zip removed from installUtils" test -e "$R/.current/installUtils/gradle-9.4.1-bin.zip"
assert_fails "zip not copied to dists" test -e "$D/gradle-9.4.1-bin.zip"
# failures (fresh fixture each)
assert_fails "missing zip"            # rm the zip first
assert_fails "missing Gradle key"     # fullConfig.json = {}
assert_fails "ZipName with .."        # ZipName "../evil.zip"; also assert $TMP/evil.zip and $G absent
assert_fails "ZipName not .zip"       # "gradle-9.4.1-bin.tar"
assert_fails "Hash with slash"        # Hash "a/b"
assert_fails "wrong arg count"        # one argument
```

- [ ] **Step 2: Run** `bash tests/test_install_gradle.sh`. Expected: FAIL (script missing).

- [ ] **Step 3: Implement `scripts/install-gradle.sh`** with `set -euo pipefail`, a usage line comment like the other scripts, JSON read via `python3 -c` as in `extract-artifacts.sh`, validation regexes from Global Constraints, `unzip -q` into a staging dir inside the target `<Hash>/` parent then rename into place (so a failed unzip leaves no partial `<Hash>/` dir), then `: > <ZipName>.ok`, then `rm` the zip.

- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: all `ok` including `scripts/install-gradle.sh is executable in git` (after `git add --chmod=+x`).

- [ ] **Step 5: Commit**

```bash
git add --chmod=+x scripts/install-gradle.sh
git add tests/test_install_gradle.sh
git commit -m "build: add install-gradle.sh to pre-install the wrapper distribution"
```

### Task 3: `split-cpp.sh`

**Files:**
- Create: `scripts/split-cpp.sh` (mode 100755)
- Create: `tests/test_split_cpp.sh`

**Interfaces:**
- Consumes: `INSTALL_ROOT/.current -> <year>`; `<year>/systemcore/`; `<year>/installUtils/vscodeConfig.json` with `{"thirdPartyExtensions": [{"vsix": str, "name": str, ...}, ...]}`; `<year>/vsCodeExtensions/<vsix>`.
- Produces: `split-cpp.sh INSTALL_ROOT OUT_ROOT` → exit 0 with `OUT_ROOT/<year>/systemcore/` and `OUT_ROOT/<year>/vsCodeExtensions/<vsix>` moved out of `INSTALL_ROOT`. Exit non-zero with `INSTALL_ROOT` unchanged on: wrong arg count, dangling `.current`, missing/invalid JSON, no `ms-vscode.cpptools` entry, invalid vsix name, missing `systemcore` or `.vsix`.

- [ ] **Step 1: Write `tests/test_split_cpp.sh`.** Fixture `make_install ROOT [VSIX]` (default VSIX `cpptools-linux-arm64.vsix`): year `2027_alpha7`, `systemcore/bin/arm64-g++`, `vsCodeExtensions/{vscode-wpilib-2027.0.0-alpha-7.vsix, vscode-java-1.55.0-995.vsix, <VSIX>}`, `vscodeConfig.json` listing `redhat.java` → `vscode-java-1.55.0-995.vsix` and `ms-vscode.cpptools` → `<VSIX>`. Cases:

```bash
assert_ok "good split" run "$R" "$O"
assert_ok "systemcore moved" test -f "$O/2027_alpha7/systemcore/bin/arm64-g++"
assert_ok "cpptools vsix moved" test -f "$O/2027_alpha7/vsCodeExtensions/cpptools-linux-arm64.vsix"
assert_fails "systemcore gone from install" test -e "$R/2027_alpha7/systemcore"
assert_fails "cpptools gone from install" test -e "$R/2027_alpha7/vsCodeExtensions/cpptools-linux-arm64.vsix"
assert_ok "wpilib vsix stays" test -f "$R/2027_alpha7/vsCodeExtensions/vscode-wpilib-2027.0.0-alpha-7.vsix"
assert_ok "java vsix stays" test -f "$R/2027_alpha7/vsCodeExtensions/vscode-java-1.55.0-995.vsix"
# failures; after each, assert systemcore and every .vsix are still in $R/2027_alpha7 and $O/2027_alpha7 does not exist
assert_fails "no cpptools entry"        # drop the entry from vscodeConfig.json
assert_fails "cpptools vsix missing"    # rm the file (systemcore must stay put)
assert_fails "systemcore missing"       # rm -r systemcore
assert_fails "vsix name with .."        # entry vsix "../evil.vsix"
assert_fails "wrong arg count"
```

- [ ] **Step 2: Run** `bash tests/test_split_cpp.sh`. Expected: FAIL (script missing).

- [ ] **Step 3: Implement `scripts/split-cpp.sh`**: `set -euo pipefail`; year from `readlink "$1/.current"`, validated with the same pattern `extract-artifacts.sh` uses for `WpilibYear`; vsix name via `python3 -c` (exit non-zero if no matching entry); check both sources exist **before** moving anything; `mkdir -p` targets; `mv` both.

- [ ] **Step 4: Run** `bash tests/run-all.sh`. Expected: all `ok`.

- [ ] **Step 5: Commit**

```bash
git add --chmod=+x scripts/split-cpp.sh
git add tests/test_split_cpp.sh
git commit -m "build: add split-cpp.sh to separate the C++ toolchain and extension"
```

### Task 4: Variant-aware smoke test

**Files:**
- Modify: `scripts/smoke-test.sh`
- Modify: `tests/test_smoke_test.sh`
- Modify: `tests/lib.sh` (add `minimal_path`)

**Interfaces:**
- Consumes: the image layout produced by Tasks 1–3 and the Dockerfile (Task 5): `$GRADLE_USER_HOME` (default `$HOME/.gradle`) holds the unpacked distribution.
- Produces: `smoke-test.sh VARIANT [INSTALL_ROOT]`, `VARIANT ∈ {java, full}`, `INSTALL_ROOT` default `$HOME/.local/share/wpilib`. Exit 0 and `smoke-test: all checks passed` on success; otherwise one `smoke-test FAIL: <check>` line per failure on stderr, exit 1. Unknown/missing variant: usage on stderr, exit 2.
- External commands the script may use (the test PATH provides exactly these plus the fixture JDK): `bash sh python3 unzip mktemp rm realpath readlink dirname basename head cat ls`.

- [ ] **Step 1: Add `minimal_path DIR` to `tests/lib.sh`**: creates `DIR` with symlinks to the commands listed above (resolved with `command -v` from the caller's PATH) and prints `DIR`. Tests run the smoke test with `PATH="$jh/bin:$(minimal_path ...)"`, so a `g++`, `cmake` or `gdb` on the developer machine or runner is not visible.

- [ ] **Step 2: Rewrite the fixture in `tests/test_smoke_test.sh`.** `make_tree ROOT VARIANT [GRADLEW_EXIT]` builds, for both variants: the existing jdk/`java` stub, `tools/tools.json`, `installUtils/fullConfig.json` (Gradle `gradle-9.4.1-bin.zip` / `arn2x92ynaizyzdaamcbpbhtj`) and `vscodeConfig.json` (`ms-vscode.cpptools` → `cpptools-linux-x64.vsix`), `.current`, a WPILib `.vsix` built with python3 `zipfile` containing `extension/resources/gradle/shared/gradlew` = `#!/bin/sh\nexit <GRADLEW_EXIT default 0>`, and `$HOME_FIXTURE/.gradle/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/{gradle-9.4.1/, gradle-9.4.1-bin.zip.ok}`. For `full` it adds `systemcore/bin/arm64-g++` (exit 0) and `vsCodeExtensions/cpptools-linux-x64.vsix`. `run_smoke VARIANT ROOT [JAVA_HOME]` runs with `HOME`/`GRADLE_USER_HOME` pointed at the fixture and the minimal PATH. Cases:

```bash
fresh full; assert_ok "full: good tree passes" run_smoke full "$R"
fresh java; assert_ok "java: good tree passes" run_smoke java "$R"
assert_fails "no variant" bash "$SCRIPT"
assert_fails "unknown variant" run_smoke cpp "$R"
# both variants (loop over java full), fresh tree each:
#   existing cases: missing WPILib vsix, maven present, missing tools.json, dangling .current, JAVA_HOME elsewhere
#   new: documentation present; wpilibcode present; zip left in installUtils;
#        .ok marker missing; unpacked dist dir missing; gradlew exits 1 (make_tree ... 1)
# full only: compiler exits 1; cpptools vsix missing
# java only: systemcore present; cpptools vsix present;
#            a fake `cmake` (exit 0) in a dir prepended to PATH → fails; same for `gdb` and `g++`
```

- [ ] **Step 3: Run** `bash tests/test_smoke_test.sh`. Expected: FAIL (script takes no variant yet).

- [ ] **Step 4: Update `scripts/smoke-test.sh`.** Keep the existing `check_*` style and `fail()` collector. Parse `VARIANT` first (usage + exit 2 on bad value). Add: `check_removed` (documentation, wpilibcode, no `installUtils/*.zip`), `check_gradle_layout` (paths from `fullConfig.json` via `python3`), `check_gradle_wrapper` (`unzip -q <wpilib vsix> 'extension/resources/gradle/shared/*' -d "$(mktemp -d)"`, then `sh ./gradlew --version` from that `shared/` dir; clean up the temp dir), `check_cpptools_vsix present|absent` (name from `vscodeConfig.json`), `check_no_systemcore`, `check_no_native_tools` (`command -v cmake gdb g++` must find none). `full` runs the existing `check_compiler` plus `check_cpptools_vsix present`; `java` runs `check_no_systemcore`, `check_cpptools_vsix absent`, `check_no_native_tools`.

- [ ] **Step 5: Run** `bash tests/run-all.sh`. Expected: all `ok`.

- [ ] **Step 6: Commit**

```bash
git add scripts/smoke-test.sh tests/test_smoke_test.sh tests/lib.sh
git commit -m "test: make smoke-test.sh variant-aware and check the Gradle install"
```

### Task 5: Multi-stage Dockerfile

**Files:**
- Modify: `Dockerfile`

**Interfaces:**
- Consumes: `extract-artifacts.sh INSTALL_ROOT` (stdin), `install-gradle.sh INSTALL_ROOT GRADLE_USER_HOME`, `split-cpp.sh INSTALL_ROOT OUT_ROOT`.
- Produces: build targets `java` and `full` (last stage); build args `WPILIB_VERSION`, `TARGETARCH` as today.

- [ ] **Step 1: Restructure the Dockerfile** into the four stages from the spec's Dockerfile section:
  - `base`: `FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base`, the existing `LABEL`s (declare `ARG WPILIB_VERSION` in this stage for the version label), `SHELL ["/bin/bash", "-o", "pipefail", "-c"]`, `ENV DEBIAN_FRONTEND=noninteractive`, apt `wget curl git unzip sudo python3 python3-pip` with the existing clean-up.
  - `fetch`: re-declare `ARG WPILIB_VERSION` and `ARG TARGETARCH`; `USER vscode`, `WORKDIR /home/vscode`; one `RUN` with `--mount=type=bind,source=scripts,target=/tmp/scripts` that runs the existing streaming pipeline into `extract-artifacts.sh`, then `install-gradle.sh "$HOME/.local/share/wpilib" "$HOME/.gradle"`, then `split-cpp.sh "$HOME/.local/share/wpilib" "$HOME/.wpilib-cpp"`.
  - `java`: `FROM base AS java`, `USER vscode`, `WORKDIR /home/vscode`, the two `COPY --from=fetch --chown=vscode:vscode` lines, `ENV JAVA_HOME=/home/vscode/.local/share/wpilib/.current/jdk` and `ENV PATH=${JAVA_HOME}/bin:$PATH`, `CMD [ "/bin/bash" ]`.
  - `full`: `FROM java AS full`, `USER root`, apt `build-essential cmake gdb` with clean-up, `USER vscode`, `COPY --from=fetch --chown=vscode:vscode /home/vscode/.wpilib-cpp/ /home/vscode/.local/share/wpilib/`, `ENV PATH=$PATH:/home/vscode/.local/share/wpilib/.current/systemcore/bin`.

- [ ] **Step 2: Lint** with `docker buildx build --check .` (static check only, does not build). Expected: no errors. If `buildx --check` is unavailable, skip; Task 6's PR build is the real test.

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "build: split the Dockerfile into java and full targets"
```

### Task 6: PR workflow

**Files:**
- Modify: `.github/workflows/pr.yml`

**Interfaces:**
- Consumes: Dockerfile targets `java`, `full`; `smoke-test.sh VARIANT`.

- [ ] **Step 1: Edit `pr.yml`.** Job id and `name` stay `check`; `runs-on: ubuntu-24.04-arm`. Keep the script-test and version steps. Replace the single build with two `docker/build-push-action` steps (same pinned SHA): `target: java`, `tags: wpilib-test:java`, then `target: full`, `tags: wpilib-test:full`; both `platforms: linux/arm64`, `push: false`, `load: true`, `cache-from: type=gha,scope=linux/arm64`, build args `WPILIB_VERSION` and `TARGETARCH=arm64`. Replace the smoke step with two runs: `docker run --rm --network none -v "$PWD/scripts:/scripts:ro" wpilib-test:<variant> /scripts/smoke-test.sh <variant>`.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/pr.yml
git commit -m "ci: build and smoke-test both variants on arm64 in PR checks"
```

### Task 7: Publish workflow

**Files:**
- Modify: `.github/workflows/docker-publish.yml`

**Interfaces:**
- Consumes: Dockerfile targets; `smoke-test.sh VARIANT`; `scripts/version-info.sh` (outputs `stable`, `major`).
- Produces: artifacts `digests-<variant>-<arch>`; manifests and tags per Global Constraints.

- [ ] **Step 1: Add** at workflow level:

```yaml
concurrency:
  group: docker-publish
  cancel-in-progress: false
```

- [ ] **Step 2: Rework the `build` job.** Remove the `outputs:` block. Replace the single build step with: build `target: java` (step id `build_java`, `cache-from` only), smoke-test its digest with `java`, build `target: full` (step id `build_full`, `cache-from` and `cache-to: type=gha,mode=max,scope=${{ matrix.platform }}`), smoke-test its digest with `full`. Both builds keep `push-by-digest=true,name-canonical=true,push=true` outputs and the existing build args. Smoke runs use `--network none`. Export each digest into `/tmp/digests/<variant>/` and upload two artifacts, `digests-java-${{ matrix.arch }}` and `digests-full-${{ matrix.arch }}`, with the existing `if-no-files-found: error` and `retention-days: 1`.

- [ ] **Step 3: Rework the `merge` job.** Add:

```yaml
strategy:
  matrix:
    include:
      - variant: full
        suffix: ""
      - variant: java
        suffix: "-java"
```

  Download with `pattern: digests-${{ matrix.variant }}-*`. Tags in the metadata step:

```yaml
tags: |
  type=raw,value=${{ steps.version.outputs.version }}${{ matrix.suffix }}
  type=raw,value=${{ steps.version.outputs.major }}${{ matrix.suffix }},enable=${{ steps.version.outputs.stable == 'true' && github.ref == 'refs/heads/develop' }}
  type=raw,value=latest${{ matrix.suffix }},enable=${{ steps.version.outputs.stable == 'true' && github.ref == 'refs/heads/develop' }}
```

  Keep `flavor: latest=false` and the manifest-creation step unchanged.

- [ ] **Step 4: Validate YAML** with `python3 -c 'import yaml,sys; [yaml.safe_load(open(f)) for f in sys.argv[1:]]' .github/workflows/*.yml` (install `python3-yaml` or `pip install pyyaml` locally if missing). Expected: no output, exit 0. If `actionlint` is installed, run it too.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/docker-publish.yml
git commit -m "ci: publish full and java variants with ordered runs and guarded moving tags"
```

### Task 8: Documentation

**Files:**
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: README.** Add a "Variants" section (full vs. java contents per the spec's Image contents table); add `-java` rows to the tags table (`2027.0.0-alpha-7-java`, `2027-java`, `latest-java`); add a sentence that the Gradle distribution WPILib projects use is pre-installed under `~/.gradle/permwrapper/dists`; remove `documentation` and `wpilibcode` from "Also included"; under the sample config, show the two changes for `java` (image tag with `-java`, drop `ms-vscode.cpptools-extension-pack`). Update the "Updates" paragraph to say each variant is smoke-tested. `sample-devcontainer.json` is unchanged.

- [ ] **Step 2: CLAUDE.md.** Architecture: describe the `base`/`fetch`/`java`/`full` stages, the two new scripts and their one-line contracts, the variant tag scheme with the develop-only guard and the `concurrency` group, and that `pr.yml` runs on arm64. Install layout: add `~/.gradle/permwrapper/dists/...`, note `systemcore` on `PATH` in `full` only, update the keep list. Remove the TODOs for the dead `tar`, the unused `digest` output, and `concurrency`/older-ref. Keep the Renovate automerge TODO and the "Unverified" section.

- [ ] **Step 3: Run** `bash tests/run-all.sh`. Expected: all `ok`.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document the java variant and Gradle pre-install"
```

### Task 9: CI verification (requires user approval to push)

- [ ] **Step 1: Ask the user** before pushing `feat/java-variant` and opening a PR against `develop`.
- [ ] **Step 2: Watch the `check` run** (`gh pr checks --watch`). Expected: script tests pass; both arm64 targets build; both smoke tests print `smoke-test: all checks passed`. If the `java` smoke test fails only on `g++` being present from the base image, drop `g++` from `check_no_native_tools` (spec Testing section allows this), update the test, commit, and re-run.
- [ ] **Step 3: Report** the result. Publishing (merge to `develop`, or a deliberate `gh workflow run docker-publish.yml --ref feat/java-variant`) is the user's decision; after a publish, confirm with `docker buildx imagetools inspect ghcr.io/npmanos/devcontainer_wpilib:<version>-java` that the manifest lists amd64 and arm64.

# Java variant: design

Date: 2026-10-19
Status: draft, awaiting review

## Goal

Publish a Java-only variant of the image alongside the existing full image. The Java variant leaves out the systemcore C++ toolchain, the C/C++ apt packages and the C++ VS Code extension, which Java teams never use. Both variants stay general-purpose FRC images; nothing here is specific to one team's hosting.

While restructuring the build, align the image with what the WPILib installer actually installs (verified against a `WPILibInstaller-CLI` install of 2027.0.0-alpha-7):

- Put the bundled Gradle distribution where the WPILib project templates' wrapper looks for it, unpacked, so the first build does not download Gradle.
- Stop shipping directories that do nothing in a container (`documentation`, `wpilibcode`) and the Gradle zip inside `installUtils`.

## Scope

- Two variants: `full` (today's image, minus the removals above) and `java`. No separate C++ variant: WPILib C++ projects build through GradleRIO and need the JDK, so it would differ from `full` by almost nothing.
- `gh`, `jj`, code-server and similar tools are not added. Consumers add them with dev container features.
- `wpilib.version` remains the only version input. Renovate configuration is unchanged.

Non-goals: changing the base image or the `vscode` user's UID; including the offline Maven repository (`maven`, 1.4 GB); the Renovate automerge question for Actions pin bumps.

## Image contents

| Item | `java` | `full` |
|---|---|---|
| `jdk`, `vendordeps`, `tools/tools.json` | yes | yes |
| `vsCodeExtensions`: WPILib and Java `.vsix` files | yes | yes |
| `vsCodeExtensions`: C++ extension `.vsix` (`ms-vscode.cpptools`) | no | yes |
| `systemcore` (cross-compiler), on `PATH` | no | yes |
| apt `build-essential`, `cmake`, `gdb` | no | yes |
| `installUtils` JSON files (no Gradle zip) | yes | yes |
| Gradle distribution unpacked under `~/.gradle/permwrapper/dists` | yes | yes |
| `wpilibcode`, `documentation`, `maven` | no | no |

Not extracted in either variant, as today: `maven`, `advantagescope`, `elastic`, `icons` and the `tools` binaries. The installer downloads VS Code itself at install time rather than bundling it, so there is nothing to exclude for it.

`wpilibcode` holds a launcher for the installer-downloaded desktop VS Code and a script that sets `JAVA_HOME`; the image sets `JAVA_HOME` itself. `documentation` (425 MB) is the offline copy of the online docs.

### Gradle distribution

`installUtils/fullConfig.json` names the zip, the wrapper hash and the extract locations:

```json
"Gradle": { "Hash": "arn2x92ynaizyzdaamcbpbhtj", "ZipName": "gradle-9.4.1-bin.zip",
            "ExtractLocations": ["wrapper/dists", "permwrapper/dists"] }
```

The installer copies the zip into `~/.gradle/<location>/<zip name without .zip>/<Hash>/` and leaves unpacking to the wrapper on first use. The WPILib templates' `gradle-wrapper.properties` sets `distributionPath=permwrapper/dists`.

The image goes one step further and unpacks the zip at build time, so the distribution sits in a shared read-only layer instead of being unpacked into every container's writable layer on first build. The result follows the layout the wrapper itself produces:

```
~/.gradle/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/
    gradle-9.4.1/              unpacked distribution
    gradle-9.4.1-bin.zip.ok    empty marker
```

The zip is deleted afterwards. Only `permwrapper/dists` is populated; `wrapper/dists` is only used by projects that keep Gradle's default wrapper path. Net image growth is about 21 MB (153 MB unpacked, 132 MB zip). The smoke test proves the wrapper uses this copy (see Testing).

## Build scripts

Each script has one job, parses JSON with `python3` like `extract-artifacts.sh`, and is committed executable.

### `scripts/extract-artifacts.sh` (changed)

`KEEP` becomes `jdk systemcore vsCodeExtensions vendordeps tools/tools.json installUtils`. Everything else in the script is unchanged.

### `scripts/install-gradle.sh INSTALL_ROOT GRADLE_USER_HOME` (new)

1. Read `Gradle.ZipName` and `Gradle.Hash` from `INSTALL_ROOT/.current/installUtils/fullConfig.json`.
2. Validate both. `ZipName` must match `^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$` and must not contain `..`. `Hash` must match `^[A-Za-z0-9]+$`. Exit non-zero otherwise.
3. Fail if `INSTALL_ROOT/.current/installUtils/<ZipName>` does not exist.
4. Unzip it into `GRADLE_USER_HOME/permwrapper/dists/<ZipName without .zip>/<Hash>/`.
5. Create the empty file `<ZipName>.ok` in that directory.
6. Delete the zip from `installUtils`.

### `scripts/split-cpp.sh INSTALL_ROOT OUT_ROOT` (new)

1. Resolve the year directory name from the `INSTALL_ROOT/.current` symlink.
2. Read the `.vsix` filename of the entry named `ms-vscode.cpptools` in `thirdPartyExtensions` of `INSTALL_ROOT/.current/installUtils/vscodeConfig.json`. Validate it like `ZipName` (with a `.vsix` suffix).
3. Fail if `<year>/systemcore` or `<year>/vsCodeExtensions/<vsix>` is missing.
4. Move both to `OUT_ROOT/<year>/systemcore` and `OUT_ROOT/<year>/vsCodeExtensions/<vsix>`, keeping their paths relative to the year directory.

Reading the filename from WPILib's config means a renamed file is followed automatically, and the arm64 bundle's differently named file is handled the same way.

## Dockerfile

One multi-stage Dockerfile. `full` is the last stage, so `docker build .` without `--target` still produces the full image.

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base
# apt: wget curl git unzip sudo python3 python3-pip

FROM base AS fetch
USER vscode
# stream the installer bundle | extract-artifacts.sh ~/.local/share/wpilib   (unchanged)
# install-gradle.sh ~/.local/share/wpilib ~/.gradle
# split-cpp.sh      ~/.local/share/wpilib ~/.wpilib-cpp

FROM base AS java
USER vscode
COPY --from=fetch --chown=vscode:vscode /home/vscode/.local/share/wpilib /home/vscode/.local/share/wpilib
COPY --from=fetch --chown=vscode:vscode /home/vscode/.gradle /home/vscode/.gradle
ENV JAVA_HOME=/home/vscode/.local/share/wpilib/.current/jdk
ENV PATH=${JAVA_HOME}/bin:$PATH

FROM java AS full
USER root
# apt: build-essential cmake gdb
USER vscode
COPY --from=fetch --chown=vscode:vscode /home/vscode/.wpilib-cpp/ /home/vscode/.local/share/wpilib/
ENV PATH=$PATH:/home/vscode/.local/share/wpilib/.current/systemcore/bin
```

- The `fetch` stage is never published. The installer bundle is still streamed, so no tarball lands in any layer.
- `full` builds on `java`, so a host or registry holding both stores the shared layers once.
- The year directory name (`2027_alpha7`) is unknown when the Dockerfile is written. `split-cpp.sh` writes a tree that mirrors `<year>/…`, and `full` copies that tree onto `~/.local/share/wpilib/`, which merges it into the right year directory.
- Every `COPY --from` sets `--chown=vscode:vscode`.
- `python3` stays in `base` because the build scripts use it. It was already in the image.
- Existing labels stay. `org.opencontainers.image.version` is set in both variants.

## CI

### `docker-publish.yml`

- **Concurrency:** add a workflow-level group with `cancel-in-progress: false`, so overlapping runs execute in order and the newest commit publishes last. Cancelling a run in progress could leave one variant's tags updated and the other's not.
- **Build job:** same matrix as today (amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm`). Each job builds `--target java`, then `--target full`, in the same builder, so the second reuses the cached `fetch` stage and the bundle downloads once per architecture. Each target is pushed by digest, smoke-tested by digest with its variant, and recorded in its own artifact, `digests-<variant>-<arch>`. Cache scope stays per platform.
- **Merge job:** a matrix over `variant: full` (suffix `""`) and `variant: java` (suffix `-java`). Each job downloads `digests-<variant>-*` and creates the manifest list with explicitly written tags:

  ```
  type=raw,value=<version><suffix>
  type=raw,value=<major><suffix>,enable=<stable && ref is develop>
  type=raw,value=latest<suffix>,enable=<stable && ref is develop>
  ```

  "Ref is develop" means `github.ref == 'refs/heads/develop'`. A manual dispatch from another branch still publishes its exact version tag but cannot move the major or `latest` tags.
- Remove the build job's unused `digest` output.

Resulting tags for a stable version `2027.1.0`: `2027.1.0`, `2027`, `latest`, `2027.1.0-java`, `2027-java`, `latest-java`. A pre-release such as `2027.0.0-alpha-7` gets only `2027.0.0-alpha-7` and `2027.0.0-alpha-7-java`.

### `pr.yml`

The single job keeps the name `check` (the required status). It moves to `ubuntu-24.04-arm` and builds for `linux/arm64`, reading cache from `scope=linux/arm64`. After the script tests, it builds `--target java` and `--target full` with `load: true` and smoke-tests each. amd64 is first built and smoke-tested in the publish workflow, before any tag moves.

### Smoke test invocation

Both workflows run `docker run --rm --network none -v "$PWD/scripts:/scripts:ro" <image> /scripts/smoke-test.sh <variant>`. No check needs the network, and the Gradle wrapper check depends on having none.

## Testing

### `scripts/smoke-test.sh VARIANT [INSTALL_ROOT]`

`VARIANT` is required and must be `java` or `full`. `INSTALL_ROOT` defaults to `$HOME/.local/share/wpilib`. As today, every failing check is named on stderr and the script exits non-zero if any failed.

Both variants:

- `.current` resolves to a directory; `JAVA_HOME` resolves to `.current/jdk`; `java -version` succeeds (existing).
- A `vscode-wpilib-*.vsix` exists; `tools/tools.json` exists; `maven` does not exist (existing).
- `documentation` and `wpilibcode` do not exist; `installUtils` contains no `*.zip`.
- Gradle layout: using `ZipName` and `Hash` from `fullConfig.json`, the unpacked distribution directory and the `.ok` marker exist under `$HOME/.gradle/permwrapper/dists/<name>/<Hash>/`.
- Gradle wrapper: unzip `extension/resources/gradle/shared/` from the WPILib `.vsix` into a temporary directory and run `./gradlew --version` there. With the network disabled, this fails if the wrapper does not use the pre-installed distribution. Because it uses WPILib's own wrapper files, it also catches a release whose wrapper URL or hash no longer matches the installed distribution.

`full` only:

- A `*g++` in `.current/systemcore/bin` runs `--version` successfully (existing).
- The C++ extension `.vsix` named in `vscodeConfig.json` exists.

`java` only:

- `.current/systemcore` does not exist.
- The C++ extension `.vsix` named in `vscodeConfig.json` does not exist.
- `cmake` and `gdb` are not on `PATH`. (The base image ships `g++` as part of `build-essential`, confirmed by the first CI run, so `g++` is not checked.)

### Script tests (`tests/`, no Docker)

- `test_extract_artifacts.sh`: fixture updated for the new keep list. Remove the dead first `tar -czf` in `make_artifacts`.
- `test_install_gradle.sh` (new): unpacks into `permwrapper/dists/<name>/<hash>/`, creates the `.ok` marker, removes the zip; fails when the zip is missing; rejects an invalid `ZipName` or `Hash`.
- `test_split_cpp.sh` (new): moves `systemcore` and the configured C++ `.vsix` into `OUT_ROOT/<year>/…`; leaves the other `.vsix` files in place; fails when either item is missing.
- `test_smoke_test.sh`: one fixture per variant, each passing on a good tree, plus a failing case for each new check. The fixture's `.vsix` is a real zip containing a stub `gradlew` (`exit 0`, or `exit 1` for the failure case), so the wrapper check runs without Gradle.
- `test_scripts_executable.sh` already covers every `scripts/*.sh`.

## Documentation

- `README.md`: a "Variants" section describing both images and what `java` leaves out; `-java` rows in the tags table; a note that the Gradle distribution used by WPILib projects is pre-installed; `documentation` and `wpilibcode` removed from the list of included directories.
- `sample-devcontainer.json`: stays the `full` example. The README shows the changes for `java`: the image tag, and dropping `ms-vscode.cpptools-extension-pack`.
- `CLAUDE.md`: describe the stages, the variant split, the two new scripts and the `~/.gradle/permwrapper/dists` location. Remove the resolved TODOs: the dead `tar`, the unused `digest` output, and the missing `concurrency` group and older-ref guard. The Renovate automerge TODO stays.

## Risks and assumptions

- The Gradle wrapper treats a distribution as installed when `<zip>.ok` exists next to the unpacked directory. This is inferred from the layout the wrapper writes. The smoke test's wrapper check verifies it.
- `COPY --from` keeps the `.current` symlink when copying the directory. The smoke test's `.current` check verifies it.
- The devcontainer base image does not provide `cmake` or `gdb`. The `java` smoke test verifies it. It does provide `gcc`, `g++` and `make`; purging them would not shrink the image.
- Builds still need network access for WPILib libraries and the GradleRIO plugin (published on the Gradle Plugin Portal), as today.

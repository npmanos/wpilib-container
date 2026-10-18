# WPILib Dev Container

A pre-configured Development Container for FRC robot code development. The image is built from WPILib's own installer bundle, so it contains the same JDK, cross-compiler toolchain and VS Code extension that the official installer provides.

## Features

* **Base OS:** Ubuntu 24.04 (via Microsoft Dev Containers base)
* **Java:** the WPILib JDK
* **Compiler:** the WPILib systemcore cross-compiler toolchain
* **IDE Support:** the WPILib VS Code extension (`.vsix`, installed by your `postCreateCommand`)
* **Also included:** `vendordeps`, `wpilibcode`, `documentation` and `tools/tools.json` from the WPILib install. The Maven repository, AdvantageScope, Elastic, icons and the tool binaries are not included.

## Install layout

WPILib is installed under `/home/vscode/.local/share/wpilib/<WpilibYear>/`, the installer's default location. `<WpilibYear>` is the directory name the installer uses for that release (for example `2027_alpha7` for an alpha). Because that name varies between releases, `/home/vscode/.local/share/wpilib/.current` is a symlink to it. Use `.current` in paths. `JAVA_HOME` and `PATH` are already set in the image.

## Usage

This image is designed to be used with [Github Codespaces](https://github.com/features/codespaces) or the [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers) extension.

### devcontainer.json Configuration

Add a [.devcontainer/devcontainer.json](sample-devcontainer.json) file to your robot project with the following configuration. This sets up the environment variables and paths to use the pre-installed tools instead of downloading them locally.

```json
{
    "name": "WPILib 2027",
    "image": "ghcr.io/npmanos/devcontainer_wpilib:2027.0.0-alpha-7",
    "customizations": {
        "vscode": {
            "settings": {
                "java.home": "/home/vscode/.local/share/wpilib/.current/jdk",
                "java.import.gradle.java.home": "/home/vscode/.local/share/wpilib/.current/jdk",
                "java.configuration.runtimes": [
                    {
                        "name": "JavaSE-25",
                        "path": "/home/vscode/.local/share/wpilib/.current/jdk",
                        "default": true
                    }
                ],
                "terminal.integrated.env.linux": {
                    "JAVA_HOME": "/home/vscode/.local/share/wpilib/.current/jdk"
                }
            },
            "extensions": [
                "vscjava.vscode-java-pack",
                "ms-vscode.cpptools-extension-pack"
            ]
        }
    },
    "postCreateCommand": "code --install-extension /home/vscode/.local/share/wpilib/.current/vsCodeExtensions/vscode-wpilib-*.vsix",
    "remoteUser": "vscode",
    "features": {
        "ghcr.io/stuartleeks/dev-container-features/shell-history:0": {}
    }
}
```

### Gradle Setup

The container includes the necessary compilers. Your build.gradle should function normally, as the JAVA_HOME environment variable is set globally within the container to point to the correct JDK.

## Container Tags

Images are published to the GitHub Container Registry (ghcr.io).

| Tag     | Description                                                                 | Example                                              |
| :----   | :----                                                                       | :----                                                |
| VERSION | A specific WPILib version. Always published.                                | ghcr.io/npmanos/devcontainer_wpilib:2027.0.0-alpha-7 |
| MAJOR   | The latest stable build for a season. Not moved by alpha, beta or rc builds. | ghcr.io/npmanos/devcontainer_wpilib:2027             |
| latest  | The most recent stable build. Not moved by pre-releases.                    | ghcr.io/npmanos/devcontainer_wpilib:latest           |

Images published before the 2027 season used other tags (for example `2026`) and are unchanged.

## Updates

The WPILib version is pinned in [wpilib.version](wpilib.version). [Renovate](https://docs.renovatebot.com/) watches tags on [WPILibInstaller-Avalonia](https://github.com/wpilibsuite/WPILibInstaller-Avalonia) and opens a pull request against `develop` when a new version appears. When the PR checks pass it merges, and the merge builds and publishes the new image.

The Dockerfile downloads the installer bundle for that version and extracts only the files listed in [scripts/extract-artifacts.sh](scripts/extract-artifacts.sh). Pull requests build the amd64 image and run [scripts/smoke-test.sh](scripts/smoke-test.sh) against it. The publish workflow runs the same smoke test on each architecture before creating the multi-arch manifest.

## License

This project is released into the public domain under The Unlicense. See [LICENSE](LICENSE) for details.

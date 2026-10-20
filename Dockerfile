FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base

LABEL org.opencontainers.image.source="https://github.com/npmanos/wpilib-container"
LABEL org.opencontainers.image.base.name="mcr.microsoft.com/devcontainers/base:ubuntu-24.04"

ARG WPILIB_VERSION

LABEL org.opencontainers.image.version="$WPILIB_VERSION"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Install core dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    git \
    unzip \
    sudo \
    python3 \
    python3-pip \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Throwaway stage: download the installer bundle and prepare the install tree.
FROM base AS fetch

ARG WPILIB_VERSION
ARG TARGETARCH

USER vscode
WORKDIR /home/vscode

# Stream the installer bundle, pull out its artifacts tarball, and extract only the keep list
# into ~/.local/share/wpilib/<WpilibYear> (scripts/extract-artifacts.sh). Then pre-install the
# Gradle distribution (scripts/install-gradle.sh) and move the C++ parts aside for the full
# image (scripts/split-cpp.sh).
RUN --mount=type=bind,source=scripts,target=/tmp/scripts \
    case "${TARGETARCH}" in \
        amd64) ARCH=x64 ;; \
        arm64) ARCH=Arm64 ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && mkdir -p "$HOME/.local/share/wpilib" \
    && curl -fsSL "https://packages.wpilib.workers.dev/installer/v${WPILIB_VERSION}/WPILib_Linux-${ARCH}-${WPILIB_VERSION}.tar.gz" \
        | tar -xzO --wildcards '*-artifacts.tar.gz' \
        | bash /tmp/scripts/extract-artifacts.sh "$HOME/.local/share/wpilib" \
    && bash /tmp/scripts/install-gradle.sh "$HOME/.local/share/wpilib" "$HOME/.gradle" \
    && bash /tmp/scripts/split-cpp.sh "$HOME/.local/share/wpilib" "$HOME/.wpilib-cpp"

# Java variant: JDK, VS Code extensions, vendordeps, tools.json, and the pre-installed Gradle.
FROM base AS java

USER vscode
WORKDIR /home/vscode

COPY --from=fetch --chown=vscode:vscode /home/vscode/.local/share/wpilib/ /home/vscode/.local/share/wpilib/
COPY --from=fetch --chown=vscode:vscode /home/vscode/.gradle/ /home/vscode/.gradle/

# Environment Setup
ENV JAVA_HOME=/home/vscode/.local/share/wpilib/.current/jdk
ENV PATH=${JAVA_HOME}/bin:$PATH

CMD [ "/bin/bash" ]

# Full variant (last stage, so it is the default target): java plus the C++ toolchain.
FROM java AS full

USER root
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    gdb \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

USER vscode
COPY --from=fetch --chown=vscode:vscode /home/vscode/.wpilib-cpp/ /home/vscode/.local/share/wpilib/

ENV PATH=$PATH:/home/vscode/.local/share/wpilib/.current/systemcore/bin

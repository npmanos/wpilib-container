FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS base

LABEL org.opencontainers.image.source="https://github.com/npmanos/wpilib-container"
LABEL org.opencontainers.image.base.name="mcr.microsoft.com/devcontainers/base:ubuntu-24.04"

ARG WPILIB_VERSION

LABEL org.opencontainers.image.version="$WPILIB_VERSION"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Install core dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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

# Look up the installer URL and cross-compiler directory for this season and architecture
# (scripts/installer-info.sh), stream the installer bundle, pull out its artifacts tarball, and
# extract only the keep list into ~/.local/share/wpilib/<year> (scripts/extract-artifacts.sh). Then
# pre-install the Gradle distribution (scripts/install-gradle.sh) and move the C++ parts aside for
# the full image (scripts/split-cpp.sh). The info is captured before eval so that a failure stops
# the chain: eval of a failed command substitution would succeed.
RUN --mount=type=bind,source=scripts,target=/tmp/scripts \
    info="$(bash /tmp/scripts/installer-info.sh "${WPILIB_VERSION}" "${TARGETARCH}")" \
    && eval "$info" \
    && mkdir -p "$HOME/.local/share/wpilib" \
    && curl -fsSL "$url" \
        | tar -xzO --wildcards '*-artifacts.tar.gz' \
        | bash /tmp/scripts/extract-artifacts.sh "$HOME/.local/share/wpilib" "$toolchain" \
    && bash /tmp/scripts/install-gradle.sh "$HOME/.local/share/wpilib" "$HOME/.gradle" \
    && bash /tmp/scripts/split-cpp.sh "$HOME/.local/share/wpilib" "$HOME/.wpilib-cpp"

# Java variant: JDK, VS Code extensions, vendordeps, tools.json, and the pre-installed Gradle.
FROM base AS java

USER vscode
WORKDIR /home/vscode

RUN mkdir -p "$HOME/.local/share"
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

# The cross-compiler is .current/systemcore (2027+) or .current/roborio (2024-2026); only one exists.
ENV PATH=$PATH:/home/vscode/.local/share/wpilib/.current/systemcore/bin:/home/vscode/.local/share/wpilib/.current/roborio/bin

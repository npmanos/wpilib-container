FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

LABEL org.opencontainers.image.source="https://github.com/npmanos/wpilib-container"
LABEL org.opencontainers.image.base.name="mcr.microsoft.com/devcontainers/base:ubuntu-24.04"

ARG WPILIB_VERSION
ARG TARGETARCH

LABEL org.opencontainers.image.version="$WPILIB_VERSION"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Install core dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    gdb \
    wget \
    curl \
    git \
    unzip \
    sudo \
    python3 \
    python3-pip \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

USER vscode
WORKDIR /home/vscode

# Stream the installer bundle, pull out its artifacts tarball, and extract only
# the keep list into ~/.local/share/wpilib/<WpilibYear> (see scripts/extract-artifacts.sh).
RUN --mount=type=bind,source=scripts/extract-artifacts.sh,target=/tmp/extract-artifacts.sh \
    case "${TARGETARCH}" in \
        amd64) ARCH=x64 ;; \
        arm64) ARCH=Arm64 ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && mkdir -p "$HOME/.local/share/wpilib" \
    && curl -fsSL "https://packages.wpilib.workers.dev/installer/v${WPILIB_VERSION}/WPILib_Linux-${ARCH}-${WPILIB_VERSION}.tar.gz" \
        | tar -xzO --wildcards '*-artifacts.tar.gz' \
        | bash /tmp/extract-artifacts.sh "$HOME/.local/share/wpilib"

# Environment Setup
ENV JAVA_HOME=/home/vscode/.local/share/wpilib/.current/jdk
ENV PATH=${JAVA_HOME}/bin:$PATH:/home/vscode/.local/share/wpilib/.current/systemcore/bin

CMD [ "/bin/bash" ]

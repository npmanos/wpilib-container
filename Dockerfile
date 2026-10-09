FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

LABEL org.opencontainers.image.source="https://github.com/npmanos/wpilib-container"
LABEL org.opencontainers.image.base.name="mcr.microsoft.com/devcontainers/base:ubuntu-24.04"

ARG TARGETARCH
ARG WPILIB_YEAR
ARG GCC_VERSION
ARG TOOLCHAIN_VERSION
ARG VSCODE_WPILIB_VERSION
ARG VSCODE_WPILIB_URL=https://github.com/wpilibsuite/vscode-wpilib/releases/download/v${VSCODE_WPILIB_VERSION}/vscode-wpilib-${VSCODE_WPILIB_VERSION}.vsix
ARG JDK_TAG
ARG JDK_TAG_CLEAN

LABEL org.opencontainers.image.version="$VSCODE_WPILIB_VERSION"

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

# Create WPILib directory structure
RUN mkdir -p /home/vscode/wpilib/${WPILIB_YEAR}/tools \
    && mkdir -p /home/vscode/wpilib/${WPILIB_YEAR}/maven \
    && mkdir -p /home/vscode/wpilib/${WPILIB_YEAR}/jdk

# Install WPILib JDK and Toolchain based on architecture
RUN TOOLCHAIN_YEAR=$(echo "${TOOLCHAIN_VERSION}" | grep -oE '[0-9]{4}' | head -n1) \
    && if [ "${TOOLCHAIN_YEAR}" -ge 2027 ] 2>/dev/null; then \
        TOOLCHAIN_TARGET="arm64-systemcore"; \
        TOOLCHAIN_DIR="systemcore"; \
        ARM64_HOST="aarch64-trixie-linux-gnu"; \
    else \
        TOOLCHAIN_TARGET="cortexa9_vfpv3-roborio-academic"; \
        TOOLCHAIN_DIR="roborio"; \
        ARM64_HOST="aarch64-bullseye-linux-gnu"; \
    fi \
    && if [ "$TARGETARCH" = "amd64" ]; then \
        JDK_ARCH="x64"; \
        TOOLCHAIN_ARCH="x86_64-linux-gnu"; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        JDK_ARCH="aarch64"; \
        TOOLCHAIN_ARCH="${ARM64_HOST}"; \
    else \
        echo "Unsupported architecture: $TARGETARCH"; exit 1; \
    fi \
    && echo "Downloading for architecture: $TARGETARCH (Host: ${TOOLCHAIN_ARCH}, Target: ${TOOLCHAIN_TARGET})" \
    # Derive JDK major version dynamically (e.g., 17, 25)
    && JDK_MAJOR=$(echo "${JDK_TAG_CLEAN}" | sed 's/^jdk-//' | cut -d. -f1) \
    && JDK_TAG_SLUG=$(echo "${JDK_TAG}" | sed 's/^jdk-//') \
    && JDK_FILE="OpenJDK${JDK_MAJOR}U-jdk_${JDK_ARCH}_linux_hotspot_${JDK_TAG_CLEAN}.tar.gz" \
    && JDK_URL="https://github.com/adoptium/temurin${JDK_MAJOR}-binaries/releases/download/jdk-${JDK_TAG_SLUG}/${JDK_FILE}" \
    && TOOLCHAIN_FILE="${TOOLCHAIN_TARGET}-${TOOLCHAIN_YEAR}-${TOOLCHAIN_ARCH}-Toolchain-${GCC_VERSION}.tgz" \
    && TOOLCHAIN_URL="https://github.com/wpilibsuite/opensdk/releases/download/${TOOLCHAIN_VERSION}/${TOOLCHAIN_FILE}" \
    # Install JDK
    && wget -nv "${JDK_URL}" -O /tmp/jdk.tar.gz \
    && tar -xzf /tmp/jdk.tar.gz -C /home/vscode/wpilib/${WPILIB_YEAR}/jdk --strip-components=1 \
    && rm /tmp/jdk.tar.gz \
    # Install Toolchain
    && cd /tmp \
    && wget -nv "${TOOLCHAIN_URL}" \
    && mkdir -p "/home/vscode/wpilib/${WPILIB_YEAR}/${TOOLCHAIN_DIR}" \
    && tar -xzf "${TOOLCHAIN_FILE}" -C "/home/vscode/wpilib/${WPILIB_YEAR}/${TOOLCHAIN_DIR}" \
    && rm "${TOOLCHAIN_FILE}" \
    # Symlink roborio <-> systemcore to maintain tooling path compatibility
    && if [ "${TOOLCHAIN_DIR}" = "systemcore" ]; then \
        ln -sfn systemcore "/home/vscode/wpilib/${WPILIB_YEAR}/roborio"; \
    else \
        ln -sfn roborio "/home/vscode/wpilib/${WPILIB_YEAR}/systemcore"; \
    fi

# Install VS Code Extension
RUN wget -q ${VSCODE_WPILIB_URL} -O /home/vscode/wpilib/vscode-wpilib.vsix

# Fix permissions
RUN sudo chown -R vscode:vscode /home/vscode/wpilib

# Environment Setup
ENV JAVA_HOME=/home/vscode/wpilib/${WPILIB_YEAR}/jdk
ENV PATH=${JAVA_HOME}/bin:$PATH:/home/vscode/wpilib/${WPILIB_YEAR}/systemcore/bin:/home/vscode/wpilib/${WPILIB_YEAR}/roborio/bin

CMD [ "/bin/bash" ]

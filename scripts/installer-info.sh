#!/usr/bin/env bash
# Usage: installer-info.sh VERSION TARGETARCH
#   TARGETARCH is amd64 or arm64 (Docker's names).
# Prints url=<installer bundle URL> and toolchain=<cross-compiler directory name inside the
# artifacts tarball>, for eval in the Dockerfile. Both depend on the season:
#   2024-2026: <host>/v<ver>/{Linux|LinuxArm64}/WPILib_{Linux|LinuxArm64}-<ver>.tar.gz, toolchain roborio
#   2027+:     <host>/v<ver>/WPILib_Linux-{x64|Arm64}-<ver>.tar.gz,                      toolchain systemcore
# Earlier seasons were GitHub release assets with a different layout and are not supported.
set -euo pipefail

version="${1:-}"
arch="${2:-}"
host=https://packages.wpilib.workers.dev/installer

if [[ ! "$version" =~ ^([0-9]+)\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  echo "installer-info: unrecognized version '$version'" >&2
  exit 1
fi
major="${BASH_REMATCH[1]}"

if ((major < 2024)); then
  echo "installer-info: WPILib $version is not supported (2024 and later only)" >&2
  exit 1
fi

if ((major >= 2027)); then
  case "$arch" in
    amd64) file="WPILib_Linux-x64-$version.tar.gz" ;;
    arm64) file="WPILib_Linux-Arm64-$version.tar.gz" ;;
    *) echo "installer-info: unsupported architecture '$arch'" >&2; exit 1 ;;
  esac
  echo "url=$host/v$version/$file"
  echo "toolchain=systemcore"
else
  case "$arch" in
    amd64) platform=Linux ;;
    arm64) platform=LinuxArm64 ;;
    *) echo "installer-info: unsupported architecture '$arch'" >&2; exit 1 ;;
  esac
  echo "url=$host/v$version/$platform/WPILib_$platform-$version.tar.gz"
  echo "toolchain=roborio"
fi

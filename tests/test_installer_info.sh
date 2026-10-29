#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/installer-info.sh"

BASE=https://packages.wpilib.workers.dev/installer

# 2027 and later: flat path, x64/Arm64 in the file name, systemcore toolchain
assert_eq $'url='"$BASE"$'/v2027.0.0-alpha-8/WPILib_Linux-x64-2027.0.0-alpha-8.tar.gz\ntoolchain=systemcore' \
  "$(bash "$SCRIPT" 2027.0.0-alpha-8 amd64)" "2027 amd64"
assert_eq $'url='"$BASE"$'/v2027.0.0-alpha-8/WPILib_Linux-Arm64-2027.0.0-alpha-8.tar.gz\ntoolchain=systemcore' \
  "$(bash "$SCRIPT" 2027.0.0-alpha-8 arm64)" "2027 arm64"
assert_eq $'url='"$BASE"$'/v2028.1.1/WPILib_Linux-Arm64-2028.1.1.tar.gz\ntoolchain=systemcore' \
  "$(bash "$SCRIPT" 2028.1.1 arm64)" "later seasons follow the 2027 scheme"

# 2024-2026: per-platform directory, no arch suffix, LinuxArm64 platform name, roborio toolchain
for v in 2024.3.2 2025.3.2 2026.2.1; do
  assert_eq $'url='"$BASE/v$v/Linux/WPILib_Linux-$v"$'.tar.gz\ntoolchain=roborio' \
    "$(bash "$SCRIPT" "$v" amd64)" "$v amd64"
  assert_eq $'url='"$BASE/v$v/LinuxArm64/WPILib_LinuxArm64-$v"$'.tar.gz\ntoolchain=roborio' \
    "$(bash "$SCRIPT" "$v" arm64)" "$v arm64"
done
assert_eq $'url='"$BASE"$'/v2026.1.1-beta-1/Linux/WPILib_Linux-2026.1.1-beta-1.tar.gz\ntoolchain=roborio' \
  "$(bash "$SCRIPT" 2026.1.1-beta-1 amd64)" "prerelease keeps the suffix"

# unsupported
assert_fails "2023 not supported" bash "$SCRIPT" 2023.4.3 amd64
assert_fails "2022 not supported" bash "$SCRIPT" 2022.4.1 arm64
assert_fails "unknown arch" bash "$SCRIPT" 2026.2.1 riscv64
assert_fails "missing arch" bash "$SCRIPT" 2026.2.1
assert_fails "garbage version" bash "$SCRIPT" foo amd64
assert_fails "empty version" bash "$SCRIPT" "" amd64
assert_fails "path traversal in version" bash "$SCRIPT" '2026.2.1/../x' amd64

# the error says why
assert_eq "yes" "$(bash "$SCRIPT" 2023.4.3 amd64 2>&1 >/dev/null | grep -q 'not supported' && echo yes)" "2023 error mentions support"

finish

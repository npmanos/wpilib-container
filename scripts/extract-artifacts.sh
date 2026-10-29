#!/usr/bin/env bash
# Usage: extract-artifacts.sh INSTALL_ROOT [TOOLCHAIN] < WPILib_Linux-<ver>-artifacts.tar.gz
# Extracts the keep list into INSTALL_ROOT/<year> and links INSTALL_ROOT/.current to it.
# TOOLCHAIN is the cross-compiler directory in the tarball: systemcore (default, 2027+) or roborio
# (2024-2026); scripts/installer-info.sh reports it. It must be known up front because the
# stream cannot be read twice and GNU tar fails on a member it does not find.
# <year> is upgradeConfig.json's WpilibYear (2027+) or FrcYear (2024-2026).
set -euo pipefail

root="${1:?usage: extract-artifacts.sh INSTALL_ROOT [TOOLCHAIN]}"
toolchain="${2:-systemcore}"
staging="$root/.staging"

if [[ ! "$toolchain" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "extract-artifacts: refusing toolchain '$toolchain'" >&2
  exit 1
fi

KEEP=(jdk "$toolchain" vsCodeExtensions vendordeps tools/tools.json installUtils)

cleanup_on_failure() { rm -rf "$staging"; }
trap 'cleanup_on_failure' ERR
trap 'cleanup_on_failure' EXIT

rm -rf "$staging"
mkdir -p "$staging"

# GNU tar exits non-zero when a named member is missing from the archive.
tar -xz -C "$staging" "${KEEP[@]}"

year="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("WpilibYear") or d["FrcYear"])' \
  "$staging/installUtils/upgradeConfig.json")"

if [[ ! "$year" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || "$year" == *..* ]]; then
  echo "extract-artifacts: refusing WpilibYear '$year'" >&2
  exit 1
fi

rm -rf "${root:?}/$year"
mv "$staging" "$root/$year"
ln -sfn "$year" "$root/.current"
trap - ERR EXIT

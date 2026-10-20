#!/usr/bin/env bash
# Usage: extract-artifacts.sh INSTALL_ROOT < WPILib_Linux-<ver>-artifacts.tar.gz
# Extracts the keep list into INSTALL_ROOT/<WpilibYear> and links INSTALL_ROOT/.current to it.
set -euo pipefail

root="${1:?usage: extract-artifacts.sh INSTALL_ROOT}"
staging="$root/.staging"

KEEP=(jdk systemcore vsCodeExtensions vendordeps tools/tools.json installUtils)

cleanup_on_failure() { rm -rf "$staging"; }
trap 'cleanup_on_failure' ERR
trap 'cleanup_on_failure' EXIT

rm -rf "$staging"
mkdir -p "$staging"

# GNU tar exits non-zero when a named member is missing from the archive.
tar -xz -C "$staging" "${KEEP[@]}"

year="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["WpilibYear"])' \
  "$staging/installUtils/upgradeConfig.json")"

if [[ ! "$year" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || "$year" == *..* ]]; then
  echo "extract-artifacts: refusing WpilibYear '$year'" >&2
  exit 1
fi

rm -rf "${root:?}/$year"
mv "$staging" "$root/$year"
ln -sfn "$year" "$root/.current"
trap - ERR EXIT

#!/usr/bin/env bash
# Usage: install-gradle.sh INSTALL_ROOT GRADLE_USER_HOME
# Unpacks the Gradle distribution named in INSTALL_ROOT/.current/installUtils/fullConfig.json
# into GRADLE_USER_HOME/permwrapper/dists/<name>/<Hash>/, writes the .ok marker the wrapper
# looks for, and deletes the zip.
set -euo pipefail

if (($# != 2)); then
  echo "usage: install-gradle.sh INSTALL_ROOT GRADLE_USER_HOME" >&2
  exit 2
fi
root="$1"
gradle_home="$2"
utils="$root/.current/installUtils"

read_key() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["Gradle"][sys.argv[2]])' \
    "$utils/fullConfig.json" "$1"
}

zip_name="$(read_key ZipName)" || { echo "install-gradle: cannot read Gradle.ZipName" >&2; exit 1; }
hash="$(read_key Hash)" || { echo "install-gradle: cannot read Gradle.Hash" >&2; exit 1; }

if [[ ! "$zip_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$ || "$zip_name" == *..* ]]; then
  echo "install-gradle: refusing ZipName '$zip_name'" >&2
  exit 1
fi
if [[ ! "$hash" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "install-gradle: refusing Hash '$hash'" >&2
  exit 1
fi
if [[ ! -f "$utils/$zip_name" ]]; then
  echo "install-gradle: $utils/$zip_name not found" >&2
  exit 1
fi

dist="$gradle_home/permwrapper/dists/${zip_name%.zip}"
staging="$dist/.staging-$hash"
trap 'rm -rf "$staging"' EXIT

rm -rf "$staging" "${dist:?}/$hash"
mkdir -p "$staging"
unzip -q "$utils/$zip_name" -d "$staging"
: > "$staging/$zip_name.ok"
mv "$staging" "$dist/$hash"
rm "$utils/$zip_name"

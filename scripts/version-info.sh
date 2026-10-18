#!/usr/bin/env bash
# Usage: version-info.sh VERSION
# Prints stable=true|false and major=<digits>, for appending to $GITHUB_OUTPUT.
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^([0-9]+)\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  echo "version-info: unrecognized version '$version'" >&2
  exit 1
fi

if [[ -n "${BASH_REMATCH[2]}" ]]; then stable=false; else stable=true; fi
echo "stable=$stable"
echo "major=${BASH_REMATCH[1]}"

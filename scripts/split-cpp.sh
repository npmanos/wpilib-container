#!/usr/bin/env bash
# Usage: split-cpp.sh INSTALL_ROOT OUT_ROOT
# Moves the C++ parts of the install (the cross-compiler directory named by CppToolchain.Directory
# in installUtils/fullConfig.json, systemcore if absent, and the ms-vscode.cpptools .vsix named in
# installUtils/vscodeConfig.json) to OUT_ROOT/<year>/. Checks both exist before moving either.
set -euo pipefail

if (($# != 2)); then
  echo "usage: split-cpp.sh INSTALL_ROOT OUT_ROOT" >&2
  exit 2
fi
root="$1"
out="$2"

year="$(readlink "$root/.current")" || { echo "split-cpp: $root/.current is not a symlink" >&2; exit 1; }
if [[ ! "$year" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || "$year" == *..* ]]; then
  echo "split-cpp: refusing year '$year'" >&2
  exit 1
fi
src="$root/$year"
if [[ ! -d "$src" ]]; then
  echo "split-cpp: $src not found" >&2
  exit 1
fi

toolchain="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1])).get("CppToolchain", {}).get("Directory", "systemcore"))
' "$src/installUtils/fullConfig.json")" || { echo "split-cpp: cannot read installUtils/fullConfig.json" >&2; exit 1; }
if [[ ! "$toolchain" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "split-cpp: refusing toolchain '$toolchain'" >&2
  exit 1
fi

vsix="$(python3 -c '
import json, sys
for e in json.load(open(sys.argv[1]))["thirdPartyExtensions"]:
    if e["name"] == "ms-vscode.cpptools":
        print(e["vsix"]); break
else:
    sys.exit(1)
' "$src/installUtils/vscodeConfig.json")" || { echo "split-cpp: no ms-vscode.cpptools entry in vscodeConfig.json" >&2; exit 1; }

# '@' appears in the 2024 and 2025 names (ms-vscode.cpptools-1.23.2@linux-arm64.vsix)
if [[ ! "$vsix" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*\.vsix$ || "$vsix" == *..* ]]; then
  echo "split-cpp: refusing vsix name '$vsix'" >&2
  exit 1
fi
for p in "$src/$toolchain" "$src/vsCodeExtensions/$vsix"; do
  if [[ ! -e "$p" ]]; then
    echo "split-cpp: $p not found" >&2
    exit 1
  fi
done

mkdir -p "$out/$year/vsCodeExtensions"
mv "$src/$toolchain" "$out/$year/$toolchain"
mv "$src/vsCodeExtensions/$vsix" "$out/$year/vsCodeExtensions/$vsix"

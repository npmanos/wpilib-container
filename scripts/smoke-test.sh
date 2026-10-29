#!/usr/bin/env bash
# Usage: smoke-test.sh VARIANT [INSTALL_ROOT]
#   VARIANT is java or full; INSTALL_ROOT defaults to $HOME/.local/share/wpilib.
# Verifies an installed WPILib tree. Names the failing check on stderr.
# Uses only: bash sh python3 unzip mktemp rm realpath readlink dirname basename head cat ls
# (tests/lib.sh minimal_path provides exactly these).
set -u

variant="${1:-}"
case "$variant" in
  java|full) ;;
  *) echo "usage: smoke-test.sh java|full [INSTALL_ROOT]" >&2; exit 2 ;;
esac
root="${2:-$HOME/.local/share/wpilib}"
gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
cur="$root/.current"
failed=0

fail() { echo "smoke-test FAIL: $1" >&2; failed=1; }

check_current() {
  [[ -d "$cur" ]] || fail ".current does not resolve to a directory ($cur)"
}

check_java_home() {
  if [[ -z "${JAVA_HOME:-}" ]]; then fail "JAVA_HOME is not set"; return; fi
  local want got
  want="$(realpath "$cur/jdk" 2>/dev/null)" || { fail "cannot resolve $cur/jdk"; return; }
  got="$(realpath "$JAVA_HOME" 2>/dev/null)" || { fail "cannot resolve JAVA_HOME=$JAVA_HOME"; return; }
  [[ "$got" == "$want" ]] || fail "JAVA_HOME ($got) is not .current/jdk ($want)"
}

check_java() {
  java -version >/dev/null 2>&1 || fail "java -version failed"
}

# The cross-compiler directory is fullConfig.json's CppToolchain.Directory: roborio for 2024-2026,
# systemcore for 2027 and later (and the default when the key is absent).
toolchain=""
resolve_toolchain() {
  [[ -n "$toolchain" ]] && return 0
  toolchain="$(json_get "$cur/installUtils/fullConfig.json" 'd.get("CppToolchain", {}).get("Directory", "systemcore")')" \
    || { fail "cannot read installUtils/fullConfig.json"; return 1; }
  if [[ ! "$toolchain" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    fail "refusing toolchain directory '$toolchain'"; toolchain=""; return 1
  fi
}

check_compiler() {
  local gxx
  resolve_toolchain || return
  gxx="$(compgen -G "$cur/$toolchain/bin/*g++" | head -n1)"
  if [[ -z "$gxx" ]]; then fail "no *g++ in .current/$toolchain/bin"; return; fi
  "$gxx" --version >/dev/null 2>&1 || fail "$gxx --version failed"
}

check_vsix() {
  compgen -G "$cur/vsCodeExtensions/vscode-wpilib-*.vsix" >/dev/null \
    || fail "no vscode-wpilib-*.vsix in .current/vsCodeExtensions"
}

check_tools_json() {
  [[ -f "$cur/tools/tools.json" ]] || fail ".current/tools/tools.json missing"
}

check_no_maven() {
  [[ ! -e "$cur/maven" ]] || fail ".current/maven must not exist"
}

check_removed() {
  local d
  for d in documentation wpilibcode; do
    [[ ! -e "$cur/$d" ]] || fail ".current/$d must not exist"
  done
  compgen -G "$cur/installUtils/*.zip" >/dev/null && fail "zip left in .current/installUtils"
  return 0
}

# json_get FILE PYTHON_EXPR_ON_d: print a value from a JSON file
json_get() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

check_gradle_layout() {
  local zip hash dir
  zip="$(json_get "$cur/installUtils/fullConfig.json" 'd["Gradle"]["ZipName"]')" \
    && hash="$(json_get "$cur/installUtils/fullConfig.json" 'd["Gradle"]["Hash"]')" \
    || { fail "cannot read Gradle entry from fullConfig.json"; return; }
  dir="$gradle_home/permwrapper/dists/${zip%.zip}/$hash"
  [[ -d "$dir" ]] || { fail "Gradle distribution dir missing ($dir)"; return; }
  [[ -f "$dir/$zip.ok" ]] || fail "Gradle .ok marker missing ($dir/$zip.ok)"
  compgen -G "$dir/*/" >/dev/null || fail "unpacked Gradle distribution missing in $dir"
}

# COPY in the Dockerfile must not leave the parents of the install root owned by root.
check_local_share_writable() {
  [[ -w "$HOME/.local/share" ]] || fail "$HOME/.local/share is not writable"
}

# Runs the wrapper script shipped in the WPILib extension. It must resolve Gradle from the
# pre-installed distribution: the smoke test runs with no network.
check_gradle_wrapper() {
  local vsix tmp
  vsix="$(compgen -G "$cur/vsCodeExtensions/vscode-wpilib-*.vsix" | head -n1)"
  [[ -n "$vsix" ]] || return 0  # check_vsix already failed
  tmp="$(mktemp -d)"
  if unzip -q "$vsix" 'extension/resources/gradle/shared/*' -d "$tmp" 2>/dev/null; then
    (cd "$tmp/extension/resources/gradle/shared" && sh ./gradlew --version >/dev/null 2>&1) \
      || fail "gradlew --version failed (offline wrapper)"
  else
    fail "cannot unpack gradle wrapper from $vsix"
  fi
  rm -rf "$tmp"
}

check_cpptools_vsix() {
  local want="$1" name
  name="$(json_get "$cur/installUtils/vscodeConfig.json" \
    '[e["vsix"] for e in d["thirdPartyExtensions"] if e["name"]=="ms-vscode.cpptools"][0]')" \
    || { fail "no ms-vscode.cpptools entry in vscodeConfig.json"; return; }
  if [[ "$want" == present ]]; then
    [[ -f "$cur/vsCodeExtensions/$name" ]] || fail "$name missing from .current/vsCodeExtensions"
  else
    [[ ! -e "$cur/vsCodeExtensions/$name" ]] || fail "$name must not exist in the java variant"
  fi
}

check_no_toolchain() {
  resolve_toolchain || return
  [[ ! -e "$cur/$toolchain" ]] || fail ".current/$toolchain must not exist in the java variant"
}

check_no_native_tools() {
  local t
  for t in cmake gdb; do
    if command -v "$t" >/dev/null 2>&1; then fail "$t must not be installed in the java variant"; fi
  done
}

check_current
check_java_home
check_java
check_vsix
check_tools_json
check_no_maven
check_removed
check_gradle_layout
check_gradle_wrapper
check_local_share_writable
if [[ "$variant" == full ]]; then
  check_compiler
  check_cpptools_vsix present
else
  check_no_toolchain
  check_cpptools_vsix absent
  check_no_native_tools
fi

if ((failed)); then exit 1; fi
echo "smoke-test: all checks passed"

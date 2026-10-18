#!/usr/bin/env bash
# Usage: smoke-test.sh [INSTALL_ROOT]   (default $HOME/.local/share/wpilib)
# Verifies an installed WPILib tree. Names the failing check on stderr.
set -u

root="${1:-$HOME/.local/share/wpilib}"
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

check_compiler() {
  local gxx
  gxx="$(compgen -G "$cur/systemcore/bin/*g++" | head -n1)"
  if [[ -z "$gxx" ]]; then fail "no *g++ in .current/systemcore/bin"; return; fi
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

check_current
check_java_home
check_java
check_compiler
check_vsix
check_tools_json
check_no_maven

if ((failed)); then exit 1; fi
echo "smoke-test: all checks passed"

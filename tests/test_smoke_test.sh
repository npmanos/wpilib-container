#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/smoke-test.sh"

make_tree() {
  local root="$1" y="$1/2027_alpha7"
  mkdir -p "$y/jdk/bin" "$y/systemcore/bin" "$y/vsCodeExtensions" "$y/tools"
  printf '#!/bin/sh\necho "openjdk version 25" >&2\n' > "$y/jdk/bin/java"
  printf '#!/bin/sh\nexit 0\n' > "$y/systemcore/bin/arm64-g++"
  chmod +x "$y/jdk/bin/java" "$y/systemcore/bin/arm64-g++"
  : > "$y/vsCodeExtensions/vscode-wpilib-2027.0.0-alpha-7.vsix"
  echo '[]' > "$y/tools/tools.json"
  ln -sfn 2027_alpha7 "$root/.current"
}

# run_smoke ROOT [JAVA_HOME]
run_smoke() {
  local root="$1" jh="${2:-$1/.current/jdk}"
  JAVA_HOME="$jh" PATH="$jh/bin:$PATH" bash "$SCRIPT" "$root"
}

fresh() { R="$(mktemp -d -p "$TMP")"; make_tree "$R"; }

fresh; assert_ok "good tree passes" run_smoke "$R"
fresh; rm "$R/.current/vsCodeExtensions/"*.vsix; assert_fails "missing vsix" run_smoke "$R"
fresh; mkdir "$R/.current/maven"; assert_fails "maven present" run_smoke "$R"
fresh; rm "$R/.current/tools/tools.json"; assert_fails "missing tools.json" run_smoke "$R"
fresh; ln -sfn nonexistent "$R/.current"; assert_fails "dangling .current" run_smoke "$R"
fresh; mkdir -p "$TMP/otherjdk/bin"; cp "$R/.current/jdk/bin/java" "$TMP/otherjdk/bin/java"
assert_fails "JAVA_HOME elsewhere" run_smoke "$R" "$TMP/otherjdk"
fresh; printf '#!/bin/sh\nexit 1\n' > "$R/.current/systemcore/bin/arm64-g++"; assert_fails "compiler exits 1" run_smoke "$R"

finish

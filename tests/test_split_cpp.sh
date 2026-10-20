#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/split-cpp.sh"

# make_install ROOT [VSIX]
make_install() {
  local root="$1" vsix="${2:-cpptools-linux-arm64.vsix}" y="$1/2027_alpha7"
  mkdir -p "$y/systemcore/bin" "$y/vsCodeExtensions" "$y/installUtils"
  echo stub > "$y/systemcore/bin/arm64-g++"
  local f; for f in vscode-wpilib-2027.0.0-alpha-7.vsix vscode-java-1.55.0-995.vsix cpptools-linux-arm64.vsix; do
    echo stub > "$y/vsCodeExtensions/$f"
  done
  ln -s 2027_alpha7 "$root/.current"
  printf '{"thirdPartyExtensions": [{"name": "redhat.java", "vsix": "vscode-java-1.55.0-995.vsix"}, {"name": "ms-vscode.cpptools", "vsix": "%s"}]}\n' \
    "$vsix" > "$y/installUtils/vscodeConfig.json"
}

run() { bash "$SCRIPT" "$1" "$2"; }

# untouched ROOT OUT: everything still in place, nothing moved out
assert_untouched() {
  local label="$1" root="$2" out="$3" y="$2/2027_alpha7"
  assert_ok "$label: systemcore stays" test -f "$y/systemcore/bin/arm64-g++"
  assert_ok "$label: wpilib vsix stays" test -f "$y/vsCodeExtensions/vscode-wpilib-2027.0.0-alpha-7.vsix"
  assert_ok "$label: java vsix stays" test -f "$y/vsCodeExtensions/vscode-java-1.55.0-995.vsix"
  assert_fails "$label: nothing in out" test -e "$out/2027_alpha7"
}

# good
R="$TMP/r1"; O="$TMP/o1"; mkdir -p "$R"; make_install "$R"
assert_ok "good split" run "$R" "$O"
assert_ok "systemcore moved" test -f "$O/2027_alpha7/systemcore/bin/arm64-g++"
assert_ok "cpptools vsix moved" test -f "$O/2027_alpha7/vsCodeExtensions/cpptools-linux-arm64.vsix"
assert_fails "systemcore gone from install" test -e "$R/2027_alpha7/systemcore"
assert_fails "cpptools gone from install" test -e "$R/2027_alpha7/vsCodeExtensions/cpptools-linux-arm64.vsix"
assert_ok "wpilib vsix stays" test -f "$R/2027_alpha7/vsCodeExtensions/vscode-wpilib-2027.0.0-alpha-7.vsix"
assert_ok "java vsix stays" test -f "$R/2027_alpha7/vsCodeExtensions/vscode-java-1.55.0-995.vsix"

# amd64 name comes from the config, not a hard-coded name
R="$TMP/r1b"; O="$TMP/o1b"; mkdir -p "$R"; make_install "$R" cpptools-linux-x64.vsix
echo stub > "$R/2027_alpha7/vsCodeExtensions/cpptools-linux-x64.vsix"
assert_ok "x64 split" run "$R" "$O"
assert_ok "x64 vsix moved" test -f "$O/2027_alpha7/vsCodeExtensions/cpptools-linux-x64.vsix"

# no cpptools entry
R="$TMP/r2"; O="$TMP/o2"; mkdir -p "$R"; make_install "$R"
echo '{"thirdPartyExtensions": []}' > "$R/2027_alpha7/installUtils/vscodeConfig.json"
assert_fails "no cpptools entry" run "$R" "$O"
assert_untouched "no entry" "$R" "$O"
assert_ok "no entry: cpptools stays" test -f "$R/2027_alpha7/vsCodeExtensions/cpptools-linux-arm64.vsix"

# cpptools vsix missing
R="$TMP/r3"; O="$TMP/o3"; mkdir -p "$R"; make_install "$R"
rm "$R/2027_alpha7/vsCodeExtensions/cpptools-linux-arm64.vsix"
assert_fails "cpptools vsix missing" run "$R" "$O"
assert_untouched "vsix missing" "$R" "$O"

# systemcore missing
R="$TMP/r4"; O="$TMP/o4"; mkdir -p "$R"; make_install "$R"
rm -r "$R/2027_alpha7/systemcore"
assert_fails "systemcore missing" run "$R" "$O"
assert_ok "systemcore missing: cpptools stays" test -f "$R/2027_alpha7/vsCodeExtensions/cpptools-linux-arm64.vsix"
assert_fails "systemcore missing: nothing in out" test -e "$O/2027_alpha7"

# vsix name with ..
R="$TMP/r5"; O="$TMP/o5"; mkdir -p "$R"; make_install "$R" ../evil.vsix
assert_fails "vsix name with .." run "$R" "$O"
assert_untouched "bad vsix name" "$R" "$O"

# dangling .current
R="$TMP/r6"; mkdir -p "$R"; ln -s nowhere "$R/.current"
assert_fails "dangling .current" run "$R" "$TMP/o6"

# arg count
assert_fails "wrong arg count" bash "$SCRIPT" "$TMP/r1"

finish

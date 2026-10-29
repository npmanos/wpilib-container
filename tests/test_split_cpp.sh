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
  # no CppToolchain key: the toolchain falls back to systemcore
  printf '{"Gradle": {"ZipName": "gradle-9.0-bin.zip", "Hash": "abc123"}}\n' > "$y/installUtils/fullConfig.json"
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

# fullConfig.json missing
R="$TMP/r9"; O="$TMP/o9"; mkdir -p "$R"; make_install "$R"
rm "$R/2027_alpha7/installUtils/fullConfig.json"
assert_fails "fullConfig.json missing" run "$R" "$O"
assert_untouched "fullConfig.json missing" "$R" "$O"

# 2024-2026: roborio toolchain named by fullConfig.json, FrcYear-style year dir, '@' in the vsix name
make_legacy() {
  local root="$1" tc="$2" vsix="$3" y="$1/2025"
  mkdir -p "$y/$tc/bin" "$y/vsCodeExtensions" "$y/installUtils"
  echo stub > "$y/$tc/bin/arm-nilrt-linux-gnueabi-g++"
  local f; for f in vscode-wpilib-2025.3.2.vsix redhat.java-1.38.0.vsix "$vsix"; do
    echo stub > "$y/vsCodeExtensions/$f"
  done
  ln -s 2025 "$root/.current"
  printf '{"thirdPartyExtensions": [{"name": "redhat.java", "vsix": "redhat.java-1.38.0.vsix"}, {"name": "ms-vscode.cpptools", "vsix": "%s"}]}\n' \
    "$vsix" > "$y/installUtils/vscodeConfig.json"
  printf '{"Gradle": {"ZipName": "gradle-8.11-bin.zip", "Hash": "c4te04g51qsyw1bxcb929u7br"}, "CppToolchain": {"Version": "12.1.0", "Directory": "%s"}}\n' \
    "$tc" > "$y/installUtils/fullConfig.json"
}

AT=ms-vscode.cpptools-1.23.2@linux-arm64.vsix
R="$TMP/r10"; O="$TMP/o10"; mkdir -p "$R"; make_legacy "$R" roborio "$AT"
assert_ok "roborio + '@' vsix splits" run "$R" "$O"
assert_ok "roborio moved" test -f "$O/2025/roborio/bin/arm-nilrt-linux-gnueabi-g++"
assert_ok "'@' vsix moved" test -f "$O/2025/vsCodeExtensions/$AT"
assert_fails "roborio gone from install" test -e "$R/2025/roborio"
assert_ok "wpilib vsix stays (legacy)" test -f "$R/2025/vsCodeExtensions/vscode-wpilib-2025.3.2.vsix"
assert_ok "java vsix stays (legacy)" test -f "$R/2025/vsCodeExtensions/redhat.java-1.38.0.vsix"

# fullConfig names roborio but the directory is absent
R="$TMP/r11"; O="$TMP/o11"; mkdir -p "$R"; make_legacy "$R" roborio "$AT"
rm -r "$R/2025/roborio"
assert_fails "roborio missing" run "$R" "$O"
assert_ok "roborio missing: cpptools stays" test -f "$R/2025/vsCodeExtensions/$AT"
assert_fails "roborio missing: nothing in out" test -e "$O/2025"

# a toolchain name that is not a plain directory name
for t in ../evil .hidden 'a/b'; do
  R="$TMP/r12"; O="$TMP/o12"; rm -rf "$R" "$O"; mkdir -p "$R"; make_legacy "$R" systemcore "$AT"
  printf '{"CppToolchain": {"Directory": "%s"}}\n' "$t" > "$R/2025/installUtils/fullConfig.json"
  assert_fails "toolchain '$t' refused" run "$R" "$O"
  assert_ok "toolchain '$t': cpptools stays" test -f "$R/2025/vsCodeExtensions/$AT"
done

# other characters in a vsix name are still refused
for v in 'x y.vsix' '../x.vsix' '@x.vsix' 'a;b.vsix'; do
  R="$TMP/r13"; O="$TMP/o13"; rm -rf "$R" "$O"; mkdir -p "$R"; make_legacy "$R" roborio "$AT"
  printf '{"thirdPartyExtensions": [{"name": "ms-vscode.cpptools", "vsix": "%s"}]}\n' "$v" > "$R/2025/installUtils/vscodeConfig.json"
  assert_fails "vsix name '$v' refused" run "$R" "$O"
done

finish

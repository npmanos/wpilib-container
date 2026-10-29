#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/smoke-test.sh"
MINPATH="$(minimal_path "$TMP/minpath")"

# make_tree VARIANT [GRADLEW_EXIT]: sets H (fixture dir), R (install root), GH (Gradle user home).
# The cross-compiler directory is systemcore with no CppToolchain key in fullConfig.json (2027);
# TOOLCHAIN=roborio names it in fullConfig.json as the 2024-2026 bundles do.
make_tree() {
  local variant="$1" gradlew_exit="${2:-0}" tc="${TOOLCHAIN:-systemcore}"
  H="$(mktemp -d -p "$TMP")"; R="$H/wpilib"; GH="$H/gradle"
  local y="$R/2027_alpha7" d="$GH/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj"
  mkdir -p "$y/jdk/bin" "$y/vsCodeExtensions" "$y/tools" "$y/installUtils" "$d/gradle-9.4.1"
  printf '#!/bin/sh\necho "openjdk version 25" >&2\n' > "$y/jdk/bin/java"
  chmod +x "$y/jdk/bin/java"
  echo '[]' > "$y/tools/tools.json"
  if [[ -n "${TOOLCHAIN:-}" ]]; then
    printf '{"Gradle": {"Hash": "arn2x92ynaizyzdaamcbpbhtj", "ZipName": "gradle-9.4.1-bin.zip"}, "CppToolchain": {"Version": "12.1.0", "Directory": "%s"}}\n' "$tc" > "$y/installUtils/fullConfig.json"
  else
    printf '{"Gradle": {"Hash": "arn2x92ynaizyzdaamcbpbhtj", "ZipName": "gradle-9.4.1-bin.zip"}}\n' > "$y/installUtils/fullConfig.json"
  fi
  printf '{"thirdPartyExtensions": [{"name": "ms-vscode.cpptools", "vsix": "cpptools-linux-x64.vsix"}]}\n' > "$y/installUtils/vscodeConfig.json"
  : > "$d/gradle-9.4.1-bin.zip.ok"
  python3 - "$y/vsCodeExtensions/vscode-wpilib-2027.0.0-alpha-7.vsix" "$gradlew_exit" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("extension/resources/gradle/shared/gradlew", "#!/bin/sh\nexit %s\n" % sys.argv[2])
PY
  mkdir -p "$H/.local/share"
  ln -sfn 2027_alpha7 "$R/.current"
  if [[ "$variant" == full ]]; then
    mkdir -p "$y/$tc/bin"
    printf '#!/bin/sh\nexit 0\n' > "$y/$tc/bin/arm64-g++"
    chmod +x "$y/$tc/bin/arm64-g++"
    : > "$y/vsCodeExtensions/cpptools-linux-x64.vsix"
  fi
}

# run_smoke VARIANT ROOT [JAVA_HOME]; EXTRA_PATH (optional global) is prepended to PATH
run_smoke() {
  local variant="$1" root="$2" jh="${3:-$2/.current/jdk}"
  HOME="$H" GRADLE_USER_HOME="$GH" JAVA_HOME="$jh" PATH="${EXTRA_PATH:+$EXTRA_PATH:}$jh/bin:$MINPATH" \
    bash "$SCRIPT" "$variant" "$root"
}

# fake_tool NAME: a dir holding an executable NAME that exits 0
fake_tool() {
  local d="$TMP/fake-$1"; mkdir -p "$d"
  printf '#!/bin/sh\nexit 0\n' > "$d/$1"; chmod +x "$d/$1"
  echo "$d"
}

make_tree full; assert_ok "full: good tree passes" run_smoke full "$R"
make_tree java; assert_ok "java: good tree passes" run_smoke java "$R"
make_tree java; assert_fails "no variant" env PATH="$MINPATH" bash "$SCRIPT"
make_tree java; assert_fails "unknown variant" run_smoke cpp "$R"
make_tree java; assert_eq 2 "$(run_smoke cpp "$R" >/dev/null 2>&1; echo $?)" "unknown variant exits 2"

for v in java full; do
  make_tree $v; rm "$R/.current/vsCodeExtensions/vscode-wpilib-"*.vsix; assert_fails "$v: missing vsix" run_smoke $v "$R"
  make_tree $v; mkdir "$R/.current/maven"; assert_fails "$v: maven present" run_smoke $v "$R"
  make_tree $v; rm "$R/.current/tools/tools.json"; assert_fails "$v: missing tools.json" run_smoke $v "$R"
  make_tree $v; ln -sfn nonexistent "$R/.current"; assert_fails "$v: dangling .current" run_smoke $v "$R"
  make_tree $v; mkdir -p "$TMP/otherjdk/bin"; cp "$R/.current/jdk/bin/java" "$TMP/otherjdk/bin/java"
  assert_fails "$v: JAVA_HOME elsewhere" run_smoke $v "$R" "$TMP/otherjdk"
  make_tree $v; mkdir "$R/.current/documentation"; assert_fails "$v: documentation present" run_smoke $v "$R"
  make_tree $v; mkdir "$R/.current/wpilibcode"; assert_fails "$v: wpilibcode present" run_smoke $v "$R"
  make_tree $v; : > "$R/.current/installUtils/gradle-9.4.1-bin.zip"; assert_fails "$v: zip left in installUtils" run_smoke $v "$R"
  make_tree $v; rm "$GH/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/gradle-9.4.1-bin.zip.ok"
  assert_fails "$v: .ok marker missing" run_smoke $v "$R"
  make_tree $v; rm -r "$GH/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj"
  assert_fails "$v: unpacked dist dir missing" run_smoke $v "$R"
  make_tree $v 1; assert_fails "$v: gradlew exits 1" run_smoke $v "$R"
  make_tree $v; rm -r "$GH/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj/gradle-9.4.1"
  assert_fails "$v: unpacked gradle dir missing (marker present)" run_smoke $v "$R"
  make_tree $v; mkdir -p "$H/.local/share"; chmod a-w "$H/.local/share"
  assert_fails "$v: ~/.local/share not writable" run_smoke $v "$R"
  chmod u+w "$H/.local/share"
done

make_tree full; printf '#!/bin/sh\nexit 1\n' > "$R/.current/systemcore/bin/arm64-g++"; assert_fails "full: compiler exits 1" run_smoke full "$R"
make_tree full; rm "$R/.current/vsCodeExtensions/cpptools-linux-x64.vsix"; assert_fails "full: cpptools vsix missing" run_smoke full "$R"

make_tree java; mkdir -p "$R/.current/systemcore"; assert_fails "java: systemcore present" run_smoke java "$R"
make_tree java; : > "$R/.current/vsCodeExtensions/cpptools-linux-x64.vsix"; assert_fails "java: cpptools vsix present" run_smoke java "$R"
for t in cmake gdb; do
  make_tree java; EXTRA_PATH="$(fake_tool $t)"
  assert_fails "java: $t on PATH" run_smoke java "$R"
  EXTRA_PATH=""
done

# 2024-2026: the toolchain is roborio, named by fullConfig.json
TOOLCHAIN=roborio make_tree full; assert_ok "roborio full: good tree passes" run_smoke full "$R"
TOOLCHAIN=roborio make_tree java; assert_ok "roborio java: good tree passes" run_smoke java "$R"
TOOLCHAIN=roborio make_tree full; rm -r "$R/.current/roborio"; assert_fails "roborio full: toolchain missing" run_smoke full "$R"
TOOLCHAIN=roborio make_tree full; printf '#!/bin/sh\nexit 1\n' > "$R/.current/roborio/bin/arm64-g++"
assert_fails "roborio full: compiler exits 1" run_smoke full "$R"
TOOLCHAIN=roborio make_tree java; mkdir -p "$R/.current/roborio"; assert_fails "roborio java: roborio present" run_smoke java "$R"
# a systemcore directory is not the toolchain when fullConfig.json says roborio
TOOLCHAIN=roborio make_tree full; mv "$R/.current/roborio" "$R/.current/systemcore"
assert_fails "roborio full: only systemcore present" run_smoke full "$R"
# a toolchain name that is not a plain directory name
for t in ../evil .hidden 'a/b'; do
  TOOLCHAIN=roborio make_tree full
  printf '{"Gradle": {"Hash": "arn2x92ynaizyzdaamcbpbhtj", "ZipName": "gradle-9.4.1-bin.zip"}, "CppToolchain": {"Directory": "%s"}}\n' "$t" > "$R/.current/installUtils/fullConfig.json"
  assert_fails "toolchain '$t' refused" run_smoke full "$R"
done

# The devcontainer base image ships g++ (build-essential), so it is not a java-variant failure.
make_tree java; EXTRA_PATH="$(fake_tool g++)"
assert_ok "java: g++ on PATH is allowed" run_smoke java "$R"
EXTRA_PATH=""

finish

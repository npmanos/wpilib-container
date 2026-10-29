#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/extract-artifacts.sh"

KEEP=(jdk/x systemcore/x vsCodeExtensions/x vendordeps/x tools/tools.json)

# make_artifacts OUT YEAR [OMIT_PATH...]
# YEAR is the upgradeConfig.json value; the key is WpilibYear unless YEAR_KEY is set (2024-2026
# bundles use FrcYear) and the toolchain directory is systemcore unless TOOLCHAIN is set (roborio
# before 2027).
make_artifacts() {
  local out="$1" year="$2"; shift 2
  local dir; dir="$(mktemp -d -p "$TMP")"
  local p tc="${TOOLCHAIN:-systemcore}"
  for p in "${KEEP[@]/systemcore/$tc}" maven/x wpilibcode/x documentation/x advantagescope/x elastic/x icons/x tools/artifacts/Glass.zip; do
    mkdir -p "$dir/$(dirname "$p")"; echo data > "$dir/$p"
  done
  mkdir -p "$dir/installUtils"
  printf '{"%s": "%s"}\n' "${YEAR_KEY:-WpilibYear}" "$year" > "$dir/installUtils/upgradeConfig.json"
  local o; for o in "$@"; do rm -f "$dir/$o"; done
  # members must not carry ./ (real tarball has none)
  tar -czf "$out" -C "$dir" $(cd "$dir" && find . -type f | sed 's|^\./||')
}

run() { bash "$SCRIPT" "$1" ${3:+"$3"} < "$2"; }

# good fixture
make_artifacts "$TMP/good.tgz" 2027_alpha7
R="$TMP/r1"; mkdir -p "$R"
assert_ok "good fixture extracts" run "$R" "$TMP/good.tgz"
assert_eq 2027_alpha7 "$(readlink "$R/.current")" ".current target"
Y="$R/2027_alpha7"
assert_ok "tools.json kept" test -f "$Y/tools/tools.json"
assert_ok "jdk kept" test -f "$Y/jdk/x"
assert_ok "upgradeConfig kept" test -f "$Y/installUtils/upgradeConfig.json"
assert_fails "maven dropped" test -e "$Y/maven"
assert_fails "wpilibcode dropped" test -e "$Y/wpilibcode"
assert_fails "documentation dropped" test -e "$Y/documentation"
assert_fails "advantagescope dropped" test -e "$Y/advantagescope"
assert_fails "tools/artifacts dropped" test -e "$Y/tools/artifacts"
assert_fails ".staging gone" test -e "$R/.staging"

# missing tools.json
make_artifacts "$TMP/notools.tgz" 2027_alpha7 tools/tools.json
R="$TMP/r2"; mkdir -p "$R"
assert_fails "missing tools.json fails" run "$R" "$TMP/notools.tgz"
assert_fails "no .current after missing member" test -e "$R/.current"
assert_fails "no .staging after missing member" test -e "$R/.staging"

# missing upgradeConfig
make_artifacts "$TMP/nocfg.tgz" 2027_alpha7 installUtils/upgradeConfig.json
R="$TMP/r3"; mkdir -p "$R"
assert_fails "missing upgradeConfig fails" run "$R" "$TMP/nocfg.tgz"
assert_eq "" "$(ls -A "$R")" "no year dir after missing config"

# truncated
head -c 200 "$TMP/good.tgz" > "$TMP/trunc.tgz"
R="$TMP/r4"; mkdir -p "$R"
assert_fails "truncated stream fails" run "$R" "$TMP/trunc.tgz"
assert_eq "" "$(ls -A "$R")" "no year dir or .staging after truncation"

# bad years
for y in ../evil .hidden; do
  make_artifacts "$TMP/bad.tgz" "$y"
  R="$TMP/r5"; rm -rf "$R"; mkdir -p "$R"
  assert_fails "year '$y' rejected" run "$R" "$TMP/bad.tgz"
  assert_fails "no evil dir for '$y'" test -e "$TMP/evil"
  assert_eq "" "$(ls -A "$R")" "nothing left behind for '$y'"
done

# 2024-2026 bundles: FrcYear key, roborio toolchain passed by the caller
YEAR_KEY=FrcYear TOOLCHAIN=roborio make_artifacts "$TMP/legacy.tgz" 2026
R="$TMP/r6"; mkdir -p "$R"
assert_ok "FrcYear + roborio extracts" run "$R" "$TMP/legacy.tgz" roborio
assert_eq 2026 "$(readlink "$R/.current")" "FrcYear names the year dir"
assert_ok "roborio kept" test -f "$R/2026/roborio/x"
assert_fails "systemcore absent" test -e "$R/2026/systemcore"
assert_ok "jdk kept (legacy)" test -f "$R/2026/jdk/x"
assert_fails "legacy: maven dropped" test -e "$R/2026/maven"

# asking for the wrong toolchain fails and leaves nothing behind
R="$TMP/r7"; mkdir -p "$R"
assert_fails "roborio bundle, default systemcore" run "$R" "$TMP/legacy.tgz"
assert_eq "" "$(ls -A "$R")" "nothing left behind after toolchain mismatch"
R="$TMP/r8"; mkdir -p "$R"
assert_fails "systemcore bundle, roborio requested" run "$R" "$TMP/good.tgz" roborio
assert_eq "" "$(ls -A "$R")" "nothing left behind after reverse mismatch"

# neither year key
YEAR_KEY=Bogus make_artifacts "$TMP/nokey.tgz" 2026
R="$TMP/r9"; mkdir -p "$R"
assert_fails "no year key fails" run "$R" "$TMP/nokey.tgz"
assert_eq "" "$(ls -A "$R")" "nothing left behind without a year key"

# bad toolchain names are refused before extracting
for t in ../evil .hidden 'a b' tools/tools.json; do
  R="$TMP/r10"; rm -rf "$R"; mkdir -p "$R"
  assert_fails "toolchain '$t' rejected" run "$R" "$TMP/good.tgz" "$t"
  assert_eq "" "$(ls -A "$R")" "nothing left behind for toolchain '$t'"
done

finish

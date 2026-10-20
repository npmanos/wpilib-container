#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/install-gradle.sh"

# make_install ROOT [ZIPNAME] [HASH]
make_install() {
  local root="$1" zip="${2:-gradle-9.4.1-bin.zip}" hash="${3:-arn2x92ynaizyzdaamcbpbhtj}"
  mkdir -p "$root/2027_alpha7/installUtils"
  ln -s 2027_alpha7 "$root/.current"
  printf '{"Gradle": {"Hash": "%s", "ZipName": "%s", "ExtractLocations": ["permwrapper/dists"]}}\n' \
    "$hash" "$zip" > "$root/2027_alpha7/installUtils/fullConfig.json"
  python3 - "$root/2027_alpha7/installUtils/$(basename "$zip")" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("gradle-9.4.1/bin/gradle", "stub")
PY
}

run() { bash "$SCRIPT" "$1" "$2"; }

# good
R="$TMP/r1"; make_install "$R"
G="$R/gh"; D="$G/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj"
assert_ok "good install" run "$R" "$G"
assert_ok "unpacked" test -f "$D/gradle-9.4.1/bin/gradle"
assert_ok "ok marker" test -f "$D/gradle-9.4.1-bin.zip.ok"
assert_eq 0 "$(stat -c %s "$D/gradle-9.4.1-bin.zip.ok")" "marker empty"
assert_fails "zip removed from installUtils" test -e "$R/.current/installUtils/gradle-9.4.1-bin.zip"
assert_fails "zip not copied to dists" test -e "$D/gradle-9.4.1-bin.zip"

# missing zip
R="$TMP/r2"; make_install "$R"; rm "$R/.current/installUtils/gradle-9.4.1-bin.zip"
assert_fails "missing zip" run "$R" "$R/gh"

# missing Gradle key
R="$TMP/r3"; make_install "$R"; echo '{}' > "$R/.current/installUtils/fullConfig.json"
assert_fails "missing Gradle key" run "$R" "$R/gh"

# ZipName with ..
R="$TMP/r4"; make_install "$R" gradle-9.4.1-bin.zip
printf '{"Gradle": {"Hash": "abc", "ZipName": "../evil.zip"}}\n' > "$R/.current/installUtils/fullConfig.json"
echo x > "$R/.current/evil.zip"
assert_fails "ZipName with .." run "$R" "$R/gh"
assert_fails "no escaped zip moved" test -e "$TMP/evil.zip"
assert_fails "no gradle home created" test -e "$R/gh"

# ZipName not .zip
R="$TMP/r5"; make_install "$R" gradle-9.4.1-bin.tar
assert_fails "ZipName not .zip" run "$R" "$R/gh"

# Hash with slash
R="$TMP/r6"; make_install "$R" gradle-9.4.1-bin.zip a/b
assert_fails "Hash with slash" run "$R" "$R/gh"

# corrupt zip leaves no partial dist dir
R="$TMP/r7"; make_install "$R"; echo notazip > "$R/.current/installUtils/gradle-9.4.1-bin.zip"
assert_fails "corrupt zip" run "$R" "$R/gh"
assert_fails "no partial hash dir" test -e "$R/gh/permwrapper/dists/gradle-9.4.1-bin/arn2x92ynaizyzdaamcbpbhtj"

# arg count
assert_fails "wrong arg count" bash "$SCRIPT" "$TMP/r1"

finish

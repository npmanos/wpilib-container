#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/version-info.sh"

assert_eq $'stable=false\nmajor=2027' "$(bash "$SCRIPT" 2027.0.0-alpha-7)" "alpha"
assert_eq $'stable=false\nmajor=2027' "$(bash "$SCRIPT" 2027.1.1-beta-1)" "beta"
assert_eq $'stable=false\nmajor=2027' "$(bash "$SCRIPT" 2027.1.1-rc-1)" "rc"
assert_eq $'stable=true\nmajor=2026' "$(bash "$SCRIPT" 2026.2.1)" "stable"
assert_fails "garbage" bash "$SCRIPT" foo
assert_fails "empty" bash "$SCRIPT" ""

finish

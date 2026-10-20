#!/usr/bin/env bash
# Shared helpers for tests/test_*.sh. Source this file.
set -u
FAILURES=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok   $label"
  else
    echo "FAIL $label: expected [$expected], got [$actual]"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_ok() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   $label"
  else
    echo "FAIL $label: command failed: $*"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_fails() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL $label: command unexpectedly succeeded: $*"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok   $label"
  fi
}

# minimal_path DIR: create DIR holding symlinks to the only external commands smoke-test.sh may use
# and print DIR. Putting it alone on PATH hides any cmake, gdb or g++ on the machine running the tests.
minimal_path() {
  local dir="$1" c
  mkdir -p "$dir"
  for c in bash sh python3 unzip mktemp rm realpath readlink dirname basename head cat ls; do
    ln -sf "$(command -v "$c")" "$dir/$c"
  done
  echo "$dir"
}

finish() {
  if ((FAILURES > 0)); then
    echo "$FAILURES assertion(s) failed"
    exit 1
  fi
}

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

finish() {
  if ((FAILURES > 0)); then
    echo "$FAILURES assertion(s) failed"
    exit 1
  fi
}

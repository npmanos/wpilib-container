#!/usr/bin/env bash
# Workflows invoke scripts/*.sh directly (e.g. docker run ... /scripts/smoke-test.sh),
# so git must record the executable bit.
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."
for f in scripts/*.sh; do
  mode="$(git ls-files -s -- "$f" | cut -d' ' -f1)"
  assert_eq 100755 "$mode" "$f is executable in git"
done
finish

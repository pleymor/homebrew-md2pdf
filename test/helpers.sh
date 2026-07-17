#!/bin/bash
# Shared assertion helpers for md2pdf tests.
PASS=0
FAIL=0

# check <description> <command...> — passes if the command exits 0
check() {
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    PASS=$((PASS + 1)); echo "ok - $desc"
  else
    FAIL=$((FAIL + 1)); echo "not ok - $desc"
  fi
}

finish() {
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}

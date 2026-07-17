#!/bin/bash
# Runs all md2pdf test suites.
cd "$(dirname "$0")"
fail=0
for t in test_cli.sh test_filters.sh test_reference.sh test_integration.sh; do
  [ -f "$t" ] || continue
  echo "== $t =="
  bash "$t" || fail=1
done
exit $fail

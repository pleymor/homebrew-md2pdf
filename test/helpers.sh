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

# pdf_page_of <pdf> <text> — prints the 1-based number of the first page whose
# extracted text contains <text>, or returns 1 when no page matches.
pdf_page_of() {
  local pdf="$1" needle="$2" pages page
  pages=$(pdfinfo "$pdf" | awk '/^Pages:/ {print $2}')
  for ((page = 1; page <= pages; page++)); do
    if pdftotext -f "$page" -l "$page" "$pdf" - 2>/dev/null | grep -qF "$needle"; then
      echo "$page"; return 0
    fi
  done
  return 1
}

finish() {
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}

#!/bin/bash
# CLI tests for md2pdf.sh — no Docker daemon required.
set -u
cd "$(dirname "$0")/.."
source test/helpers.sh

# Fake container engines so the script stops at the engine check, after
# printing the "Converting ..." line that reveals the resolved output path.
FAKEBIN=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$FAKEBIN/docker"
cp "$FAKEBIN/docker" "$FAKEBIN/podman"
chmod +x "$FAKEBIN/docker" "$FAKEBIN/podman"

out=$(./md2pdf.sh --help 2>&1)
check "--help mentions --word" grep -q -- "--word" <<< "$out"

out=$(./md2pdf.sh example.md out.pdf --word 2>&1)
rc=$?
check "--word with .pdf output exits 1" test "$rc" -eq 1
check "--word with .pdf output prints conflict" grep -qi "conflict" <<< "$out"

out=$(PATH="$FAKEBIN:$PATH" ./md2pdf.sh example.md --word 2>&1)
check "--word infers .docx default output" grep -q "example.docx" <<< "$out"

out=$(PATH="$FAKEBIN:$PATH" ./md2pdf.sh example.md report.docx 2>&1)
check ".docx extension accepted as output" grep -q "report.docx" <<< "$out"

out=$(PATH="$FAKEBIN:$PATH" ./md2pdf.sh example.md 2>&1)
check "default output stays .pdf" grep -q "example.pdf" <<< "$out"

out=$(./md2pdf.sh missing-file.md 2>&1)
check "missing input exits 1" test $? -eq 1

rm -rf "$FAKEBIN"
finish

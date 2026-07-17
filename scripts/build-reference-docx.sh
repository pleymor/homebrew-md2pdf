#!/bin/bash
# Regenerates templates/reference.docx from pandoc's default reference doc,
# with md2pdf customizations applied (see scripts/patch_reference_styles.py).
set -euo pipefail
cd "$(dirname "$0")/.."

docker build -q -t md2pdf . > /dev/null
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

docker run --rm md2pdf pandoc --print-default-data-file reference.docx > "$WORKDIR/reference.docx"
unzip -q "$WORKDIR/reference.docx" -d "$WORKDIR/ref"

python3 scripts/patch_reference_styles.py "$WORKDIR/ref"

(cd "$WORKDIR/ref" && zip -q -r -X "$WORKDIR/patched.docx" .)
cp "$WORKDIR/patched.docx" templates/reference.docx
echo "templates/reference.docx regenerated"

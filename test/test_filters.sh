#!/bin/bash
# Lua filter tests — run pandoc inside the md2pdf image with local
# filters mounted, then inspect the produced OOXML. Needs Docker.
set -u
cd "$(dirname "$0")/.."
source test/helpers.sh
mkdir -p test/tmp

docker build -q -t md2pdf . > /dev/null

# run_pandoc <output-name> <args...> — converts a fixture inside the container
run_pandoc() {
  local out="$1"; shift
  docker run --rm \
    -v "$PWD/filters:/filters" \
    -v "$PWD/test/fixtures:/data" \
    -v "$PWD/test/tmp:/out" \
    md2pdf pandoc "$@" -o "/out/$out"
}

# run_pandoc_text <args...> — converts a fixture to stdout (text formats)
run_pandoc_text() {
  docker run --rm \
    -v "$PWD/filters:/filters" \
    -v "$PWD/test/fixtures:/data" \
    md2pdf pandoc "$@"
}

docxml() {
  unzip -p "test/tmp/$1" word/document.xml
}

# --- horizontal-rule.lua ---
run_pandoc hr.docx /data/hr.md --lua-filter /filters/horizontal-rule.lua
check "hr: docx gets a page break" grep -q '<w:br w:type="page"/>' <<< "$(docxml hr.docx)"

hr_tex=$(run_pandoc_text /data/hr.md -t latex --lua-filter /filters/horizontal-rule.lua)
check "hr: latex still gets newpage" grep -q '\\newpage' <<< "$hr_tex"

finish

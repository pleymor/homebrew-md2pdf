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

# --- alerts.lua ---
run_pandoc alerts.docx /data/alerts.md --lua-filter /filters/alerts.lua
alerts_xml=$(docxml alerts.docx)
check "alerts: docx NOTE style applied" grep -q 'w:val="AlertNote"' <<< "$alerts_xml"
check "alerts: docx WARNING style applied" grep -q 'w:val="AlertWarning"' <<< "$alerts_xml"
check "alerts: docx keeps content" grep -q 'Useful information.' <<< "$alerts_xml"

alerts_tex=$(run_pandoc_text /data/alerts.md -t latex --lua-filter /filters/alerts.lua)
check "alerts: latex still uses tcolorbox" grep -q 'tcolorbox' <<< "$alerts_tex"

# --- table-autofit.lua ---
run_pandoc table.docx /data/table.md --lua-filter /filters/table-autofit.lua
widths=$(docxml table.docx | grep -o '<w:gridCol w:w="[0-9]*"' | grep -o '[0-9][0-9]*')
w1=$(echo "$widths" | sed -n 1p)
w2=$(echo "$widths" | sed -n 2p)
check "table: docx has two column widths" test -n "$w1" -a -n "$w2"
check "table: long column wider than short" test "${w2:-0}" -gt "${w1:-0}"

table_tex=$(run_pandoc_text /data/table.md -t latex --lua-filter /filters/table-autofit.lua)
check "table: latex still emits longtable" grep -q 'longtable' <<< "$table_tex"

# --- titlepage-docx.lua ---
run_pandoc cover.docx /data/cover.md \
  --shift-heading-level-by=-1 \
  -M author="Jane Doe" -M date="2026-07-17" -M titlelogo=/data/logo.png \
  --lua-filter /filters/titlepage-docx.lua
cover_xml=$(docxml cover.docx)
check "cover: TOC field present" grep -q 'TOC .o "1-3"' <<< "$cover_xml"
check "cover: author present" grep -q 'Jane Doe' <<< "$cover_xml"
check "cover: title styled" grep -q 'w:val="Title"' <<< "$cover_xml"
check "cover: logo embedded" bash -c "unzip -l test/tmp/cover.docx | grep -q 'word/media/'"
check "cover: page break after cover" grep -q '<w:br w:type="page"/>' <<< "$cover_xml"

finish

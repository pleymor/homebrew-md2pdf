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

# --- image-fit.lua ---
python3 - <<'EOF'
import struct, zlib

def png(path, w, h):
    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)  # 8-bit grayscale
    raw = b"".join(b"\x00" + b"\x80" * w for _ in range(h))
    idat = zlib.compress(raw)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))

png("test/tmp/tall.png", 200, 4000)
png("test/tmp/small.png", 100, 100)
EOF
printf '![](/out/tall.png)\n\n![](/out/small.png)\n' > test/tmp/images.md
run_pandoc images.docx /out/images.md --lua-filter /filters/image-fit.lua
cys=$(docxml images.docx | grep -o 'cy="[0-9]*"' | grep -o '[0-9]*')
tall_cy=$(echo "$cys" | sed -n 1p)
small_cy=$(echo "$cys" | sed -n '$p')
check "image-fit: tall image capped to max height" \
  test "${tall_cy:-99999999}" -ge 6300000 -a "${tall_cy:-99999999}" -le 6500000
# 100px at the writer's 72 dpi = 1270000 EMU
check "image-fit: small image untouched" \
  test "${small_cy:-0}" -ge 1200000 -a "${small_cy:-0}" -le 1300000

# mermaid-filter embeds diagrams as data URIs, not files
b64=$(base64 < test/tmp/tall.png | tr -d '\n')
printf '![](data:image/png;base64,%s)\n' "$b64" > test/tmp/datauri.md
run_pandoc datauri.docx /out/datauri.md --lua-filter /filters/image-fit.lua
datauri_cy=$(docxml datauri.docx | grep -o 'cy="[0-9]*"' | grep -o '[0-9]*' | sed -n 1p)
check "image-fit: data-URI image capped to max height" \
  test "${datauri_cy:-99999999}" -ge 6300000 -a "${datauri_cy:-99999999}" -le 6500000

finish

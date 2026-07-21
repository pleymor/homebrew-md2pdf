#!/bin/bash
# End-to-end tests: full docx conversion + PDF regression. Needs Docker.
set -u
cd "$(dirname "$0")/.."
source test/helpers.sh
mkdir -p test/tmp
rm -f test/tmp/example.docx test/tmp/example.pdf

./md2pdf.sh example.md test/tmp/example.docx --logo logo.png --author "Test Author" --date "2026-07-17"
check "docx conversion exits 0" test $? -eq 0
check "docx file exists" test -f test/tmp/example.docx

doc=$(unzip -p test/tmp/example.docx word/document.xml 2>/dev/null)
check "docx has TOC field" grep -q 'TOC .o "1-3"' <<< "$doc"
check "docx cover has author" grep -q 'Test Author' <<< "$doc"
check "docx has page breaks" grep -q '<w:br w:type="page"/>' <<< "$doc"
check "docx alert styled" grep -q 'w:val="AlertNote"' <<< "$doc"
check "docx embeds images" bash -c "unzip -l test/tmp/example.docx | grep -q 'word/media/'"
footer=$(unzip -p test/tmp/example.docx word/footer1.xml 2>/dev/null)
check "docx footer has PAGE field" grep -q 'w:instr=" PAGE "' <<< "$footer"
check "docx footer has NUMPAGES field" grep -q 'w:instr=" NUMPAGES "' <<< "$footer"

# Font/margin overrides are patched into a temp reference doc
./md2pdf.sh test/fixtures/hr.md test/tmp/hr-font.docx --font "Arial" --margin 1in
check "docx font override exits 0" test $? -eq 0
styles=$(unzip -p test/tmp/hr-font.docx word/styles.xml 2>/dev/null)
check "docx font override applied" grep -q 'Arial' <<< "$styles"
sect=$(unzip -p test/tmp/hr-font.docx word/document.xml 2>/dev/null)
check "docx margin override applied" grep -q 'w:top="1440"' <<< "$sect"

# PDF pipeline regression
./md2pdf.sh example.md test/tmp/example.pdf
check "pdf conversion exits 0" test $? -eq 0
check "pdf file exists" test -f test/tmp/example.pdf

finish

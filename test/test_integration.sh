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
# Task lists must reach Word as clickable checkboxes, not bullet + glyph
checklist=$(python3 test/docx_checklist.py test/tmp/example.docx 2>/dev/null)
check "docx checklist has clickable checkboxes" test "$(sed -n 's/^checkboxes=//p' <<< "$checklist")" -eq 3
check "docx checklist items are not bulleted" test "$(sed -n 's/^bulleted_tasks=//p' <<< "$checklist")" -eq 0
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

# hyperref draws a red box around every link unless it is loaded with hidelinks
read -r links bordered <<< "$(python3 test/pdf_link_borders.py test/tmp/example.pdf)"
check "pdf has link annotations" test "${links:-0}" -gt 0
check "pdf links have no coloured border box" test "${bordered:-1}" -eq 0

# Emoji must not leak their fallback font into the following text: Symbola has
# no bold/italic member, so a leaking switch silently drops all formatting.
rm -f test/tmp/emoji.pdf
./md2pdf.sh test/fixtures/emoji.md test/tmp/emoji.pdf
check "emoji pdf exists" test -f test/tmp/emoji.pdf

# fonts_on <needle> — fonts used by the page holding <needle> ("?" if not found)
fonts_on() {
  local page
  page=$(pdf_page_of test/tmp/emoji.pdf "$1") || { echo "?"; return; }
  pdffonts -f "$page" -l "$page" test/tmp/emoji.pdf
}

emoji_fonts=$(fonts_on "A check mark")
inside_fonts=$(fonts_on "stays bold to the end")
after_fonts=$(fonts_on "must stay bold")

check "emoji page renders with Symbola" grep -q 'Symbola' <<< "$emoji_fonts"
check "bold right after emoji stays bold" grep -q 'Bold' <<< "$emoji_fonts"
check "bold around an emoji stays bold" grep -q 'Bold' <<< "$inside_fonts"
check "later page keeps bold" grep -q 'Bold' <<< "$after_fonts"
grep -q 'Symbola' <<< "$after_fonts" && leaked=1 || leaked=0
check "emoji font does not leak to later pages" test "$leaked" -eq 0

finish

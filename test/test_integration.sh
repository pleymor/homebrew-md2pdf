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
# The TOC ships filled in, and nothing asks Word to update fields on open
# (that only produces a prompt, and answering "no" leaves the TOC empty).
settings=$(unzip -p test/tmp/example.docx word/settings.xml 2>/dev/null)
check "docx does not ask Word to update fields on open" lacks 'updateFields' "$settings"
toc=$(python3 test/docx_toc.py test/tmp/example.docx)
check "docx TOC lists the headings" test "$(sed -n 's/^entries=//p' <<< "$toc")" -ge 10
check "docx TOC entries match the headings" test "$(sed -n 's/^mismatch=//p' <<< "$toc")" -eq 0
check "docx TOC entries are clickable" test "$(sed -n 's/^linked=//p' <<< "$toc")" -ge 10
check "docx TOC field is marked dirty" grep -q 'w:dirty="true"' <<< "$doc"

# Tables reach Word with visible black gridlines
example_styles=$(unzip -p test/tmp/example.docx word/styles.xml 2>/dev/null)
example_table_borders=$(python3 -c 'import re,sys; x=sys.stdin.read(); m=re.search(r"<w:style [^>]*w:styleId=\"Table\"[^>]*>.*?<w:tblBorders>(.*?)</w:tblBorders>", x, re.S); print(m.group(1) if m else "")' <<< "$example_styles")
check "docx tables have borders" test -n "$example_table_borders"
check "docx table borders are black on all six edges" \
  test "$(grep -o 'w:color="000000"' <<< "$example_table_borders" | wc -l)" -eq 6
# Every numbered list starts again at 1 (see scripts/restart_list_numbering.py)
example_lists=$(python3 test/docx_lists.py test/tmp/example.docx)
check "docx has several numbered lists" \
  test "$(sed -n 's/^ordered_lists=//p' <<< "$example_lists")" -ge 2
check "docx numbered lists have their own definition" \
  test "$(sed -n 's/^shared_abstract=//p' <<< "$example_lists")" -eq 0

footer=$(unzip -p test/tmp/example.docx word/footer1.xml 2>/dev/null)
check "docx footer has PAGE field" grep -q 'w:instr=" PAGE "' <<< "$footer"
check "docx footer has NUMPAGES field" grep -q 'w:instr=" NUMPAGES "' <<< "$footer"

# Font/margin overrides are patched into a temp reference doc
./md2pdf.sh test/fixtures/hr.md test/tmp/hr-font.docx --font "Arial" --margin 1in
check "docx font override exits 0" test $? -eq 0
styles=$(unzip -p test/tmp/hr-font.docx word/styles.xml 2>/dev/null)
check "docx font override applied" grep -q 'Arial' <<< "$styles"
# Grepping the whole file is not enough: only the code style carries a literal
# font name, so body text and headings can stay on Word's Times New Roman
# fallback while 'Arial' is present elsewhere in styles.xml.
font_docdefaults=$(python3 -c 'import re,sys; m=re.search(r"<w:docDefaults>.*?</w:docDefaults>", sys.stdin.read(), re.S); print(m.group(0) if m else "")' <<< "$styles")
check "docx font override reaches body text" grep -q 'w:ascii="Arial"' <<< "$font_docdefaults"
font_heading=$(python3 -c 'import re,sys; m=re.search(r"<w:style [^>]*w:styleId=\"Heading1\".*?</w:style>", sys.stdin.read(), re.S); print(m.group(0) if m else "")' <<< "$styles")
check "docx font override reaches headings" grep -q 'w:ascii="Arial"' <<< "$font_heading"
# The override substitutes a font name inside styles.xml, so a plain search for
# "DejaVu Sans" would also chew through "DejaVu Sans Mono" and invent an
# "Arial Mono" that no system has.
check "docx font override invents no monospace variant" lacks 'Arial Mono' "$styles"
font_verbatim=$(python3 -c 'import re,sys; m=re.search(r"<w:style [^>]*w:styleId=\"VerbatimChar\".*?</w:style>", sys.stdin.read(), re.S); print(m.group(0) if m else "")' <<< "$styles")
check "docx font override leaves code monospaced" grep -q 'w:ascii="DejaVu Sans Mono"' <<< "$font_verbatim"

# The default docx must name a real font too, or Word picks Times New Roman
default_styles=$(unzip -p test/tmp/example.docx word/styles.xml 2>/dev/null)
default_docdefaults=$(python3 -c 'import re,sys; m=re.search(r"<w:docDefaults>.*?</w:docDefaults>", sys.stdin.read(), re.S); print(m.group(0) if m else "")' <<< "$default_styles")
check "default docx body font is DejaVu Sans" grep -q 'w:ascii="DejaVu Sans"' <<< "$default_docdefaults"
sect=$(unzip -p test/tmp/hr-font.docx word/document.xml 2>/dev/null)
check "docx margin override applied" grep -q 'w:top="1440"' <<< "$sect"

# Word continues a numbering sequence across lists that share an abstract
# definition, so each list gets its own definition and nsid on the way out.
rm -f test/tmp/lists.docx
./md2pdf.sh test/fixtures/lists.md test/tmp/lists.docx
check "lists docx conversion exits 0" test $? -eq 0
lists=$(python3 test/docx_lists.py test/tmp/lists.docx)
# list_stat <key> — value of <key> in the numbered-list report
list_stat() { sed -n "s/^$1=//p" <<< "$lists"; }
check "lists: every numbered list found" test "$(list_stat ordered_lists)" -eq 4
check "lists: no two numbered lists share a definition" test "$(list_stat shared_abstract)" -eq 0
check "lists: no two numbered lists share an nsid" test "$(list_stat shared_nsid)" -eq 0
check "lists: every numbered list restarts at 1" test "$(list_stat restarts)" -eq 4

# PDF pipeline regression
./md2pdf.sh example.md test/tmp/example.pdf
check "pdf conversion exits 0" test $? -eq 0
check "pdf file exists" test -f test/tmp/example.pdf

# --font has to reach the PDF as well: it used to be parsed and then dropped, so
# every PDF rendered in XeLaTeX's Latin Modern default whatever was asked for.
rm -f test/tmp/font-arial.pdf test/tmp/font-dejavu.pdf test/tmp/font-missing.pdf test/tmp/font-plain.pdf
./md2pdf.sh test/fixtures/font.md test/tmp/font-arial.pdf --font "Arial"
check "pdf font override exits 0" test $? -eq 0
arial_fonts=$(pdf_font_names test/tmp/font-arial.pdf)
# Arial is proprietary and absent from the image; Liberation Sans is metrically
# identical and stands in for it.
check "pdf --font Arial renders in Liberation Sans" grep -q '^LiberationSans' <<< "$arial_fonts"
check "pdf --font Arial drops the Latin Modern default" lacks 'LMRoman' "$arial_fonts"
check "pdf --font Arial keeps code monospaced" grep -qx 'DejaVuSansMono' <<< "$arial_fonts"

# Asking for the default font by name must be honoured, not mistaken for "no
# option given" - the two are distinct and only the parser can tell them apart.
./md2pdf.sh test/fixtures/font.md test/tmp/font-dejavu.pdf --font "DejaVu Sans"
check "pdf honours an explicit --font DejaVu Sans" grep -qx 'DejaVuSans' <<< "$(pdf_font_names test/tmp/font-dejavu.pdf)"

# XeLaTeX aborts on an unknown font name unless the preamble guards the switch
./md2pdf.sh test/fixtures/font.md test/tmp/font-missing.pdf --font "Calibri"
check "pdf unknown font still converts" test $? -eq 0
check "pdf unknown font falls back to the default" grep -q '^LMRoman' <<< "$(pdf_font_names test/tmp/font-missing.pdf)"
# Probing for the font makes TeX log the miss next to the input file
check "pdf unknown font leaves no missfont.log behind" test ! -f test/fixtures/missfont.log

# Without --font nothing may change: existing documents keep their rendering
./md2pdf.sh test/fixtures/font.md test/tmp/font-plain.pdf
check "pdf without --font keeps Latin Modern" grep -q '^LMRoman' <<< "$(pdf_font_names test/tmp/font-plain.pdf)"

# The PDF cover page had no coverage at all, and it is where the title, the logo
# and the font override have to land together - the title page is built from a
# separate template, so it can miss a font switch the body picked up.
rm -f test/tmp/cover-font.pdf
./md2pdf.sh test/fixtures/cover.md test/tmp/cover-font.pdf --logo logo.png --font "Arial" --author "Test Author" --date "2026-08-07"
check "pdf cover conversion exits 0" test $? -eq 0
cover_text=$(pdftotext -f 1 -l 1 test/tmp/cover-font.pdf - 2>/dev/null)
check "pdf cover shows the title" grep -q 'My Document' <<< "$cover_text"
check "pdf cover shows the author" grep -q 'Test Author' <<< "$cover_text"
check "pdf cover shows the date" grep -q '2026-08-07' <<< "$cover_text"
check "pdf cover embeds the logo" \
  test "$(pdfimages -list -f 1 -l 1 test/tmp/cover-font.pdf 2>/dev/null | tail -n +3 | wc -l)" -gt 0
check "pdf cover follows the font override" grep -q '^LiberationSans' <<< "$(pdf_font_names test/tmp/cover-font.pdf)"

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

#!/bin/bash
# Checks the committed templates/reference.docx customizations.
set -u
cd "$(dirname "$0")/.."
source test/helpers.sh

check "reference.docx exists" test -f templates/reference.docx
styles=$(unzip -p templates/reference.docx word/styles.xml 2>/dev/null)
for sid in AlertNote AlertTip AlertImportant AlertWarning AlertCaution TitleLogo Checklist TOC1 TOC2 TOC3; do
  check "reference has $sid style" grep -q "w:styleId=\"$sid\"" <<< "$styles"
done
# Checklist items sit where a bullet would, without a list marker
checklist_style=$(python3 -c 'import re,sys; x=sys.stdin.read(); m=re.search(r"<w:style [^>]*w:styleId=\"Checklist\".*?</w:style>", x, re.S); print(m.group(0) if m else "")' <<< "$styles")
check "reference indents the Checklist style" grep -q '<w:ind ' <<< "$checklist_style"
check "reference uses DejaVu Sans" grep -q 'DejaVu Sans' <<< "$styles"

# Pandoc binds every font through a theme reference (w:asciiTheme="minorHAnsi")
# rather than a literal name. Dropping those references without writing a real
# font leaves <w:rFonts/> empty, and Word then falls back to its own built-in
# default - Times New Roman - for body text, headings and the title alike.
# xml_block <element-regex> reads styles.xml on stdin and prints the first match
xml_block() {
  python3 -c 'import re,sys; m=re.search(sys.argv[1], sys.stdin.read(), re.S); print(m.group(0) if m else "")' "$1"
}
docdefaults=$(xml_block '<w:docDefaults>.*?</w:docDefaults>' <<< "$styles")
check "reference declares a default font" grep -q '<w:rFonts [^>]*w:ascii=' <<< "$docdefaults"
check "reference default font is DejaVu Sans" grep -q 'w:ascii="DejaVu Sans"' <<< "$docdefaults"
check "reference leaves no dangling theme font reference" lacks 'Theme="' "$styles"
for sid in Title Heading1 Heading2 Heading3; do
  style=$(xml_block "<w:style [^>]*w:styleId=\"$sid\".*?</w:style>" <<< "$styles")
  check "reference $sid font is DejaVu Sans" grep -q 'w:ascii="DejaVu Sans"' <<< "$style"
done
# Code is the one place that must not follow the main font: fixed width is what
# makes a code block readable, and the PDF side pins \setmonofont for the same
# reason. Pandoc ships Consolas here, which the font patch would otherwise
# flatten into the proportional main font along with everything else.
verbatim=$(xml_block '<w:style [^>]*w:styleId="VerbatimChar".*?</w:style>' <<< "$styles")
check "reference code style is monospaced" grep -q 'w:ascii="DejaVu Sans Mono"' <<< "$verbatim"
# The font patch must not stray outside <w:rFonts>: w:eastAsia is also a w:lang
# attribute, where a font name is meaningless and schema-invalid.
check "reference keeps font names out of language attributes" \
  test "$(grep -o '<w:lang[^>]*DejaVu[^>]*>' <<< "$styles" | wc -l)" -eq 0
# Tables ship with plain black gridlines; pandoc's default Table style has none
table_borders=$(python3 -c 'import re,sys; x=sys.stdin.read(); m=re.search(r"<w:style [^>]*w:styleId=\"Table\"[^>]*>.*?<w:tblBorders>(.*?)</w:tblBorders>", x, re.S); print(m.group(1) if m else "")' <<< "$styles")
check "reference Table style has borders" test -n "$table_borders"
for edge in top left bottom right insideH insideV; do
  check "reference Table style borders the $edge edge" \
    grep -q "<w:$edge w:val=\"single\"" <<< "$table_borders"
done
check "reference Table borders are black" \
  test "$(grep -o 'w:color="000000"' <<< "$table_borders" | wc -l)" -eq 6
doc=$(unzip -p templates/reference.docx word/document.xml 2>/dev/null)
check "reference margins are 2.5cm" grep -q 'w:top="1417"' <<< "$doc"
check "reference registers footer reference" grep -q '<w:footerReference' <<< "$doc"

footer=$(unzip -p templates/reference.docx word/footer1.xml 2>/dev/null)
check "reference footer has PAGE field" grep -q 'w:instr=" PAGE "' <<< "$footer"
check "reference footer has NUMPAGES field" grep -q 'w:instr=" NUMPAGES "' <<< "$footer"
check "reference footer is centered" grep -q 'w:jc w:val="center"' <<< "$footer"

ct=$(unzip -p templates/reference.docx "\[Content_Types\].xml" 2>/dev/null)
check "reference declares footer content type" grep -q 'wordprocessingml.footer' <<< "$ct"
finish

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

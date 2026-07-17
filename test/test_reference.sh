#!/bin/bash
# Checks the committed templates/reference.docx customizations.
set -u
cd "$(dirname "$0")/.."
source test/helpers.sh

check "reference.docx exists" test -f templates/reference.docx
styles=$(unzip -p templates/reference.docx word/styles.xml 2>/dev/null)
for sid in AlertNote AlertTip AlertImportant AlertWarning AlertCaution TitleLogo; do
  check "reference has $sid style" grep -q "w:styleId=\"$sid\"" <<< "$styles"
done
check "reference uses DejaVu Sans" grep -q 'DejaVu Sans' <<< "$styles"
doc=$(unzip -p templates/reference.docx word/document.xml 2>/dev/null)
check "reference margins are 2.5cm" grep -q 'w:top="1417"' <<< "$doc"
finish

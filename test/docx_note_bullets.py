#!/usr/bin/env python3
"""Reports how the bullets written inside the example NOTE reached Word.

Usage: docx_note_bullets.py <file.docx>

Prints:
  bulleted=<n>   list paragraphs among the note's four bullet texts
  styles=<...>   comma-separated paragraph style of each of them
"""
import re
import sys
import zipfile

BULLETS = ("un", "dos", "tres", "un pasido bardate Maria")


def main() -> None:
    xml = zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode("utf-8")

    bulleted = 0
    styles = []
    for para in re.findall(r"<w:p\b.*?</w:p>", xml, re.DOTALL):
        text = "".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", para, re.DOTALL)).strip()
        if text not in BULLETS:
            continue
        if "<w:numPr>" in para:
            bulleted += 1
        style = re.search(r'<w:pStyle w:val="([^"]+)"', para)
        styles.append(style.group(1) if style else "none")

    print(f"bulleted={bulleted}")
    print(f"styles={','.join(styles)}")


if __name__ == "__main__":
    main()

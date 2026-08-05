#!/usr/bin/env python3
"""Reports the inline formatting kept inside a docx paragraph.

Usage: docx_alerts.py <file.docx> <needle>

Looks at the first paragraph whose text contains <needle> and prints one
"key=value" per line:
  style     its paragraph style ("" when unstyled)
  bold      runs in bold
  italic    runs in italic
  code      runs carrying the VerbatimChar (code span) style
  links     hyperlinks
"""
import sys
import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def text_of(el):
    """Concatenates every w:t descendant of an element."""
    return "".join(t.text or "" for t in el.iter(f"{W}t"))


def main():
    path, needle = sys.argv[1], sys.argv[2]
    with zipfile.ZipFile(path) as z:
        root = ET.fromstring(z.read("word/document.xml"))

    para = next((p for p in root.iter(f"{W}p") if needle in text_of(p)), None)
    if para is None:
        sys.exit(f"no paragraph contains {needle!r}")

    style = para.find(f".//{W}pStyle")
    run_styles = [s.get(f"{W}val") for s in para.iter(f"{W}rStyle")]

    stats = {
        "style": style.get(f"{W}val") if style is not None else "",
        "bold": len(list(para.iter(f"{W}b"))),
        "italic": len(list(para.iter(f"{W}i"))),
        "code": run_styles.count("VerbatimChar"),
        "links": len(list(para.iter(f"{W}hyperlink"))),
    }

    for key, value in stats.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Reports the table of contents stored in a docx.

Usage: docx_toc.py <file.docx>

Prints one "key=value" per line:
  field       1 when a TOC field is present
  dirty       1 when that field is flagged for refresh
  entry       one per TOC entry, as "<style>|<anchor>|<text>"
  entries     how many entries there are
  linked      entries whose text sits inside a hyperlink
  mismatch    entries whose anchor or text disagrees with the heading it points
              at (0 means the baked TOC matches the document)
"""
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
TOC_STYLE = re.compile(r"^TOC(\d)$")
HEADING_STYLE = re.compile(r"^Heading(\d)$")


def text_of(el):
    """Concatenates every w:t descendant, with tabs as single spaces."""
    parts = []
    for node in el.iter():
        if node.tag == f"{W}t":
            parts.append(node.text or "")
        elif node.tag == f"{W}tab":
            parts.append(" ")
    return " ".join("".join(parts).split())


def style_of(para):
    """Paragraph style id of a w:p, or "" when unstyled."""
    style = para.find(f".//{W}pStyle")
    return style.get(f"{W}val") if style is not None else ""


def collect(root):
    """Returns (toc entries, headings by anchor), both in document order."""
    entries, headings, pending_anchor = [], {}, None

    for node in root.iter():
        if node.tag == f"{W}bookmarkStart":
            pending_anchor = node.get(f"{W}name")
        elif node.tag == f"{W}p":
            style = style_of(node)
            if TOC_STYLE.match(style):
                link = node.find(f".//{W}hyperlink")
                entries.append({
                    "style": style,
                    "anchor": link.get(f"{W}anchor") if link is not None else "",
                    "text": text_of(node),
                    "linked": link is not None and text_of(link) == text_of(node),
                })
            elif HEADING_STYLE.match(style) and pending_anchor:
                headings[pending_anchor] = text_of(node)
                pending_anchor = None

    return entries, headings


def main():
    with zipfile.ZipFile(sys.argv[1]) as z:
        xml = z.read("word/document.xml")
    root = ET.fromstring(xml)
    entries, headings = collect(root)

    print(f"field={int(b'TOC ' in xml)}")
    print(f"dirty={int(b'w:dirty=' in xml)}")
    for entry in entries:
        print(f"entry={entry['style']}|{entry['anchor']}|{entry['text']}")
    print(f"entries={len(entries)}")
    print(f"linked={sum(1 for e in entries if e['linked'])}")
    print(f"mismatch={sum(1 for e in entries if headings.get(e['anchor']) != e['text'])}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Reports how a docx renders task-list ("checklist") items.

Usage: docx_checklist.py <file.docx>

Prints one "key=value" per line:
  task_paras        paragraphs holding a checklist item ("Item N")
  bulleted_tasks    how many of those still carry list numbering (<w:numPr>)
  styled_tasks      how many carry the Checklist paragraph style
  checkboxes        w14:checkbox content controls (clickable in Word)
  checked           checkboxes pre-checked (w14:checked w14:val="1")
  legacy_glyphs     leftover bare ☐/☒ characters outside a content control
  plain_bulleted    non-task list items that kept their bullet
"""
import sys
import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
W14 = "{http://schemas.microsoft.com/office/word/2010/wordml}"
GLYPHS = ("☐", "☒")


def text_of(el):
    """Concatenates every w:t descendant of an element."""
    return "".join(t.text or "" for t in el.iter(f"{W}t"))


def main():
    with zipfile.ZipFile(sys.argv[1]) as z:
        root = ET.fromstring(z.read("word/document.xml"))

    stats = dict(
        task_paras=0,
        bulleted_tasks=0,
        styled_tasks=0,
        checkboxes=0,
        checked=0,
        legacy_glyphs=0,
        plain_bulleted=0,
    )

    for para in root.iter(f"{W}p"):
        text = text_of(para)
        boxes = list(para.iter(f"{W14}checkbox"))
        numbered = para.find(f".//{W}numPr") is not None
        styles = [s.get(f"{W}val") for s in para.iter(f"{W}pStyle")]

        stats["checkboxes"] += len(boxes)
        for box in boxes:
            checked = box.find(f"{W14}checked")
            if checked is not None and checked.get(f"{W14}val") in ("1", "true"):
                stats["checked"] += 1

        if "Item" in text:
            stats["task_paras"] += 1
            if numbered:
                stats["bulleted_tasks"] += 1
            if "Checklist" in styles:
                stats["styled_tasks"] += 1
            # A glyph is legitimate inside a content control, not outside one
            if not boxes and any(g in text for g in GLYPHS):
                stats["legacy_glyphs"] += 1
        elif numbered:
            stats["plain_bulleted"] += 1

    for key, value in stats.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()

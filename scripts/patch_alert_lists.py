#!/usr/bin/env python3
"""Gives list items inside a GitHub alert the alert's own paragraph style.

filters/alerts.lua wraps every alert list item in a Div named
"md2pdf-alert-<Style>-<n>". Pandoc drops a custom-style Div placed inside a
list item, but it does keep the id, emitting a block-level bookmark around the
item's paragraphs. Without this pass the items keep pandoc's Compact style, so
the coloured bar and the tinted background of the note stop at the text above
them and the bullets sit outside the box.

This rewrites those paragraphs to carry the Alert* style instead, then drops
the bookmarks that located them.

Usage: patch_alert_lists.py <file.docx>
"""
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

DOCUMENT_PART = "word/document.xml"

MARK_RE = re.compile(
    r'<w:bookmarkStart w:id="(?P<id>\d+)" w:name="md2pdf-alert-(?P<style>Alert\w+)-\d+"\s*/>'
    r"(?P<body>.*?)"
    r'<w:bookmarkEnd w:id="(?P=id)"\s*/>',
    re.DOTALL,
)
PARA_RE = re.compile(r"<w:p\b[^>]*>.*?</w:p>", re.DOTALL)
PSTYLE_RE = re.compile(r'<w:pStyle w:val="[^"]*"\s*/>')
PPR_OPEN_RE = re.compile(r"<w:pPr\s*/?>")


def restyle_paragraph(para: str, style: str) -> str:
    """Points one paragraph at `style`, keeping its numbering as it is."""
    if PSTYLE_RE.search(para):
        return PSTYLE_RE.sub(f'<w:pStyle w:val="{style}" />', para, count=1)

    pstyle = f'<w:pStyle w:val="{style}" />'
    opening = PPR_OPEN_RE.search(para)
    if not opening:
        # No properties at all: give the paragraph a pPr holding just the style.
        return para.replace("<w:p>", f"<w:p><w:pPr>{pstyle}</w:pPr>", 1)
    if opening.group(0).endswith("/>"):
        return para.replace(opening.group(0), f"<w:pPr>{pstyle}</w:pPr>", 1)
    return para[: opening.end()] + pstyle + para[opening.end() :]


def restyle_alert_lists(xml: str) -> str:
    """Restyles every bookmarked alert list item and removes the bookmarks."""

    def rewrite(match: re.Match) -> str:
        style = match.group("style")
        return PARA_RE.sub(lambda p: restyle_paragraph(p.group(0), style), match.group("body"))

    return MARK_RE.sub(rewrite, xml)


def patch_docx(path: Path) -> None:
    """Rewrites the document part of the .docx in place, keeping part order."""
    with zipfile.ZipFile(path) as zf:
        if DOCUMENT_PART not in zf.namelist():
            return
        entries = [(info, zf.read(info.filename)) for info in zf.infolist()]

    with tempfile.NamedTemporaryFile(suffix=".docx", delete=False) as tmp:
        patched = Path(tmp.name)
    with zipfile.ZipFile(patched, "w", zipfile.ZIP_DEFLATED) as out:
        for info, data in entries:
            if info.filename == DOCUMENT_PART:
                data = restyle_alert_lists(data.decode("utf-8")).encode("utf-8")
            out.writestr(info, data)
    shutil.move(str(patched), str(path))


if __name__ == "__main__":
    patch_docx(Path(sys.argv[1]))

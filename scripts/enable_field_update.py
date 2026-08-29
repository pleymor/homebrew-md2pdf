#!/usr/bin/env python3
"""Asks Word to refresh a .docx's fields when it opens the file.

A heading's page number only exists once the document has been laid out, so the
table of contents filters/titlepage-docx.lua builds ships without page numbers.
Word fills them in when the TOC field is refreshed, which otherwise means the
reader pressing Ctrl+A then F9 by hand.

This cannot live in templates/reference.docx: pandoc rebuilds settings.xml from
a fixed whitelist of elements and drops w:updateFields along the way, so the
switch has to be set on the finished document instead.

Usage: enable_field_update.py <file.docx>
"""
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

SETTINGS_PART = "word/settings.xml"
UPDATE_FIELDS = '<w:updateFields w:val="true"/>'


def enable_field_update(xml: str) -> str:
    """Adds the refresh-on-open switch, where CT_Settings expects it."""
    if "<w:updateFields" in xml:
        return xml
    # In the CT_Settings sequence updateFields comes just before footnotePr.
    if "<w:footnotePr" in xml:
        return xml.replace("<w:footnotePr", UPDATE_FIELDS + "<w:footnotePr", 1)
    return xml.replace("</w:settings>", UPDATE_FIELDS + "</w:settings>", 1)


def patch_docx(path: Path) -> None:
    """Rewrites the settings part of the .docx in place, keeping part order."""
    with zipfile.ZipFile(path) as zf:
        if SETTINGS_PART not in zf.namelist():
            return
        entries = [(info, zf.read(info.filename)) for info in zf.infolist()]

    with tempfile.NamedTemporaryFile(suffix=".docx", delete=False) as tmp:
        patched = Path(tmp.name)
    with zipfile.ZipFile(patched, "w", zipfile.ZIP_DEFLATED) as out:
        for info, data in entries:
            if info.filename == SETTINGS_PART:
                data = enable_field_update(data.decode("utf-8")).encode("utf-8")
            out.writestr(info, data)
    shutil.move(str(patched), str(path))


if __name__ == "__main__":
    patch_docx(Path(sys.argv[1]))

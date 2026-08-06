#!/usr/bin/env python3
"""Makes every numbered list in a .docx start again at 1.

Pandoc points all ordered lists at a single abstract numbering definition and
relies on <w:startOverride> to restart them. Word ignores that hint when the
definitions (and their nsid) are shared, so the second list carries on where
the first one stopped. This gives each list its own copy of the definition,
with its own nsid, which Word does treat as an independent sequence.

Usage: restart_list_numbering.py <file.docx>
"""
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

NUMBERING_PART = "word/numbering.xml"

ABSTRACT_RE = re.compile(
    r'<w:abstractNum w:abstractNumId="(\d+)"\s*>(.*?)</w:abstractNum>', re.S
)
NUM_RE = re.compile(r'<w:num w:numId="(\d+)"\s*>(.*?)</w:num>', re.S)
ABSTRACT_REF_RE = re.compile(r'<w:abstractNumId w:val="(\d+)"\s*/>')
NSID_RE = re.compile(r'<w:nsid w:val="[^"]*"\s*/>')
FIRST_FMT_RE = re.compile(r'<w:numFmt w:val="([^"]*)"')

# Word wants an 8 hex digit nsid; this base is far from the ids pandoc emits.
NSID_BASE = 0x0D000000

# Restart markers for the nine list levels Word supports.
LEVEL_OVERRIDES = "".join(
    f'<w:lvlOverride w:ilvl="{level}"><w:startOverride w:val="1" /></w:lvlOverride>'
    for level in range(9)
)


def is_ordered(definition: str) -> bool:
    """Tells whether an abstract numbering definition numbers its items."""
    fmt = FIRST_FMT_RE.search(definition)
    return bool(fmt) and fmt.group(1) != "bullet"


def clone_abstract(definition: str, abstract_id: str, nsid: str) -> str:
    """Copies an abstract numbering definition under a new id and nsid."""
    body = NSID_RE.sub(f'<w:nsid w:val="{nsid}" />', definition, count=1)
    if "<w:nsid " not in body:
        body = f'<w:nsid w:val="{nsid}" />' + body
    return f'<w:abstractNum w:abstractNumId="{abstract_id}">{body}</w:abstractNum>'


def restart_numbering(xml: str) -> str:
    """Rewrites numbering.xml so no two ordered lists share a definition."""
    abstracts = dict(ABSTRACT_RE.findall(xml))
    next_abstract_id = max((int(i) for i in abstracts), default=0) + 1
    next_nsid = NSID_BASE
    taken_abstracts = set()
    clones = []

    def rewrite_num(match: re.Match) -> str:
        nonlocal next_abstract_id, next_nsid
        num_id, body = match.group(1), match.group(2)
        ref = ABSTRACT_REF_RE.search(body)
        if not ref or not is_ordered(abstracts.get(ref.group(1), "")):
            return match.group(0)

        abstract_id = ref.group(1)
        if abstract_id in taken_abstracts:
            new_id = str(next_abstract_id)
            next_abstract_id += 1
            clones.append(clone_abstract(abstracts[abstract_id], new_id, f"{next_nsid:08X}"))
            next_nsid += 1
            body = ABSTRACT_REF_RE.sub(f'<w:abstractNumId w:val="{new_id}" />', body, count=1)
        else:
            taken_abstracts.add(abstract_id)

        if "<w:startOverride " not in body:
            body += LEVEL_OVERRIDES
        return f'<w:num w:numId="{num_id}">{body}</w:num>'

    rewritten = NUM_RE.sub(rewrite_num, xml)
    if not clones:
        return rewritten

    # CT_Numbering wants every abstractNum before the first num.
    first_num = rewritten.index("<w:num ")
    return rewritten[:first_num] + "".join(clones) + rewritten[first_num:]


def patch_docx(path: Path) -> None:
    """Rewrites the numbering part of the .docx in place, keeping part order."""
    with zipfile.ZipFile(path) as zf:
        if NUMBERING_PART not in zf.namelist():
            return
        entries = [(info, zf.read(info.filename)) for info in zf.infolist()]

    with tempfile.NamedTemporaryFile(suffix=".docx", delete=False) as tmp:
        patched = Path(tmp.name)
    with zipfile.ZipFile(patched, "w", zipfile.ZIP_DEFLATED) as out:
        for info, data in entries:
            if info.filename == NUMBERING_PART:
                data = restart_numbering(data.decode("utf-8")).encode("utf-8")
            out.writestr(info, data)
    shutil.move(str(patched), str(path))


if __name__ == "__main__":
    patch_docx(Path(sys.argv[1]))

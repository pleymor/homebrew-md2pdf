#!/usr/bin/env python3
"""Reports how a .docx numbers its ordered lists.

Word continues a sequence across two lists whenever they point at the same
abstract numbering definition, so every numbered list needs its own definition
(with its own nsid) to start again at 1.

Usage: docx_lists.py <file.docx>

Prints:
  ordered_lists=<n>    numbering instances used by ordered lists in the body
  shared_abstract=<n>  ordered instances reusing another instance's definition
  shared_nsid=<n>      ordered instances reusing another instance's nsid
  restarts=<n>         ordered instances that explicitly restart at 1
"""
import re
import sys
import zipfile

NUM_RE = re.compile(r'<w:num w:numId="(\d+)"\s*>(.*?)</w:num>', re.S)
ABSTRACT_RE = re.compile(
    r'<w:abstractNum w:abstractNumId="(\d+)"\s*>(.*?)</w:abstractNum>', re.S
)
ABSTRACT_REF_RE = re.compile(r'<w:abstractNumId w:val="(\d+)"')
NSID_RE = re.compile(r'<w:nsid w:val="([^"]*)"')
FIRST_FMT_RE = re.compile(r'<w:numFmt w:val="([^"]*)"')
START_OVERRIDE_RE = re.compile(
    r'<w:lvlOverride w:ilvl="0"\s*>\s*<w:startOverride w:val="1"'
)
USED_NUMID_RE = re.compile(r'<w:numId w:val="(\d+)"')


def part(docx: str, name: str) -> str:
    """Reads one part of the .docx package, or "" when it is absent."""
    with zipfile.ZipFile(docx) as zf:
        if name not in zf.namelist():
            return ""
        return zf.read(name).decode("utf-8")


def count_duplicates(values: list) -> int:
    """Counts how many entries repeat a value already seen before them."""
    seen = set()
    duplicates = 0
    for value in values:
        if value in seen:
            duplicates += 1
        seen.add(value)
    return duplicates


def main() -> None:
    numbering = part(sys.argv[1], "word/numbering.xml")
    document = part(sys.argv[1], "word/document.xml")

    abstracts = {aid: body for aid, body in ABSTRACT_RE.findall(numbering)}
    used = set(USED_NUMID_RE.findall(document))

    ordered = []
    for num_id, body in NUM_RE.findall(numbering):
        if num_id not in used:
            continue
        ref = ABSTRACT_REF_RE.search(body)
        if not ref:
            continue
        definition = abstracts.get(ref.group(1), "")
        fmt = FIRST_FMT_RE.search(definition)
        if not fmt or fmt.group(1) == "bullet":
            continue
        nsid = NSID_RE.search(definition)
        ordered.append(
            {
                "abstract": ref.group(1),
                "nsid": nsid.group(1) if nsid else "",
                "restarts": bool(START_OVERRIDE_RE.search(body)),
            }
        )

    print(f"ordered_lists={len(ordered)}")
    print(f"shared_abstract={count_duplicates([o['abstract'] for o in ordered])}")
    print(f"shared_nsid={count_duplicates([o['nsid'] for o in ordered])}")
    print(f"restarts={sum(1 for o in ordered if o['restarts'])}")


if __name__ == "__main__":
    main()

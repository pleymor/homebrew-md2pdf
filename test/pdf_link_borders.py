#!/usr/bin/env python3
"""Report the link annotations of a PDF and how many draw a visible border.

Usage:
    pdf_link_borders.py FILE.pdf

Prints two integers on one line: the number of /Link annotations found, and how
many of them draw a visible box, i.e. whose /Border width is non-zero. Loading
hyperref without options gives every link a 1pt red box; `hidelinks` sets the
width to 0. The border colour /C stays in the dictionary either way and is
inert once the width is 0, so it is not a reliable signal on its own.
"""
import re
import sys
import zlib


def flatten(data):
    """Return the raw PDF bytes plus every stream it holds, inflated when possible.

    @param {bytes} data - Contents of the PDF file.
    @returns {bytes} The file and its decompressed streams, newline-joined, so
        annotation dictionaries can be searched whether or not they live inside
        a compressed object stream.
    """
    chunks = [data]
    for match in re.finditer(rb"stream\r?\n", data):
        end = data.find(b"endstream", match.end())
        if end < 0:
            continue
        try:
            chunks.append(zlib.decompress(data[match.end():end]))
        except zlib.error:
            pass
    return b"\n".join(chunks)


def link_borders(blob):
    """Count link annotations and those drawing a visible border.

    @param {bytes} blob - Flattened PDF bytes as returned by flatten().
    @returns {tuple[int, int]} (total links, links drawing a visible box). An
        annotation without a /Border entry counts as bordered: the PDF default
        is [0 0 1], a 1pt box.
    """
    annots = re.findall(rb"/Subtype\s*/Link(.{0,240}?)/Rect", blob, re.S)
    bordered = 0
    for annot in annots:
        width = re.search(rb"/Border\s*\[\s*[\d.]+\s+[\d.]+\s+([\d.]+)", annot)
        if width is None or float(width.group(1)) > 0:
            bordered += 1
    return len(annots), bordered


if __name__ == "__main__":
    with open(sys.argv[1], "rb") as handle:
        print("%d %d" % link_borders(flatten(handle.read())))

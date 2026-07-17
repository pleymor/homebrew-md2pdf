#!/usr/bin/env python3
"""Patches an unzipped pandoc default reference.docx in place.

- Sets every font to DejaVu Sans (styles.xml literals + theme fonts)
- Centers the Title, Subtitle, Author and Date paragraph styles
- Adds the TitleLogo and Alert* paragraph styles used by the Lua filters
- Sets default page margins to 2.5cm (1417 twips)
"""
import re
import sys
from pathlib import Path

ALERTS = {
    "AlertNote": ("2E74B5", "DEEAF6"),
    "AlertTip": ("538135", "E2EFD9"),
    "AlertImportant": ("7030A0", "EDE0F5"),
    "AlertWarning": ("BF8F00", "FFF2CC"),
    "AlertCaution": ("C00000", "FBDBDB"),
}

ALERT_STYLE_TEMPLATE = (
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="{sid}">'
    '<w:name w:val="{sid}"/><w:basedOn w:val="BodyText"/>'
    "<w:pPr>"
    '<w:pBdr><w:left w:val="single" w:sz="24" w:space="8" w:color="{border}"/></w:pBdr>'
    '<w:shd w:val="clear" w:color="auto" w:fill="{fill}"/>'
    '<w:spacing w:before="120" w:after="120"/>'
    '<w:ind w:left="240" w:right="240"/>'
    "</w:pPr>"
    "</w:style>"
)

TITLELOGO_STYLE = (
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="TitleLogo">'
    '<w:name w:val="TitleLogo"/><w:basedOn w:val="BodyText"/>'
    '<w:pPr><w:jc w:val="center"/><w:spacing w:before="3000" w:after="600"/></w:pPr>'
    "</w:style>"
)

MARGIN_TWIPS = "1417"  # 2.5 cm


def center_style(xml: str, style_id: str) -> str:
    """Adds centered justification to the given paragraph style."""
    block_re = re.compile(
        r'<w:style [^>]*w:styleId="' + style_id + r'".*?</w:style>', re.DOTALL
    )
    match = block_re.search(xml)
    if not match:
        return xml
    block = match.group(0)
    if "<w:jc " in block:
        new = block
    elif "<w:pPr>" in block:
        new = block.replace("<w:pPr>", '<w:pPr><w:jc w:val="center"/>', 1)
    elif "<w:rPr>" in block:
        new = block.replace("<w:rPr>", '<w:pPr><w:jc w:val="center"/></w:pPr><w:rPr>', 1)
    else:
        new = block.replace("</w:style>", '<w:pPr><w:jc w:val="center"/></w:pPr></w:style>', 1)
    return xml[: match.start()] + new + xml[match.end():]


def main() -> None:
    ref = Path(sys.argv[1])

    styles_path = ref / "word" / "styles.xml"
    xml = styles_path.read_text(encoding="utf-8")
    xml = re.sub(r'w:(ascii|hAnsi|cs|eastAsia)="[^"]*"', r'w:\1="DejaVu Sans"', xml)
    xml = re.sub(r'\s*w:(asciiTheme|hAnsiTheme|cstheme|eastAsiaTheme)="[^"]*"', "", xml)
    for sid in ("Title", "Subtitle", "Author", "Date"):
        xml = center_style(xml, sid)
    additions = TITLELOGO_STYLE + "".join(
        ALERT_STYLE_TEMPLATE.format(sid=sid, border=border, fill=fill)
        for sid, (border, fill) in ALERTS.items()
    )
    xml = xml.replace("</w:styles>", additions + "</w:styles>")
    styles_path.write_text(xml, encoding="utf-8")

    theme_path = ref / "word" / "theme" / "theme1.xml"
    if theme_path.exists():
        theme = theme_path.read_text(encoding="utf-8")
        theme = re.sub(r'(<a:latin typeface=")[^"]*(")', r"\1DejaVu Sans\2", theme)
        theme_path.write_text(theme, encoding="utf-8")

    doc_path = ref / "word" / "document.xml"
    doc = doc_path.read_text(encoding="utf-8")
    pg_mar = (
        f'<w:pgMar w:top="{MARGIN_TWIPS}" w:right="{MARGIN_TWIPS}" '
        f'w:bottom="{MARGIN_TWIPS}" w:left="{MARGIN_TWIPS}" '
        'w:header="720" w:footer="720" w:gutter="0"/>'
    )
    if "<w:pgMar" in doc:
        doc = re.sub(r"<w:pgMar[^/]*/>", pg_mar, doc)
    else:
        # pandoc's default reference has an empty sectPr: build one with
        # A4 page size and our margins
        doc = re.sub(
            r"<w:sectPr\s*/>",
            f'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>{pg_mar}</w:sectPr>',
            doc,
        )
    doc_path.write_text(doc, encoding="utf-8")


if __name__ == "__main__":
    main()

# Making `--font` work

Date: 2026-08-07

## Problem

`md2pdf` documents `-f, --font FONT` as setting the main font, and the README
even gives `--font "Arial"` as an example. The option worked in neither output
format, for two unrelated reasons.

### Word: the font was erased, not set

`scripts/patch_reference_styles.py` rewrote fonts with two regexes:

```python
xml = re.sub(r'w:(ascii|hAnsi|cs|eastAsia)="[^"]*"', r'w:\1="DejaVu Sans"', xml)
xml = re.sub(r'\s*w:(asciiTheme|hAnsiTheme|cstheme|eastAsiaTheme)="[^"]*"', "", xml)
```

Pandoc's `reference.docx` names no font directly. Every style binds one through
a theme reference:

```xml
<w:rFonts w:asciiTheme="minorHAnsi" w:eastAsiaTheme="minorHAnsi"
          w:hAnsiTheme="minorHAnsi" w:cstheme="minorBidi" />
```

So the first regex found nothing to replace — the only literal font name in the
whole file was `Consolas`, on the code style — and the second stripped the theme
references, leaving `<w:rFonts />`. An empty `rFonts` does not mean "inherit":
Word falls back to its built-in default, Times New Roman. Body text, `Title`,
`Heading1`–`Heading9` and `TOCHeading` were all affected.

`--font Arial` then did almost nothing, because `md2pdf.sh` patches the
reference doc by substituting the string `DejaVu Sans`, which survived only on
the code style.

The same regex was also unscoped: `w:eastAsia` is an attribute of `<w:lang>` as
well as of `<w:rFonts>`, so every language tag was rewritten to
`<w:lang w:eastAsia="DejaVu Sans" ...>` — a font name in a language attribute.

**Status: fixed.** `set_fonts()` now rewrites whole `<w:rFonts>` elements,
replacing theme references with a literal font instead of deleting them.

### PDF: the font was never passed on

`FONT` is parsed by `md2pdf.sh` and then used only on the docx branch.
`templates/config.tex` contains no `\setmainfont`, so every PDF renders in
XeLaTeX's default, Latin Modern Roman — a serif face, regardless of `--font`.

**Status: this spec.**

## Decisions

| Question | Decision | Rationale |
|---|---|---|
| CLI surface | Extend `-f, --font`, no new flag | The README already promises it works; a second flag would overlap ambiguously |
| Default PDF rendering | Unchanged (Latin Modern) | `mainfont` is emitted only when `--font` is given, so existing PDFs are untouched |
| Arial in the container | Liberation Sans | Metrically identical to Arial, free, ~2 MB; `ttf-mscorefonts-installer` is non-free, EULA-gated and downloads at build time |
| Font missing from the image | Silent substitution | The document still gets produced; the user judges the result |
| Code blocks | Monospace in both formats | Fixed-width alignment is the point of a code block |

## Design

### 1. `Dockerfile`

Add `fonts-liberation` to the `apt-get install` list. Only image change.

### 2. `templates/config.tex`

After `\usepackage{fontspec}`:

```latex
$if(mainfont)$
\IfFontExistsTF{$mainfont$}{\setmainfont{$mainfont$}}{}
$endif$
\setmonofont{DejaVu Sans Mono}[Scale=0.9]
```

- `$if(mainfont)$` keeps the default output byte-identical: without `--font`,
  no font command is emitted at all.
- `\IfFontExistsTF` implements the silent-substitution decision. Without it a
  missing font is not substituted by XeLaTeX — it aborts the run with
  `Font ... not loadable`. The empty else-branch leaves Latin Modern in place.
- `\setmonofont` is untouched, so code keeps its fixed width.

Probing an absent font makes TeX write a `missfont.log` next to the input file.
The run still succeeds, so `md2pdf.sh` deletes it along with its other
per-conversion temporaries rather than leaving it in the user's directory.

Headings, the table of contents, tables and the title page all inherit from
`\setmainfont`; `header.tex` and `titlepage.tex` need no change. The Symbola
emoji fallback keeps working — it restores `\f@family`, whatever that is.

### 3. `md2pdf.sh`

A lookup mapping the three metric-compatible Microsoft fonts onto the free
faces actually present in the image:

```bash
# Maps a Microsoft font onto its metrically identical free equivalent, the only
# ones shipped in the image. Echoes the input unchanged for anything else.
pdf_font_alias() {
    case "$1" in
        Arial)             echo "Liberation Sans" ;;
        "Times New Roman") echo "Liberation Serif" ;;
        "Courier New")     echo "Liberation Mono" ;;
        *)                 echo "$1" ;;
    esac
}
```

On the PDF branch, `-V mainfont="$(pdf_font_alias "$FONT")"` is added to the
pandoc call when — and only when — `--font` was actually passed. The argument
parser records that in a `FONT_SET` flag rather than comparing `$FONT` against
the default string, so `--font "DejaVu Sans"` means what it says and renders in
DejaVu Sans instead of silently falling through to Latin Modern.

The docx branch keeps writing the requested name verbatim, so a `.docx` asking
for `Arial` gets real Arial from the reader's own Word. The Liberation aliasing
is a PDF concern only.

### 4. `templates/reference.docx` — code style

`VerbatimChar` currently resolves to `DejaVu Sans`, a proportional face, because
`set_fonts()` rewrites every `<w:rFonts>` element including the code one. It
must resolve to `DejaVu Sans Mono` instead, and must not follow `--font`, to
match `\setmonofont` on the PDF side.

This creates a trap in `patch_reference_docx()` in `md2pdf.sh`, which currently
substitutes the bare string:

```bash
sed -i.bak "s/DejaVu Sans/$font/g" "$workdir/word/styles.xml"
```

Once `DejaVu Sans Mono` exists in the file, that turns it into `Arial Mono` — a
font that does not exist. The substitution must match the quoted attribute value
`"DejaVu Sans"` so the longer name cannot be hit.

## Testing

Written before the implementation, red first.

### `test/test_reference.sh`

Already added with the Word fix, 7 assertions: `docDefaults` names a real font,
`Title` and `Heading1`–`Heading3` resolve to DejaVu Sans, no dangling `Theme="`
attribute remains, and no font name appears inside a `<w:lang>` element.

To add: `VerbatimChar` resolves to `DejaVu Sans Mono`.

### `test/test_integration.sh`

Already added with the Word fix: `--font Arial` reaches `docDefaults` and
`Heading1`; the default docx names DejaVu Sans for body text.

To add:

| Case | Assertion |
|---|---|
| `--font "Arial"`, PDF | `pdffonts` lists `LiberationSans`, not `LMRoman` |
| `--font "Calibri"`, PDF | exit 0 and `pdffonts` lists `LMRoman` — silent fallback, no crash |
| no `--font`, PDF | `pdffonts` lists `LMRoman` — default rendering unchanged |
| `--font "DejaVu Sans"`, PDF | `pdffonts` lists `DejaVuSans` — an explicit request is honoured even when it names the default |
| `--font "Arial"`, PDF | code stays in `DejaVuSansMono` |
| `--font "Arial"`, docx | `styles.xml` contains no `Arial Mono` |

The `Calibri` case is the important one: it proves `\IfFontExistsTF` absorbs the
missing font instead of letting XeLaTeX abort.

## Documentation

The README lists `-f, --font FONT` with default `DejaVu Sans`, which is only
half true. It becomes:

- default `DejaVu Sans` for Word, `Latin Modern` for PDF;
- a note listing the fonts embedded in the image (DejaVu, Liberation) and
  stating that `Arial`, `Times New Roman` and `Courier New` render through their
  metrically identical Liberation equivalents;
- a note that any other font is silently replaced by the default in PDF, while
  Word resolves the name on the reader's machine.

## Out of scope

`--margin` has exactly the same defect as `--font` had: it applies to Word only,
while the PDF is pinned to `\usepackage[margin=0.75in]` in `config.tex`. Same
cause, same shape of fix, deliberately not addressed here. Worth doing next.

The docx default font is `DejaVu Sans`, which exists only inside the container —
neither macOS nor Windows ships it, so Word substitutes it on every reader's
machine. Changing that default is a separate decision, not a bug fix.

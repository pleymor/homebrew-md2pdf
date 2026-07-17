# Word (.docx) Output for md2pdf — Design

**Date:** 2026-07-17
**Status:** Approved

## Goal

Add a `--word` option to md2pdf that converts Markdown to `.docx` instead of PDF, with near feature parity: cover page with logo/author/date, clickable TOC, styled GitHub alerts, page breaks on `---`, auto-fit tables, Mermaid diagrams, and font/margin control.

## Approach

Single format-aware pipeline: one `md2pdf.sh`, one set of Lua filters that branch on pandoc's built-in `FORMAT` global, one new docx-only cover-page filter, and a committed `templates/reference.docx` for styling. No changes to the Docker image packages.

## CLI & script behavior

- New flag `-w, --word` enables Word mode.
- Extension inference: an output filename ending in `.docx` also enables Word mode.
- A single `FORMAT` variable (`pdf` | `docx`) drives all branching.
- Default output name: `${INPUT%.md}.${FORMAT}`.
- `--word` combined with an explicit `.pdf` output filename is an error with a clear message.
- All existing options work in both modes: `--margin`, `--font`, `--logo`, `--author`, `--date`, `--theme`.
- Help text, README, and Homebrew formula caveats updated with the new flag and examples.
- Success message says "DOCX created successfully" in Word mode.

## Pandoc/Docker invocation (Word mode)

- `MERMAID_FILTER_FORMAT=png` (instead of `pdf`) with `MERMAID_FILTER_SCALE` ~3 so diagrams stay crisp. `--theme` passes through unchanged.
- Dropped LaTeX-only args: `--pdf-engine=xelatex`, `--template config.tex`, `-H header.tex`, `-B titlepage.tex`, the generated `.titlepage-header.tex` include, and `--toc`/`--toc-depth` (replaced by a native Word TOC field, see below).
- Added: `--reference-doc=/templates/reference.docx` (or the runtime-patched copy).
- Kept: `--number-sections`, `--shift-heading-level-by=-1`, `-f markdown-implicit_figures`, mermaid-filter, and the Lua filter chain.
- Title-page data plumbing: in Word mode `--logo`/`--author`/`--date` pass as pandoc metadata (`-M titlelogo=/data/<logo> -M author=... -M date=...`) read by the cover-page filter. The logo-copy-into-input-dir logic is shared by both modes.

## Filters

Existing filters branch on pandoc's `FORMAT` global:

- **alerts.lua** — docx: each alert renders as a single-cell table with the alert title bolded, using per-type paragraph styles (`AlertNote`, `AlertTip`, `AlertImportant`, `AlertWarning`, `AlertCaution`) defined in `reference.docx` (shaded background + colored left border). LaTeX path unchanged.
- **horizontal-rule.lua** — docx: emits `pandoc.RawBlock('openxml', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')`. LaTeX path unchanged.
- **table-autofit.lua** — the proportional-width calculation is format-agnostic; in docx mode it sets the computed widths on the Table AST `colspecs` (honored by the docx writer) instead of emitting LaTeX column specs.
- **no-pagebreak.lua**, **toc-pagebreak.lua** — LaTeX-only; explicitly guarded to no-op in docx.

**New `titlepage-docx.lua`** (docx-only): reads `titlelogo`/`title`/`author`/`date` metadata and prepends, in order: centered logo image, title (Title style), author/date lines, page break, native Word TOC field (`TOC \o "1-3"` OOXML field), page break. Word prompts to update the field on first open (or F9), producing a real clickable, refreshable TOC matching `--toc-depth=3`.

## reference.docx

- Generated once from pandoc's default (`pandoc --print-default-data-file reference.docx`), customized, committed as a binary in `templates/`.
- Customizations: DejaVu Sans base font (matching the PDF default), heading styles, and the five `Alert*` paragraph styles.
- The existing `COPY templates/` in the Dockerfile picks it up.

## --font / --margin in Word mode

A docx is a zip: the script copies `reference.docx` to a temp file and patches it before the run —

- font names swapped in `word/styles.xml`;
- margins converted (cm → twips, 1 cm = 567 twips) into the section properties of `word/document.xml`.

The temp reference doc is cleaned up like the existing temp files.

## Error handling

- `--word` + explicit `.pdf` output → error.
- Unknown `--font` → Word's normal font substitution (no special handling).
- Missing input, missing logo, Docker down, pandoc failure with temp cleanup → existing paths, shared by both modes.

## Testing

New `test/` directory, two tiers:

1. **Unit-ish (no full conversion):** arg parsing and format inference via `md2pdf.sh --help` and bad-combo invocations (no Docker needed); each Lua filter tested by running pandoc inside the Docker image with `-t docx` / `-t latex` on small fixtures, asserting on output (TOC field present, page-break XML emitted, alert style names applied, colspecs widths set).
2. **Integration:** convert `example.md` with `--word --logo logo.png --author X`; assert the `.docx` exists, unzip it, grep `word/document.xml` for the TOC field, cover-page content, and embedded PNG diagrams.

## Out of scope

- PDF pipeline behavior changes (must remain byte-for-byte identical in flags and output).
- SVG diagram embedding (PNG chosen for Word compatibility).
- Custom Word themes beyond the committed reference.docx.

#!/bin/bash
# md2pdf - Convert Markdown to PDF with Mermaid support

# Determine script location (works with symlinks from Homebrew)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# For Homebrew installation, resources are in ../libexec
if [ -d "$SCRIPT_DIR/../libexec/templates" ]; then
    RESOURCE_DIR="$SCRIPT_DIR/../libexec"
else
    RESOURCE_DIR="$SCRIPT_DIR"
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Converts a margin like 2.5cm / 25mm / 1in to twips (empty if unsupported).
margin_to_twips() {
    local margin="$1"
    case "$margin" in
        *cm) awk "BEGIN {printf \"%d\", ${margin%cm} * 567}" ;;
        *mm) awk "BEGIN {printf \"%d\", ${margin%mm} * 56.7}" ;;
        *in) awk "BEGIN {printf \"%d\", ${margin%in} * 1440}" ;;
        *) echo "" ;;
    esac
}

# Copies the reference docx to $2 with font/margin overrides patched in.
patch_reference_docx() {
    local src="$1" dest="$2" font="$3" margin="$4"
    local workdir
    workdir=$(mktemp -d)
    unzip -q "$src" -d "$workdir"

    if [ "$font" != "DejaVu Sans" ]; then
        sed -i.bak "s/DejaVu Sans/$font/g" "$workdir/word/styles.xml"
        rm -f "$workdir/word/styles.xml.bak"
        if [ -f "$workdir/word/theme/theme1.xml" ]; then
            sed -i.bak "s/DejaVu Sans/$font/g" "$workdir/word/theme/theme1.xml"
            rm -f "$workdir/word/theme/theme1.xml.bak"
        fi
    fi

    if [ "$margin" != "2.5cm" ]; then
        local twips
        twips=$(margin_to_twips "$margin")
        if [ -n "$twips" ]; then
            sed -i.bak -E "s|<w:pgMar[^/]*/>|<w:pgMar w:top=\"$twips\" w:right=\"$twips\" w:bottom=\"$twips\" w:left=\"$twips\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>|" "$workdir/word/document.xml"
            rm -f "$workdir/word/document.xml.bak"
        else
            echo -e "${RED}Warning: unsupported margin unit '$margin' for Word output, keeping defaults${NC}"
        fi
    fi

    rm -f "$dest"
    (cd "$workdir" && zip -q -r -X "$dest" .)
    rm -rf "$workdir"
}

# Function to show usage
usage() {
    echo "Usage: ./md2pdf.sh input.md [output.pdf] [options]"
    echo ""
    echo "Options:"
    echo "  -m, --margin SIZE      Set margins (default: 2.5cm)"
    echo "  -f, --font FONT        Set main font (default: DejaVu Sans)"
    echo "  --logo FILE            Add logo to title page"
    echo "  --theme THEME          Set Mermaid theme (default: neutral)"
    echo "                         Options: default, forest, dark, neutral"
    echo "  --author AUTHOR        Set document author"
    echo "  --date DATE            Set document date"
    echo "  -w, --word             Output Word (.docx) instead of PDF"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./md2pdf.sh document.md"
    echo "  ./md2pdf.sh document.md output.pdf"
    echo "  ./md2pdf.sh document.md --word"
    echo "  ./md2pdf.sh document.md --logo logo.png --author 'John Doe'"
    echo "  ./md2pdf.sh document.md --theme dark"
    exit 1
}

# Parse arguments
INPUT=""
OUTPUT=""
MARGIN="2.5cm"
FONT="DejaVu Sans"
LOGO=""
AUTHOR=""
DATE=""
THEME="neutral"
WORD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -m|--margin)
            MARGIN="$2"
            shift 2
            ;;
        -f|--font)
            FONT="$2"
            shift 2
            ;;
        --logo)
            LOGO="$2"
            shift 2
            ;;
        --author)
            AUTHOR="$2"
            shift 2
            ;;
        --date)
            DATE="$2"
            shift 2
            ;;
        --theme)
            THEME="$2"
            shift 2
            ;;
        -w|--word)
            WORD=true
            shift
            ;;
        *)
            if [ -z "$INPUT" ]; then
                INPUT="$1"
            elif [ -z "$OUTPUT" ]; then
                OUTPUT="$1"
            fi
            shift
            ;;
    esac
done

# Validate input
if [ -z "$INPUT" ]; then
    echo -e "${RED}Error: No input file specified${NC}"
    usage
fi

if [ ! -f "$INPUT" ]; then
    echo -e "${RED}Error: Input file '$INPUT' not found${NC}"
    exit 1
fi

# Resolve output format
FORMAT="pdf"
if [ "$WORD" = true ]; then
    FORMAT="docx"
fi
if [[ "$OUTPUT" == *.docx ]]; then
    FORMAT="docx"
fi
if [ "$WORD" = true ] && [[ "$OUTPUT" == *.pdf ]]; then
    echo -e "${RED}Error: --word conflicts with .pdf output filename '$OUTPUT'${NC}"
    exit 1
fi

# Set output filename
if [ -z "$OUTPUT" ]; then
    OUTPUT="${INPUT%.md}.${FORMAT}"
fi

# Get absolute paths
INPUT_DIR=$(cd "$(dirname "$INPUT")" && pwd)
INPUT_FILE=$(basename "$INPUT")

# Handle output path - can be a full path or just a filename
OUTPUT_DIR=$(cd "$(dirname "$OUTPUT")" 2>/dev/null && pwd)
if [ -z "$OUTPUT_DIR" ]; then
    # Directory doesn't exist, use current directory
    OUTPUT_DIR=$(pwd)
fi
OUTPUT_FILE=$(basename "$OUTPUT")
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_FILE"

# Temporary output in input directory (for Docker mount)
TEMP_OUTPUT_FILE=".tmp_${OUTPUT_FILE}"

echo -e "${GREEN}Converting $INPUT to $OUTPUT_PATH...${NC}"

# Resolve container engine (override via MD2PDF_CONTAINER_ENGINE)
CONTAINER_ENGINE=""
if [ -n "${MD2PDF_CONTAINER_ENGINE:-}" ]; then
    if command -v "$MD2PDF_CONTAINER_ENGINE" > /dev/null 2>&1 \
       && "$MD2PDF_CONTAINER_ENGINE" info > /dev/null 2>&1; then
        CONTAINER_ENGINE="$MD2PDF_CONTAINER_ENGINE"
    else
        echo -e "${RED}Error: MD2PDF_CONTAINER_ENGINE='$MD2PDF_CONTAINER_ENGINE' is not available or not running${NC}"
        exit 1
    fi
else
    for engine in docker podman; do
        if command -v "$engine" > /dev/null 2>&1 && "$engine" info > /dev/null 2>&1; then
            CONTAINER_ENGINE="$engine"
            break
        fi
    done
fi

if [ -z "$CONTAINER_ENGINE" ]; then
    echo -e "${RED}Error: No working container engine found. Install and start Docker or Podman (or set MD2PDF_CONTAINER_ENGINE).${NC}"
    exit 1
fi

# Engine-specific run flags. Rootless Podman maps the container user into the
# host subuid range, so the bind-mounted /data is not writable by the in-image
# 'converter' user. The node:24-slim base already claims UID 1000, so 'converter'
# is UID/GID 1001; keep-id must target that so the invoking user maps onto it.
ENGINE_RUN_FLAGS=()
if [ "$(basename "$CONTAINER_ENGINE")" = "podman" ]; then
    ENGINE_RUN_FLAGS+=("--userns=keep-id:uid=1001,gid=1001")
fi

# Build container image
echo -e "${GREEN}Building image with $CONTAINER_ENGINE...${NC}"
"$CONTAINER_ENGINE" build -t md2pdf "$RESOURCE_DIR"

# Copy logo next to the input so the container can see it (both formats)
LOGO_COPIED=""
LOGO_FILE=""
if [ -n "$LOGO" ]; then
    LOGO_FILE=$(basename "$LOGO")
    if [ ! -f "$INPUT_DIR/$LOGO_FILE" ]; then
        if [ -f "$LOGO" ]; then
            cp "$LOGO" "$INPUT_DIR/$LOGO_FILE"
            LOGO_COPIED="$INPUT_DIR/$LOGO_FILE"
        else
            echo -e "${RED}Error: Logo file '$LOGO' not found${NC}"
            exit 1
        fi
    fi
fi

# Build title page header with LaTeX definitions (for logo override)
TITLEPAGE_HEADER=""
HEADER_INCLUDE=()
if [ "$FORMAT" = "pdf" ] && { [ -n "$LOGO" ] || [ -n "$AUTHOR" ] || [ -n "$DATE" ]; }; then
    TITLEPAGE_HEADER="$INPUT_DIR/.titlepage-header.tex"

    # Create header file with variable definitions
    echo "% Auto-generated title page variables" > "$TITLEPAGE_HEADER"

    if [ -n "$LOGO" ]; then
        echo "\\newcommand{\\titlelogo}{/data/$LOGO_FILE}" >> "$TITLEPAGE_HEADER"
    fi
    if [ -n "$AUTHOR" ]; then
        ESCAPED_AUTHOR=$(echo "$AUTHOR" | sed 's/\\/\\\\/g; s/&/\\&/g; s/%/\\%/g; s/\$/\\$/g; s/#/\\#/g; s/_/\\_/g; s/{/\\{/g; s/}/\\}/g')
        echo "\\newcommand{\\docauthor}{$ESCAPED_AUTHOR}" >> "$TITLEPAGE_HEADER"
    fi
    if [ -n "$DATE" ]; then
        ESCAPED_DATE=$(echo "$DATE" | sed 's/\\/\\\\/g; s/&/\\&/g; s/%/\\%/g; s/\$/\\$/g; s/#/\\#/g; s/_/\\_/g; s/{/\\{/g; s/}/\\}/g')
        echo "\\newcommand{\\docdate}{$ESCAPED_DATE}" >> "$TITLEPAGE_HEADER"
    fi

    HEADER_INCLUDE=(-H "/data/.titlepage-header.tex")
fi

# Run conversion
TEMP_REFERENCE=""
if [ "$FORMAT" = "docx" ]; then
    # Title page data goes in as metadata for filters/titlepage-docx.lua
    META_ARGS=()
    if [ -n "$LOGO" ]; then
        META_ARGS+=(-M "titlelogo=/data/$LOGO_FILE")
    fi
    if [ -n "$AUTHOR" ]; then
        META_ARGS+=(-M "author=$AUTHOR")
    fi
    if [ -n "$DATE" ]; then
        META_ARGS+=(-M "date=$DATE")
    fi

    # Styling comes from the reference doc; patch a copy for font/margin overrides
    REFERENCE_ARG="--reference-doc=/templates/reference.docx"
    if [ "$FONT" != "DejaVu Sans" ] || [ "$MARGIN" != "2.5cm" ]; then
        TEMP_REFERENCE="$INPUT_DIR/.tmp_reference.docx"
        patch_reference_docx "$RESOURCE_DIR/templates/reference.docx" "$TEMP_REFERENCE" "$FONT" "$MARGIN"
        REFERENCE_ARG="--reference-doc=/data/.tmp_reference.docx"
    fi

    "$CONTAINER_ENGINE" run --rm \
        "${ENGINE_RUN_FLAGS[@]}" \
        -v "$INPUT_DIR:/data" \
        --security-opt seccomp=unconfined \
        -e MERMAID_FILTER_WIDTH=1200 \
        -e MERMAID_FILTER_HEIGHT=800 \
        -e MERMAID_FILTER_FORMAT=png \
        -e MERMAID_FILTER_SCALE=3 \
        -e MERMAID_FILTER_THEME="$THEME" \
        -e MERMAID_FILTER_BACKGROUND=transparent \
        md2pdf \
        pandoc "/data/$INPUT_FILE" \
        -o "/data/$TEMP_OUTPUT_FILE" \
        --number-sections \
        --filter mermaid-filter \
        --lua-filter /filters/no-pagebreak.lua \
        --lua-filter /filters/alerts.lua \
        --lua-filter /filters/horizontal-rule.lua \
        --lua-filter /filters/table-autofit.lua \
        --lua-filter /filters/titlepage-docx.lua \
        "$REFERENCE_ARG" \
        --shift-heading-level-by=-1 \
        "${META_ARGS[@]}" \
        -f markdown-implicit_figures
else
    "$CONTAINER_ENGINE" run --rm \
        "${ENGINE_RUN_FLAGS[@]}" \
        -v "$INPUT_DIR:/data" \
        --security-opt seccomp=unconfined \
        -e MERMAID_FILTER_WIDTH=1200 \
        -e MERMAID_FILTER_HEIGHT=800 \
        -e MERMAID_FILTER_FORMAT=pdf \
        -e MERMAID_FILTER_THEME="$THEME" \
        -e MERMAID_FILTER_BACKGROUND=transparent \
        md2pdf \
        pandoc "/data/$INPUT_FILE" \
        -o "/data/$TEMP_OUTPUT_FILE" \
        --pdf-engine=xelatex \
        --toc \
        --toc-depth=3 \
        --number-sections \
        --filter mermaid-filter \
        --lua-filter /filters/no-pagebreak.lua \
        --lua-filter /filters/alerts.lua \
        --lua-filter /filters/horizontal-rule.lua \
        --lua-filter /filters/table-autofit.lua \
        --template /templates/config.tex \
        --shift-heading-level-by=-1 \
        -H /templates/header.tex \
        "${HEADER_INCLUDE[@]}" \
        -B /templates/titlepage.tex \
        -f markdown-implicit_figures
fi

CONVERSION_RESULT=$?

# Clean up temporary files
if [ -n "$TITLEPAGE_HEADER" ] && [ -f "$TITLEPAGE_HEADER" ]; then
    rm -f "$TITLEPAGE_HEADER"
fi
if [ -n "$LOGO_COPIED" ] && [ -f "$LOGO_COPIED" ]; then
    rm -f "$LOGO_COPIED"
fi
if [ -n "$TEMP_REFERENCE" ] && [ -f "$TEMP_REFERENCE" ]; then
    rm -f "$TEMP_REFERENCE"
fi

if [ $CONVERSION_RESULT -eq 0 ]; then
    # Move temp file to final destination
    mv "$INPUT_DIR/$TEMP_OUTPUT_FILE" "$OUTPUT_PATH"
    FORMAT_LABEL=$(echo "$FORMAT" | tr '[:lower:]' '[:upper:]')
    echo -e "${GREEN}✓ ${FORMAT_LABEL} created successfully: $OUTPUT_PATH${NC}"
else
    # Clean up temp file on failure
    rm -f "$INPUT_DIR/$TEMP_OUTPUT_FILE"
    echo -e "${RED}✗ Conversion failed${NC}"
    exit 1
fi

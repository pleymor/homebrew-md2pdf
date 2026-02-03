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

# Function to show usage
usage() {
    echo "Usage: ./md2pdf.sh input.md [output.pdf] [options]"
    echo ""
    echo "Options:"
    echo "  -m, --margin SIZE      Set margins (default: 2.5cm)"
    echo "  -f, --font FONT        Set main font (default: DejaVu Sans)"
    echo "  --logo FILE            Add logo to title page"
    echo "  --author AUTHOR        Set document author"
    echo "  --date DATE            Set document date"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./md2pdf.sh document.md"
    echo "  ./md2pdf.sh document.md output.pdf"
    echo "  ./md2pdf.sh document.md --logo logo.png --author 'John Doe'"
    exit 1
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi

# Parse arguments
INPUT=""
OUTPUT=""
MARGIN="2.5cm"
FONT="DejaVu Sans"
LOGO=""
AUTHOR=""
DATE=""

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

# Set output filename
if [ -z "$OUTPUT" ]; then
    OUTPUT="${INPUT%.md}.pdf"
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

# Build Docker image if it doesn't exist
if [[ "$(docker images -q md2pdf 2> /dev/null)" == "" ]]; then
    echo -e "${GREEN}Building Docker image (first time only)...${NC}"
    docker build -t md2pdf "$RESOURCE_DIR"
fi

# Build title page header with LaTeX definitions (for logo override)
TITLEPAGE_HEADER=""
LOGO_COPIED=""
HEADER_INCLUDE=()
if [ -n "$LOGO" ] || [ -n "$AUTHOR" ] || [ -n "$DATE" ]; then
    TITLEPAGE_HEADER="$INPUT_DIR/.titlepage-header.tex"

    # Create header file with variable definitions
    echo "% Auto-generated title page variables" > "$TITLEPAGE_HEADER"

    if [ -n "$LOGO" ]; then
        LOGO_FILE=$(basename "$LOGO")
        # If logo is not in input directory, copy it there
        if [ ! -f "$INPUT_DIR/$LOGO_FILE" ]; then
            if [ -f "$LOGO" ]; then
                cp "$LOGO" "$INPUT_DIR/$LOGO_FILE"
                LOGO_COPIED="$INPUT_DIR/$LOGO_FILE"
            else
                echo -e "${RED}Error: Logo file '$LOGO' not found${NC}"
                exit 1
            fi
        fi
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
docker run --rm \
    -v "$INPUT_DIR:/data" \
    --security-opt seccomp=unconfined \
    -e MERMAID_FILTER_WIDTH=1200 \
    -e MERMAID_FILTER_HEIGHT=800 \
    -e MERMAID_FILTER_FORMAT=pdf \
    -e MERMAID_FILTER_THEME=forest \
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
    --template /templates/config.tex \
    --shift-heading-level-by=-1 \
    -H /templates/header.tex \
    "${HEADER_INCLUDE[@]}" \
    -B /templates/titlepage.tex \
    -f markdown-implicit_figures

CONVERSION_RESULT=$?

# Clean up temporary files
if [ -n "$TITLEPAGE_HEADER" ] && [ -f "$TITLEPAGE_HEADER" ]; then
    rm -f "$TITLEPAGE_HEADER"
fi
if [ -n "$LOGO_COPIED" ] && [ -f "$LOGO_COPIED" ]; then
    rm -f "$LOGO_COPIED"
fi

if [ $CONVERSION_RESULT -eq 0 ]; then
    # Move temp file to final destination
    mv "$INPUT_DIR/$TEMP_OUTPUT_FILE" "$OUTPUT_PATH"
    echo -e "${GREEN}✓ PDF created successfully: $OUTPUT_PATH${NC}"
else
    # Clean up temp file on failure
    rm -f "$INPUT_DIR/$TEMP_OUTPUT_FILE"
    echo -e "${RED}✗ Conversion failed${NC}"
    exit 1
fi

#!/bin/bash
# md2pdf - Convert Markdown to PDF with Mermaid support

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to show usage
usage() {
    echo "Usage: ./md2pdf.sh input.md [output.pdf] [options]"
    echo ""
    echo "Options:"
    echo "  -m, --margin SIZE    Set margins (default: 2.5cm)"
    echo "  -f, --font FONT      Set main font (default: DejaVu Sans)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./md2pdf.sh document.md"
    echo "  ./md2pdf.sh document.md output.pdf"
    echo "  ./md2pdf.sh document.md output.pdf --margin 3cm"
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
OUTPUT_FILE=$(basename "$OUTPUT")

echo -e "${GREEN}Converting $INPUT to $OUTPUT...${NC}"

# Build Docker image if it doesn't exist
if [[ "$(docker images -q md2pdf 2> /dev/null)" == "" ]]; then
    echo -e "${GREEN}Building Docker image (first time only)...${NC}"
    docker build -t md2pdf - < Dockerfile
fi

# Run conversion
docker run --rm \
    -v "$INPUT_DIR:/data" \
    --security-opt seccomp=unconfined \
    -e MERMAID_FILTER_WIDTH=800 \
    -e MERMAID_FILTER_HEIGHT=1000 \
    -e MERMAID_FILTER_FORMAT=pdf \
    md2pdf \
    pandoc "/data/$INPUT_FILE" \
    -o "/data/$OUTPUT_FILE" \
    --pdf-engine=xelatex \
    --toc \
    --toc-depth=3 \
    --number-sections \
    --filter mermaid-filter \
    --lua-filter /filters/alerts.lua \
    -H /templates/header.tex \
    -V geometry:margin="$MARGIN"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PDF created successfully: $OUTPUT${NC}"
else
    echo -e "${RED}✗ Conversion failed${NC}"
    exit 1
fi

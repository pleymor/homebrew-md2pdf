#!/bin/bash
# md2pdf installer - downloads md2pdf and puts it on your PATH.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/pleymor/homebrew-md2pdf/main/install.sh | bash
#
# Environment variables:
#   MD2PDF_VERSION   Release tag to install (default: v1.3.0)
#   MD2PDF_PREFIX    Directory to install files into (default: ~/.local/share/md2pdf)
#   MD2PDF_BIN       Directory for the md2pdf symlink (default: ~/.local/bin)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

REPO="pleymor/homebrew-md2pdf"
VERSION="${MD2PDF_VERSION:-v1.3.0}"
PREFIX="${MD2PDF_PREFIX:-$HOME/.local/share/md2pdf}"
BIN_DIR="${MD2PDF_BIN:-$HOME/.local/bin}"

# Preflight checks
for cmd in curl tar; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo -e "${RED}Error: '$cmd' is required but not installed${NC}" >&2
        exit 1
    fi
done

if ! command -v docker > /dev/null 2>&1 && ! command -v podman > /dev/null 2>&1; then
    echo -e "${YELLOW}Warning: no container engine found. md2pdf needs Docker or Podman at runtime to convert files.${NC}" >&2
fi

# Download and extract the release tarball
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz"
echo -e "${GREEN}Downloading md2pdf ${VERSION}...${NC}"
if ! curl -fsSL "$TARBALL_URL" | tar xz -C "$TMP_DIR"; then
    echo -e "${RED}Error: failed to download or extract ${TARBALL_URL}${NC}" >&2
    echo -e "${RED}Check that the version '${VERSION}' exists.${NC}" >&2
    exit 1
fi

# Tarball extracts to homebrew-md2pdf-<version-without-v>/
SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$SRC_DIR" ] || [ ! -f "$SRC_DIR/md2pdf.sh" ]; then
    echo -e "${RED}Error: unexpected archive layout (md2pdf.sh not found)${NC}" >&2
    exit 1
fi

# Install files
echo -e "${GREEN}Installing to ${PREFIX}...${NC}"
mkdir -p "$PREFIX"
cp "$SRC_DIR/md2pdf.sh" "$SRC_DIR/Dockerfile" "$PREFIX/"
cp -R "$SRC_DIR/templates" "$SRC_DIR/filters" "$PREFIX/"
chmod +x "$PREFIX/md2pdf.sh"

# Symlink onto PATH
mkdir -p "$BIN_DIR"
ln -sf "$PREFIX/md2pdf.sh" "$BIN_DIR/md2pdf"

echo -e "${GREEN}md2pdf ${VERSION} installed.${NC}"

# PATH check
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo -e "${YELLOW}Note: $BIN_DIR is not on your PATH.${NC}"
        echo -e "${YELLOW}Add this to your shell profile (~/.bashrc, ~/.zshrc):${NC}"
        echo "    export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

echo ""
echo "Quick start: md2pdf example.md"

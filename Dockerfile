FROM node:18-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    pandoc \
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-latex-recommended \
    texlive-latex-extra \
    fonts-dejavu \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js dependencies
RUN npm install -g \
    @mermaid-js/mermaid-cli \
    mermaid-filter

# Set Puppeteer to use system Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

# Create non-root user (required for Chromium)
RUN useradd -m -s /bin/bash converter && \
    mkdir -p /data /filters && \
    chown converter:converter /data /filters

# Copy Lua filters
COPY filters/ /filters/

# Create working directory
WORKDIR /data

# Switch to non-root user
USER converter

# Default command
CMD ["bash"]

#!/bin/bash
# ============================================================
# JavaScript File Analyzer
# Extracts endpoints, secrets, and links from JS files
# Usage: ./js-analyze.sh <target_url_or_domain>
# ============================================================

set -euo pipefail

TARGET="${1:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
OUTPUT_DIR="/workspace/output/js_${DOMAIN}_${TIMESTAMP}"

if [ -z "$TARGET" ]; then
    echo "[!] Usage: $0 <target_url_or_domain>"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"/{js-files,endpoints,secrets}

echo "[*] JavaScript Analysis for: $TARGET"

# Step 1: Collect JS URLs with katana
if command -v katana &>/dev/null; then
    echo "[1] Discovering JS files with katana..."
    katana -u "$TARGET" \
        -jc \
        -d 3 \
        -c 30 \
        -extension-match js \
        -o "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || true
fi

# Also get from gau/wayback
if command -v gau &>/dev/null; then
    echo "[2] Getting JS files from wayback..."
    echo "$DOMAIN" | gau \
        --providers wayback,commoncrawl \
        2>/dev/null | grep -E "\.js(\?|$)" >> "$OUTPUT_DIR/js-files/js-urls.txt" || true
fi

# Sort and dedup
sort -u -o "$OUTPUT_DIR/js-files/js-urls.txt" "$OUTPUT_DIR/js-files/js-urls.txt"
JS_COUNT=$(wc -l < "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || echo 0)
echo "[*] Found $JS_COUNT unique JS files"

# Step 2: Download and analyze JS files
echo "[3] Downloading and analyzing JS files..."
while IFS= read -r js_url; do
    echo "  Fetching: $js_url"
    curl -s --max-time 10 -L "$js_url" >> "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null || true
done < "$OUTPUT_DIR/js-files/js-urls.txt"

# Step 3: Extract patterns from JS
if [ -f "$OUTPUT_DIR/js-files/combined.js" ]; then
    # API endpoints
    grep -oE '("|'"'"')(/api/[^"'"'"']+)("|'"'"')' "$OUTPUT_DIR/js-files/combined.js" | \
        tr -d '"'"'" | sort -u > "$OUTPUT_DIR/endpoints/api-endpoints.txt" 2>/dev/null || true
    
    # Paths and routes
    grep -oE '("|'"'"')(/[a-zA-Z0-9_/-]{3,})("|'"'"')' "$OUTPUT_DIR/js-files/combined.js" | \
        tr -d '"'"'" | sort -u > "$OUTPUT_DIR/endpoints/paths.txt" 2>/dev/null || true
    
    # AWS/secrets patterns
    grep -oE 'AKIA[0-9A-Z]{16}' "$OUTPUT_DIR/js-files/combined.js" > "$OUTPUT_DIR/secrets/aws-keys.txt" 2>/dev/null || true
    grep -oE '"[a-zA-Z0-9_-]{32,}"' "$OUTPUT_DIR/js-files/combined.js" | \
        head -100 > "$OUTPUT_DIR/secrets/potential-tokens.txt" 2>/dev/null || true
fi

echo "[✓] Analysis complete. Output: $OUTPUT_DIR"

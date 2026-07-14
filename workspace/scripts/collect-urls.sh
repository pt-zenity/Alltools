#!/bin/bash
# ============================================================
# URL Collector Script - All sources combined
# Usage: ./collect-urls.sh <domain> [options]
# ============================================================

set -euo pipefail

DOMAIN="${1:-}"
THREADS="${2:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="/workspace/output/urls_${DOMAIN}_${TIMESTAMP}"

if [ -z "$DOMAIN" ]; then
    echo "[!] Usage: $0 <domain> [threads]"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "[*] Collecting URLs for: $DOMAIN"
echo "[*] Threads: $THREADS"
echo "[*] Output: $OUTPUT_DIR"
echo ""

# Run all collectors in parallel
{
    # gau
    if command -v gau &>/dev/null; then
        echo "[gau] Starting..."
        echo "$DOMAIN" | gau \
            --threads "$THREADS" \
            --providers wayback,commoncrawl,otx,urlscan \
            --blacklist png,jpg,gif,jpeg,webp,svg,ico,css,woff,ttf \
            > "$OUTPUT_DIR/gau.txt" 2>/dev/null
        GAU_C=$(wc -l < "$OUTPUT_DIR/gau.txt")
        echo "[gau] Found: $GAU_C URLs"
    fi
} &

{
    # waybackurls
    if command -v waybackurls &>/dev/null; then
        echo "[waybackurls] Starting..."
        echo "$DOMAIN" | waybackurls > "$OUTPUT_DIR/wayback.txt" 2>/dev/null
        WB_C=$(wc -l < "$OUTPUT_DIR/wayback.txt")
        echo "[waybackurls] Found: $WB_C URLs"
    fi
} &

{
    # waymore
    if command -v waymore &>/dev/null; then
        echo "[waymore] Starting..."
        waymore -i "$DOMAIN" -mode U -oU "$OUTPUT_DIR/waymore.txt" 2>/dev/null || true
        WM_C=$(wc -l < "$OUTPUT_DIR/waymore.txt" 2>/dev/null || echo 0)
        echo "[waymore] Found: $WM_C URLs"
    fi
} &

wait

# Combine and deduplicate
echo ""
echo "[*] Combining and deduplicating..."
cat "$OUTPUT_DIR/"*.txt 2>/dev/null | \
    grep -E "^https?://${DOMAIN}" | \
    sort -u > "$OUTPUT_DIR/all-urls.txt"

TOTAL=$(wc -l < "$OUTPUT_DIR/all-urls.txt")
echo "[✓] Total unique URLs: $TOTAL"
echo "[✓] Output: $OUTPUT_DIR/all-urls.txt"

# Optionally deduplicate with uro
if command -v uro &>/dev/null; then
    uro < "$OUTPUT_DIR/all-urls.txt" > "$OUTPUT_DIR/all-urls-dedup.txt"
    URO_C=$(wc -l < "$OUTPUT_DIR/all-urls-dedup.txt")
    echo "[✓] After uro dedup: $URO_C URLs"
fi

#!/bin/bash
# ============================================================
# URL Collector Script - All sources combined
# Usage: ./collect-urls.sh <domain> [threads]
# ============================================================

# NOTE: -e removed — individual tool failures must not abort the scan
set -uo pipefail

DOMAIN="${1:-}"
THREADS="${2:-${THREADS:-30}}"
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

# ── gau ──────────────────────────────────────────────────────
if command -v gau &>/dev/null; then
    echo "[gau][$(date +%H:%M:%S)] Starting..."
    # stdbuf forces line-buffered output so every line streams live
    echo "$DOMAIN" | stdbuf -oL gau \
        --threads "$THREADS" \
        --providers wayback,commoncrawl,otx,urlscan \
        --blacklist png,jpg,gif,jpeg,webp,svg,ico,css,woff,ttf \
        2>&1 | tee "$OUTPUT_DIR/gau_live.log" | \
        grep -E "^https?://" > "$OUTPUT_DIR/gau.txt" || true
    GAU_C=$(wc -l < "$OUTPUT_DIR/gau.txt" 2>/dev/null || echo 0)
    echo "[gau][$(date +%H:%M:%S)] Found: $GAU_C URLs"
else
    echo "[WARN] gau not found, skipping."
    GAU_C=0
fi

# ── waybackurls ───────────────────────────────────────────────
if command -v waybackurls &>/dev/null; then
    echo "[waybackurls][$(date +%H:%M:%S)] Starting..."
    echo "$DOMAIN" | stdbuf -oL waybackurls 2>&1 | tee "$OUTPUT_DIR/wayback_live.log" | \
        grep -E "^https?://" > "$OUTPUT_DIR/wayback.txt" || true
    WB_C=$(wc -l < "$OUTPUT_DIR/wayback.txt" 2>/dev/null || echo 0)
    echo "[waybackurls][$(date +%H:%M:%S)] Found: $WB_C URLs"
else
    echo "[WARN] waybackurls not found, skipping."
    WB_C=0
fi

# ── waymore ───────────────────────────────────────────────────
if command -v waymore &>/dev/null; then
    echo "[waymore][$(date +%H:%M:%S)] Starting..."
    stdbuf -oL waymore -i "$DOMAIN" -mode U -oU "$OUTPUT_DIR/waymore.txt" -p "$THREADS" 2>&1 | \
        tee "$OUTPUT_DIR/waymore_live.log" || true
    WM_C=$(wc -l < "$OUTPUT_DIR/waymore.txt" 2>/dev/null || echo 0)
    echo "[waymore][$(date +%H:%M:%S)] Found: $WM_C URLs"
else
    echo "[WARN] waymore not found, skipping."
    WM_C=0
fi

# ── Combine and deduplicate ───────────────────────────────────
echo ""
echo "[*] Combining and deduplicating..."
cat "$OUTPUT_DIR/"*.txt 2>/dev/null | \
    grep -E "^https?://${DOMAIN}" | \
    sort -u > "$OUTPUT_DIR/all-urls.txt" || true

TOTAL=$(wc -l < "$OUTPUT_DIR/all-urls.txt" 2>/dev/null || echo 0)
echo "[✓] Total unique URLs: $TOTAL"
echo "[✓] Output: $OUTPUT_DIR/all-urls.txt"

# ── Optional: deduplicate with uro ────────────────────────────
if command -v uro &>/dev/null; then
    echo "[uro][$(date +%H:%M:%S)] Deduplicating with uro..."
    uro < "$OUTPUT_DIR/all-urls.txt" > "$OUTPUT_DIR/all-urls-dedup.txt" 2>/dev/null || true
    URO_C=$(wc -l < "$OUTPUT_DIR/all-urls-dedup.txt" 2>/dev/null || echo 0)
    echo "[✓] After uro dedup: $URO_C URLs"
fi

echo ""
echo "[✓] Collection complete! Output dir: $OUTPUT_DIR"

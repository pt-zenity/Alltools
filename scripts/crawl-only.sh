#!/bin/bash
# ============================================================
# Crawl Only Script - Using katana + gospider
# Usage: ./crawl-only.sh <target_url> [depth] [threads]
# ============================================================

set -euo pipefail

TARGET="${1:-}"
DEPTH="${2:-3}"
THREADS="${3:-50}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
OUTPUT_DIR="/workspace/output/crawl_${DOMAIN}_${TIMESTAMP}"

if [ -z "$TARGET" ]; then
    echo "[!] Usage: $0 <target_url> [depth] [threads]"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"/{katana,gospider,combined}

echo "[*] Crawling: $TARGET"
echo "[*] Depth: $DEPTH | Threads: $THREADS"
echo ""

# katana - advanced crawling
if command -v katana &>/dev/null; then
    echo "[katana] Starting crawler..."
    katana \
        -u "$TARGET" \
        -d "$DEPTH" \
        -c "$THREADS" \
        -jc \
        -kf all \
        -aff \
        -fx \
        -xhr \
        -H "User-Agent: Mozilla/5.0 (compatible; CrawlerToolkit/2026)" \
        -rl 150 \
        -timeout 15 \
        -retry 2 \
        -o "$OUTPUT_DIR/katana/urls.txt" \
        -jsonl "$OUTPUT_DIR/katana/results.jsonl" \
        2>&1
    
    KATANA_C=$(wc -l < "$OUTPUT_DIR/katana/urls.txt" 2>/dev/null || echo 0)
    echo "[katana] Found: $KATANA_C URLs"
fi

# gospider - additional spider
if command -v gospider &>/dev/null; then
    echo "[gospider] Starting spider..."
    gospider \
        -s "$TARGET" \
        -o "$OUTPUT_DIR/gospider/" \
        -c "$THREADS" \
        -d "$DEPTH" \
        --js \
        --sitemap \
        --robots \
        --other-source \
        --include-subs \
        -q \
        2>&1
    
    GOSPIDER_C=$(cat "$OUTPUT_DIR/gospider/"* 2>/dev/null | wc -l || echo 0)
    echo "[gospider] Found: $GOSPIDER_C entries"
fi

# xnLinkFinder
if command -v xnLinkFinder &>/dev/null; then
    echo "[xnLinkFinder] Extracting links..."
    xnLinkFinder \
        -i "$TARGET" \
        -op "$OUTPUT_DIR/xnlink.txt" \
        -sp "$TARGET" \
        -sf "$DOMAIN" \
        -d "$DEPTH" \
        2>&1 || true
    
    XNLINK_C=$(wc -l < "$OUTPUT_DIR/xnlink.txt" 2>/dev/null || echo 0)
    echo "[xnLinkFinder] Found: $XNLINK_C links"
fi

# Combine results
echo ""
echo "[*] Combining results..."
cat \
    "$OUTPUT_DIR/katana/urls.txt" \
    "$OUTPUT_DIR/gospider/"*.txt \
    "$OUTPUT_DIR/xnlink.txt" \
    2>/dev/null | \
    grep -E "^https?://" | \
    sort -u > "$OUTPUT_DIR/combined/all-urls.txt"

TOTAL=$(wc -l < "$OUTPUT_DIR/combined/all-urls.txt")
echo "[✓] Total unique URLs: $TOTAL"

# Probe with httpx
if command -v httpx &>/dev/null; then
    echo ""
    echo "[httpx] Probing alive URLs..."
    httpx \
        -l "$OUTPUT_DIR/combined/all-urls.txt" \
        -o "$OUTPUT_DIR/combined/alive-urls.txt" \
        -sc -title -ct -server \
        -threads "$THREADS" \
        -timeout 10 \
        2>&1
    
    ALIVE_C=$(wc -l < "$OUTPUT_DIR/combined/alive-urls.txt" 2>/dev/null || echo 0)
    echo "[✓] Alive URLs: $ALIVE_C"
fi

echo ""
echo "[✓] Crawl complete! Output: $OUTPUT_DIR"

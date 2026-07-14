#!/bin/bash
# ============================================================
# Crawl Only Script - Using katana + gospider
# Usage: ./crawl-only.sh <target_url> [depth] [threads]
# ============================================================

# NOTE: -e removed — individual tool failures must not abort the scan
set -uo pipefail

TARGET="${1:-}"
DEPTH="${2:-${DEPTH:-3}}"
THREADS="${3:-${THREADS:-50}}"
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
echo "[*] Output: $OUTPUT_DIR"
echo ""

# ── helper: stream a tool live, tee to per-tool log ──────────
run_tool() {
    local label="$1"
    local logfile="$2"
    shift 2
    [ "${1:-}" = "--" ] && shift
    echo "[$(date +%H:%M:%S)][${label}] starting..."
    stdbuf -oL "$@" 2>&1 | tee -a "$logfile" || \
        echo "[WARN][$(date +%H:%M:%S)][${label}] exited with non-zero status (continuing)"
    echo "[$(date +%H:%M:%S)][${label}] done."
}

# ── katana - advanced crawling ────────────────────────────────
if command -v katana &>/dev/null; then
    echo "[katana] Starting crawler..."
    run_tool "katana" "$OUTPUT_DIR/katana/tool.log" \
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
            -jsonl "$OUTPUT_DIR/katana/results.jsonl"
    KATANA_C=$(wc -l < "$OUTPUT_DIR/katana/urls.txt" 2>/dev/null || echo 0)
    echo "[katana] Found: $KATANA_C URLs"
else
    echo "[WARN] katana not found, skipping."
    KATANA_C=0
fi

# ── gospider - additional spider ─────────────────────────────
if command -v gospider &>/dev/null; then
    echo "[gospider] Starting spider..."
    run_tool "gospider" "$OUTPUT_DIR/gospider/tool.log" \
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
            -q
    GOSPIDER_C=$(cat "$OUTPUT_DIR/gospider/"* 2>/dev/null | wc -l || echo 0)
    echo "[gospider] Found: $GOSPIDER_C entries"
else
    echo "[WARN] gospider not found, skipping."
    GOSPIDER_C=0
fi

# ── xnLinkFinder ─────────────────────────────────────────────
if command -v xnLinkFinder &>/dev/null; then
    echo "[xnLinkFinder] Extracting links..."
    run_tool "xnLinkFinder" "$OUTPUT_DIR/xnlink_tool.log" \
        xnLinkFinder \
            -i "$TARGET" \
            -op "$OUTPUT_DIR/xnlink.txt" \
            -sp "$TARGET" \
            -sf "$DOMAIN" \
            -d "$DEPTH"
    XNLINK_C=$(wc -l < "$OUTPUT_DIR/xnlink.txt" 2>/dev/null || echo 0)
    echo "[xnLinkFinder] Found: $XNLINK_C links"
else
    echo "[WARN] xnLinkFinder not found, skipping."
    XNLINK_C=0
fi

# ── Combine results ───────────────────────────────────────────
echo ""
echo "[*] Combining results..."
cat \
    "$OUTPUT_DIR/katana/urls.txt" \
    "$OUTPUT_DIR/gospider/"*.txt \
    "$OUTPUT_DIR/xnlink.txt" \
    2>/dev/null | \
    grep -E "^https?://" | \
    sort -u > "$OUTPUT_DIR/combined/all-urls.txt" || true

TOTAL=$(wc -l < "$OUTPUT_DIR/combined/all-urls.txt" 2>/dev/null || echo 0)
echo "[✓] Total unique URLs: $TOTAL"

# ── Probe with httpx ──────────────────────────────────────────
if command -v httpx &>/dev/null; then
    echo ""
    echo "[httpx] Probing alive URLs..."
    run_tool "httpx" "$OUTPUT_DIR/httpx_tool.log" \
        httpx \
            -l "$OUTPUT_DIR/combined/all-urls.txt" \
            -o "$OUTPUT_DIR/combined/alive-urls.txt" \
            -sc -title -ct -server \
            -threads "$THREADS" \
            -timeout 10
    ALIVE_C=$(wc -l < "$OUTPUT_DIR/combined/alive-urls.txt" 2>/dev/null || echo 0)
    echo "[✓] Alive URLs: $ALIVE_C"
else
    echo "[WARN] httpx not found, skipping probe."
fi

echo ""
echo "[✓] Crawl complete! Output: $OUTPUT_DIR"

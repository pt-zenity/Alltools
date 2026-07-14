#!/bin/bash
# ============================================================
# Crawl Only Script - Using katana + gospider + xnLinkFinder
# Usage: ./crawl-only.sh <target_url> [depth] [threads]
# ============================================================

# NOTE: -e removed — individual tool failures must not abort the scan
set -uo pipefail

# ── Colors ──────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

TARGET="${1:-}"
DEPTH="${2:-${DEPTH:-3}}"
THREADS="${3:-${THREADS:-50}}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||' | sed 's|:.*||')
OUTPUT_DIR="/workspace/output/crawl_${DOMAIN}_${TIMESTAMP}"
SCAN_START=$(date +%s)

if [ -z "$TARGET" ]; then
    echo -e "${YELLOW}[!] Usage: $0 <target_url> [depth] [threads]${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"/{katana,gospider,combined}

# Pre-create output files so wc -l never fails
touch "$OUTPUT_DIR/katana/urls.txt"
touch "$OUTPUT_DIR/katana/results.jsonl"
touch "$OUTPUT_DIR/gospider/combined.txt"
touch "$OUTPUT_DIR/xnlink.txt"
touch "$OUTPUT_DIR/combined/all-urls.txt"
touch "$OUTPUT_DIR/combined/alive-urls.txt"

# ── Helpers ─────────────────────────────────────────────────
ok() {
    local label="$1" count="$2" elapsed="$3"
    echo -e "  ${GREEN}[✓]${NC} ${BOLD}${label}${NC} ${DIM}→${NC} ${CYAN}${count} items${NC} ${DIM}(${elapsed}s)${NC}"
}

skip() {
    echo -e "  ${DIM}[–] $1 — not installed, skipping${NC}"
}

elapsed_since() { echo $(( $(date +%s) - $1 )); }

run_tool() {
    local label="$1"
    local logfile="$2"
    shift 2
    [ "${1:-}" = "--" ] && shift
    echo -e "${DIM}  │  ${CYAN}[$(date +%H:%M:%S)][${label}]${NC} ${DIM}starting...${NC}"
    stdbuf -oL "$@" 2>&1 | tee -a "$logfile" | tee -a "$OUTPUT_DIR/scan.log" || \
        echo -e "${YELLOW}  [WARN][$(date +%H:%M:%S)] ${label} exited non-zero (continuing)${NC}" \
            | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${DIM}  │  ${CYAN}[$(date +%H:%M:%S)][${label}]${NC} ${DIM}done.${NC}"
}

# ── Header ──────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║          🕷️  CRAWL ONLY SCAN 2026                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${DIM}Target  :${NC} ${WHITE}$TARGET${NC}"
echo -e "  ${DIM}Domain  :${NC} ${WHITE}$DOMAIN${NC}"
echo -e "  ${DIM}Depth   :${NC} ${WHITE}$DEPTH${NC}"
echo -e "  ${DIM}Threads :${NC} ${WHITE}$THREADS${NC}"
echo -e "  ${DIM}Output  :${NC} ${CYAN}$OUTPUT_DIR${NC}"
echo ""

# ── katana - advanced crawling ────────────────────────────────
STEP_START=$(date +%s)
if command -v katana &>/dev/null; then
    echo -e "${BOLD}${WHITE}  ┌─[1/4] katana${NC} ${DIM}— active crawling with JS execution${NC}"
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
    ok "katana" "$KATANA_C" "$(elapsed_since $STEP_START)"
else
    skip "katana [1/4]"
    KATANA_C=0
fi

# ── gospider - additional spider ─────────────────────────────
STEP_START=$(date +%s)
if command -v gospider &>/dev/null; then
    echo -e "${BOLD}${WHITE}  ┌─[2/4] gospider${NC} ${DIM}— spider with sitemap + robots + JS${NC}"
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
    # Merge all gospider output into one file (extract URLs only)
    cat "$OUTPUT_DIR/gospider/"* 2>/dev/null | \
        grep -oE "https?://[^ ]+" > "$OUTPUT_DIR/gospider/combined.txt" || true
    GOSPIDER_C=$(wc -l < "$OUTPUT_DIR/gospider/combined.txt" 2>/dev/null || echo 0)
    ok "gospider" "$GOSPIDER_C" "$(elapsed_since $STEP_START)"
else
    skip "gospider [2/4]"
    GOSPIDER_C=0
fi

# ── xnLinkFinder ─────────────────────────────────────────────
STEP_START=$(date +%s)
if command -v xnLinkFinder &>/dev/null; then
    echo -e "${BOLD}${WHITE}  ┌─[3/4] xnLinkFinder${NC} ${DIM}— link extraction from pages${NC}"
    run_tool "xnLinkFinder" "$OUTPUT_DIR/xnlink_tool.log" \
        xnLinkFinder \
            -i "$TARGET" \
            -op "$OUTPUT_DIR/xnlink.txt" \
            -sp "$TARGET" \
            -sf "$DOMAIN" \
            -d "$DEPTH"
    XNLINK_C=$(wc -l < "$OUTPUT_DIR/xnlink.txt" 2>/dev/null || echo 0)
    ok "xnLinkFinder" "$XNLINK_C" "$(elapsed_since $STEP_START)"
else
    skip "xnLinkFinder [3/4]"
    XNLINK_C=0
fi

# ── Combine results ───────────────────────────────────────────
echo ""
echo -e "${BOLD}${WHITE}  ┌─[4/4] combine + dedup${NC} ${DIM}— sort -u all sources${NC}"
STEP_START=$(date +%s)
cat \
    "$OUTPUT_DIR/katana/urls.txt" \
    "$OUTPUT_DIR/gospider/combined.txt" \
    "$OUTPUT_DIR/xnlink.txt" \
    2>/dev/null | \
    grep -E "^https?://" | \
    sort -u > "$OUTPUT_DIR/combined/all-urls.txt" || true

TOTAL=$(wc -l < "$OUTPUT_DIR/combined/all-urls.txt" 2>/dev/null || echo 0)
ok "combined" "$TOTAL" "$(elapsed_since $STEP_START)"

# ── Probe with httpx ──────────────────────────────────────────
STEP_START=$(date +%s)
if command -v httpx &>/dev/null; then
    echo ""
    echo -e "${BOLD}${WHITE}  ┌─[+] httpx${NC} ${DIM}— probe alive URLs, detect tech stack${NC}"
    run_tool "httpx" "$OUTPUT_DIR/httpx_tool.log" \
        httpx \
            -l "$OUTPUT_DIR/combined/all-urls.txt" \
            -o "$OUTPUT_DIR/combined/alive-urls.txt" \
            -sc -title -ct -server \
            -threads "$THREADS" \
            -timeout 10
    ALIVE_C=$(wc -l < "$OUTPUT_DIR/combined/alive-urls.txt" 2>/dev/null || echo 0)
    ok "httpx" "$ALIVE_C alive" "$(elapsed_since $STEP_START)"
else
    skip "httpx"
    ALIVE_C=0
fi

SCAN_END=$(date +%s)
TOTAL_ELAPSED=$(( SCAN_END - SCAN_START ))

# ── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║            ✅  CRAWL COMPLETE                        ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "  ${DIM}katana       :${NC} ${WHITE}${KATANA_C}${NC}"
echo -e "  ${DIM}gospider     :${NC} ${WHITE}${GOSPIDER_C}${NC}"
echo -e "  ${DIM}xnLinkFinder :${NC} ${WHITE}${XNLINK_C}${NC}"
echo -e "  ${DIM}─────────────────────────────${NC}"
echo -e "  ${DIM}Total unique :${NC} ${BOLD}${WHITE}${TOTAL}${NC}"
echo -e "  ${DIM}Alive        :${NC} ${BOLD}${WHITE}${ALIVE_C}${NC}"
echo -e "  ${DIM}Duration     :${NC} ${WHITE}${TOTAL_ELAPSED}s${NC}"
echo -e "  ${DIM}Output       :${NC} ${CYAN}${OUTPUT_DIR}${NC}"
echo ""

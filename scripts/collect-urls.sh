#!/bin/bash
# ============================================================
# URL Collector Script - All sources combined
# Usage: ./collect-urls.sh <domain> [threads]
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

DOMAIN="${1:-}"
THREADS="${2:-${THREADS:-30}}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="/workspace/output/urls_${DOMAIN}_${TIMESTAMP}"
SCAN_START=$(date +%s)

# Waymore max processes hard limit is 5
WAYMORE_PROCS=$(( THREADS > 5 ? 5 : THREADS ))

if [ -z "$DOMAIN" ]; then
    echo -e "${YELLOW}[!] Usage: $0 <domain> [threads]${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Pre-create output files so wc -l never fails
touch "$OUTPUT_DIR/gau.txt"
touch "$OUTPUT_DIR/wayback.txt"
touch "$OUTPUT_DIR/waymore.txt"
touch "$OUTPUT_DIR/all-urls.txt"

# ── Helpers ─────────────────────────────────────────────────
ok() {
    local label="$1" count="$2" elapsed="$3"
    echo -e "  ${GREEN}[✓]${NC} ${BOLD}${label}${NC} ${DIM}→${NC} ${CYAN}${count} URLs${NC} ${DIM}(${elapsed}s)${NC}"
}

skip() {
    echo -e "  ${DIM}[–] $1 — not installed, skipping${NC}"
}

elapsed_since() { echo $(( $(date +%s) - $1 )); }

# ── Header ──────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║          🔗  URL COLLECTOR 2026                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${DIM}Domain  :${NC} ${WHITE}$DOMAIN${NC}"
echo -e "  ${DIM}Threads :${NC} ${WHITE}$THREADS${NC}  ${DIM}(waymore capped at ${WAYMORE_PROCS}/5)${NC}"
echo -e "  ${DIM}Output  :${NC} ${CYAN}$OUTPUT_DIR${NC}"
echo ""

# ── gau ──────────────────────────────────────────────────────
STEP_START=$(date +%s)
if command -v gau &>/dev/null; then
    echo -e "${BOLD}${WHITE}  ┌─[1/4] gau${NC} ${DIM}— wayback + commoncrawl + otx + urlscan${NC}"
    # stdbuf forces line-buffered output so every line streams live
    echo "$DOMAIN" | stdbuf -oL gau \
        --threads "$THREADS" \
        --providers wayback,commoncrawl,otx,urlscan \
        --blacklist png,jpg,gif,jpeg,webp,svg,ico,css,woff,ttf \
        2>&1 | tee "$OUTPUT_DIR/gau_live.log" | \
        grep -E "^https?://" > "$OUTPUT_DIR/gau.txt" || true
    GAU_C=$(wc -l < "$OUTPUT_DIR/gau.txt" 2>/dev/null || echo 0)
    ok "gau" "$GAU_C" "$(elapsed_since $STEP_START)"
else
    skip "gau [1/4]"
    GAU_C=0
fi

# ── waybackurls ───────────────────────────────────────────────
STEP_START=$(date +%s)
if command -v waybackurls &>/dev/null; then
    echo -e "${BOLD}${WHITE}  ┌─[2/4] waybackurls${NC} ${DIM}— wayback machine URL history${NC}"
    echo "$DOMAIN" | stdbuf -oL waybackurls 2>&1 | tee "$OUTPUT_DIR/wayback_live.log" | \
        grep -E "^https?://" > "$OUTPUT_DIR/wayback.txt" || true
    WB_C=$(wc -l < "$OUTPUT_DIR/wayback.txt" 2>/dev/null || echo 0)
    ok "waybackurls" "$WB_C" "$(elapsed_since $STEP_START)"
else
    skip "waybackurls [2/4]"
    WB_C=0
fi

# ── waymore ───────────────────────────────────────────────────
# IMPORTANT: waymore -p/--processes max is 5 — use WAYMORE_PROCS not THREADS
STEP_START=$(date +%s)
if command -v waymore &>/dev/null; then
    echo -e "${BOLD}${WHITE}  ┌─[3/4] waymore${NC} ${DIM}— extended archive search (procs=${WAYMORE_PROCS}/5 max)${NC}"
    # Pre-create the file — waymore may exit before writing if it errors
    touch "$OUTPUT_DIR/waymore.txt"
    stdbuf -oL waymore \
        -i "$DOMAIN" \
        -mode U \
        -oU "$OUTPUT_DIR/waymore.txt" \
        -p "$WAYMORE_PROCS" \
        2>&1 | tee "$OUTPUT_DIR/waymore_live.log" || true
    WM_C=$(wc -l < "$OUTPUT_DIR/waymore.txt" 2>/dev/null || echo 0)
    ok "waymore" "$WM_C" "$(elapsed_since $STEP_START)"
else
    skip "waymore [3/4]"
    WM_C=0
fi

# ── Combine and deduplicate ───────────────────────────────────
echo ""
echo -e "${BOLD}${WHITE}  ┌─[4/4] dedup${NC} ${DIM}— combine + sort -u + uro${NC}"
STEP_START=$(date +%s)

cat "$OUTPUT_DIR/"*.txt 2>/dev/null | \
    grep -E "^https?://${DOMAIN}" | \
    sort -u > "$OUTPUT_DIR/all-urls.txt" || true

TOTAL=$(wc -l < "$OUTPUT_DIR/all-urls.txt" 2>/dev/null || echo 0)
ok "combined (sort -u)" "$TOTAL" "$(elapsed_since $STEP_START)"

# ── Optional: deduplicate with uro ────────────────────────────
if command -v uro &>/dev/null; then
    STEP_START=$(date +%s)
    uro < "$OUTPUT_DIR/all-urls.txt" > "$OUTPUT_DIR/all-urls-dedup.txt" 2>/dev/null || true
    URO_C=$(wc -l < "$OUTPUT_DIR/all-urls-dedup.txt" 2>/dev/null || echo 0)
    ok "uro dedup" "$URO_C" "$(elapsed_since $STEP_START)"
fi

SCAN_END=$(date +%s)
TOTAL_ELAPSED=$(( SCAN_END - SCAN_START ))

# ── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║            ✅  COLLECTION COMPLETE                   ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "  ${DIM}gau          :${NC} ${WHITE}${GAU_C}${NC}"
echo -e "  ${DIM}waybackurls  :${NC} ${WHITE}${WB_C}${NC}"
echo -e "  ${DIM}waymore      :${NC} ${WHITE}${WM_C}${NC}"
echo -e "  ${DIM}─────────────────────────────${NC}"
echo -e "  ${DIM}Total unique :${NC} ${BOLD}${WHITE}${TOTAL}${NC}"
echo -e "  ${DIM}Duration     :${NC} ${WHITE}${TOTAL_ELAPSED}s${NC}"
echo -e "  ${DIM}Output       :${NC} ${CYAN}${OUTPUT_DIR}/all-urls.txt${NC}"
echo ""

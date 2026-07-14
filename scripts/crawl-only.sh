#!/bin/bash
# ============================================================
# Crawl Only Script - Using katana + gospider + xnLinkFinder
# Usage: ./crawl-only.sh <target_url> [depth] [threads]
# ============================================================

# NOTE: -e removed — individual tool failures must not abort the scan
set -uo pipefail

# ── Ensure Python venv tools are on PATH ────────────────────
export PATH="/opt/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:$PATH"
export VIRTUAL_ENV="/opt/venv"

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

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

run_tool() {
    # Quiet mode: raw output → logfile only, terminal shows progress dots
    local label="$1"
    local logfile="$2"
    shift 2
    [ "${1:-}" = "--" ] && shift
    echo -e "  ${DIM}│  ${CYAN}▶ ${label}${NC} ${DIM}running...${NC}" | tee -a "$OUTPUT_DIR/scan.log"
    "$@" >> "$logfile" 2>&1 &
    local pid=$!
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 2; count=$(( count + 1 ))
        printf "\r  ${DIM}│  ▷ ${label} %${count}s${NC}" "" 2>/dev/null || true
        if [ $(( count % 10 )) -eq 0 ]; then
            echo -e "\n  ${DIM}│  ▷ ${label} still running... (${count}×2s)${NC}" \
                | tee -a "$OUTPUT_DIR/scan.log"
        fi
    done
    printf "\r%80s\r" "" 2>/dev/null || true
    wait "$pid" 2>/dev/null || warn "${label} exited non-zero (continuing)"
    echo -e "  ${DIM}│  ${GREEN}✓ ${label}${NC} ${DIM}done${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

# ── Header ──────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}${WHITE}🕷️  WEB CRAWLER TOOLKIT 2026 — CRAWL ONLY${NC}              ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Target  :" "$TARGET"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Domain  :" "$DOMAIN"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Depth   :" "$DEPTH"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Threads :" "$THREADS"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${CYAN}%-40s${BOLD}${CYAN}║${NC}\n" "Output  :" "$OUTPUT_DIR"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── katana - advanced crawling ────────────────────────────────
STEP_START=$(date +%s)
if command -v katana &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}1/4${WHITE}]${NC} ${BOLD}katana${NC} ${DIM}— active crawling with JS execution${NC}"
    run_tool "katana" "$OUTPUT_DIR/katana/tool.log" \
        katana \
            -u "$TARGET" \
            -d "$DEPTH" \
            -c "$THREADS" \
            -kf all \
            -H "User-Agent: Mozilla/5.0 (compatible; CrawlerToolkit/2026)" \
            -rl 150 \
            -timeout 15 \
            -retry 2 \
            -silent \
            -o "$OUTPUT_DIR/katana/urls.txt"
    KATANA_C=$(wc -l < "$OUTPUT_DIR/katana/urls.txt" 2>/dev/null || echo 0)
    ok "katana" "$KATANA_C" "$(elapsed_since $STEP_START)"
else
    skip "katana [1/4]"
    KATANA_C=0
fi

# ── gospider - additional spider ─────────────────────────────
STEP_START=$(date +%s)
if command -v gospider &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}2/4${WHITE}]${NC} ${BOLD}gospider${NC} ${DIM}— spider with sitemap + robots + JS${NC}"
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
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}3/4${WHITE}]${NC} ${BOLD}xnLinkFinder${NC} ${DIM}— link extraction from pages${NC}"
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
echo -e "  ${BOLD}${WHITE}┌─[${CYAN}4/4${WHITE}]${NC} ${BOLD}combine + dedup${NC} ${DIM}— merge all sources + sort -u${NC}"
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
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}+${WHITE}]${NC} ${BOLD}httpx${NC} ${DIM}— probe alive URLs + detect tech stack${NC}"
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
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${BOLD}${CYAN}[ CRAWL RESULTS ]${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ┌──────────────────────┬────────────┐${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}Tool${NC}                  ${BOLD}${WHITE}│${NC}  ${DIM}URLs Found${NC}  ${BOLD}${WHITE}│${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ├──────────────────────┼────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

_print_row() {
    local t="$1"; local c="$2"
    if [ "$c" -gt 0 ] 2>/dev/null; then
        printf "  ${BOLD}${WHITE}│${NC}  %-20s  ${BOLD}${WHITE}│${NC}  ${CYAN}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" "$t" "$c" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-20s  │  %8s${NC}  ${BOLD}${WHITE}│${NC}\n" "$t" "$c" | tee -a "$OUTPUT_DIR/scan.log"
    fi
}
_print_row "katana"        "$KATANA_C"
_print_row "gospider"      "$GOSPIDER_C"
_print_row "xnLinkFinder"  "$XNLINK_C"
echo -e "${BOLD}${WHITE}  ├──────────────────────┼────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf   "  ${BOLD}${WHITE}│${NC}  %-20s  ${BOLD}${WHITE}│${NC}  ${WHITE}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" "Total unique" "$TOTAL" | tee -a "$OUTPUT_DIR/scan.log"
printf   "  ${BOLD}${WHITE}│${NC}  %-20s  ${BOLD}${WHITE}│${NC}  ${GREEN}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" "Alive (httpx)" "$ALIVE_C" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  └──────────────────────┴────────────┘${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

MM=$(( TOTAL_ELAPSED / 60 )); SS=$(( TOTAL_ELAPSED % 60 ))
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}${WHITE}✅  CRAWL COMPLETE${NC}                                       ${BOLD}${GREEN}║${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Total unique :" "$TOTAL URLs" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Alive URLs :" "$ALIVE_C" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Duration :" "${MM}m ${SS}s" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${CYAN}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Output :" "$OUTPUT_DIR" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

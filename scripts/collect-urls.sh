#!/bin/bash
# ============================================================
# URL Collector Script - All sources combined
# Usage: ./collect-urls.sh <domain> [threads]
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
mkdir -p "$OUTPUT_DIR/secrets"

# Pre-create output files so wc -l never fails
touch "$OUTPUT_DIR/gau.txt"
touch "$OUTPUT_DIR/wayback.txt"
touch "$OUTPUT_DIR/waymore.txt"
touch "$OUTPUT_DIR/secrets/mantra.txt"
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
    wait "$pid" 2>/dev/null || true
    echo -e "  ${DIM}│  ${GREEN}✓ ${label}${NC} ${DIM}done${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

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
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}1/5${WHITE}]${NC} ${BOLD}gau${NC} ${DIM}— wayback + commoncrawl + otx + urlscan${NC}"
    # stdbuf forces line-buffered output so every line streams live
    echo "$DOMAIN" | gau \
        --threads "$THREADS" \
        --providers wayback,commoncrawl,otx,urlscan \
        --blacklist png,jpg,gif,jpeg,webp,svg,ico,css,woff,ttf \
        2>&1 | tee "$OUTPUT_DIR/gau_live.log" | \
        grep -E "^https?://" > "$OUTPUT_DIR/gau.txt" || true
    GAU_C=$(wc -l < "$OUTPUT_DIR/gau.txt" 2>/dev/null || echo 0)
    ok "gau" "$GAU_C" "$(elapsed_since $STEP_START)"
else
    skip "gau [1/5]"
    GAU_C=0
fi

# ── waybackurls ───────────────────────────────────────────────
STEP_START=$(date +%s)
if command -v waybackurls &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}2/5${WHITE}]${NC} ${BOLD}waybackurls${NC} ${DIM}— wayback machine URL history${NC}"
    echo "$DOMAIN" | waybackurls 2>&1 | tee "$OUTPUT_DIR/wayback_live.log" | \
        grep -E "^https?://" > "$OUTPUT_DIR/wayback.txt" || true
    WB_C=$(wc -l < "$OUTPUT_DIR/wayback.txt" 2>/dev/null || echo 0)
    ok "waybackurls" "$WB_C" "$(elapsed_since $STEP_START)"
else
    skip "waybackurls [2/5]"
    WB_C=0
fi

# ── waymore ───────────────────────────────────────────────────
# IMPORTANT: waymore -p/--processes max is 5 — use WAYMORE_PROCS not THREADS
STEP_START=$(date +%s)
if command -v waymore &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}3/5${WHITE}]${NC} ${BOLD}waymore${NC} ${DIM}— extended archive search  [procs=${WAYMORE_PROCS}/5 max]${NC}"
    # Pre-create the file — waymore may exit before writing if it errors
    touch "$OUTPUT_DIR/waymore.txt"
    waymore \
        -i "$DOMAIN" \
        -mode U \
        -oU "$OUTPUT_DIR/waymore.txt" \
        -p "$WAYMORE_PROCS" \
        2>&1 | tee "$OUTPUT_DIR/waymore_live.log" || true
    WM_C=$(wc -l < "$OUTPUT_DIR/waymore.txt" 2>/dev/null || echo 0)
    ok "waymore" "$WM_C" "$(elapsed_since $STEP_START)"
else
    skip "waymore [3/5]"
    WM_C=0
fi

# ── Combine and deduplicate ───────────────────────────────────
echo ""
echo -e ""
echo -e "  ${BOLD}${WHITE}┌─[${CYAN}4/5${WHITE}]${NC} ${BOLD}dedup${NC} ${DIM}— combine all sources + sort -u + uro${NC}"
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

# ── mantra — secret/key scan on collected URLs ────────────────
MANTRA_COUNT=0
DEDUP_FILE="${OUTPUT_DIR}/all-urls-dedup.txt"
[ ! -s "$DEDUP_FILE" ] && DEDUP_FILE="${OUTPUT_DIR}/all-urls.txt"
DEDUP_TOTAL=$(wc -l < "$DEDUP_FILE" 2>/dev/null || echo 0)

echo ""
echo -e "  ${BOLD}${WHITE}┌─[${CYAN}5/5${WHITE}]${NC} ${BOLD}mantra${NC} ${DIM}— hunt secrets/keys in HTTP responses${NC}"
if command -v mantra &>/dev/null && [ "$DEDUP_TOTAL" -gt 0 ]; then
    STEP_START=$(date +%s)
    run_tool "mantra" "$OUTPUT_DIR/secrets/mantra.log" \
        bash -c "cat '$DEDUP_FILE' | mantra 2>/dev/null | tee '$OUTPUT_DIR/secrets/mantra.txt'"
    MANTRA_COUNT=$(wc -l < "$OUTPUT_DIR/secrets/mantra.txt" 2>/dev/null || echo 0)
    if [ "$MANTRA_COUNT" -gt 0 ]; then
        ok "mantra" "$MANTRA_COUNT secrets found!" "$(elapsed_since $STEP_START)"
        echo -e "  ${RED}[!]${NC} ${BOLD}mantra${NC}: ${YELLOW}${MANTRA_COUNT} secrets/keys found — check $OUTPUT_DIR/secrets/mantra.txt${NC}"
    else
        ok "mantra" "0 (clean)" "$(elapsed_since $STEP_START)"
    fi
else
    skip "mantra [5/5]"
fi

SCAN_END=$(date +%s)
TOTAL_ELAPSED=$(( SCAN_END - SCAN_START ))
MM=$(( TOTAL_ELAPSED / 60 ))
SS=$(( TOTAL_ELAPSED % 60 ))

# ── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${BOLD}${CYAN}[ URL COLLECTION RESULTS ]${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ┌───────────────────┬────────────┐${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}Tool${NC}               ${BOLD}${WHITE}│${NC}  ${DIM}URLs Found${NC}  ${BOLD}${WHITE}│${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ├───────────────────┼────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

_cr() {
    local t="$1"; local c="$2"
    if [ "$c" -gt 0 ] 2>/dev/null; then
        printf "  ${BOLD}${WHITE}│${NC}  %-17s  ${BOLD}${WHITE}│${NC}  ${CYAN}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" "$t" "$c" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-17s  │  %8s${NC}  ${BOLD}${WHITE}│${NC}\n" "$t" "$c" | tee -a "$OUTPUT_DIR/scan.log"
    fi
}
_cr "gau"         "$GAU_C"
_cr "waybackurls" "$WB_C"
_cr "waymore"     "$WM_C"
echo -e "${BOLD}${WHITE}  ├───────────────────┼────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf   "  ${BOLD}${WHITE}│${NC}  %-17s  ${BOLD}${WHITE}│${NC}  ${WHITE}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" "Total unique" "${URO_C:-$TOTAL}" | tee -a "$OUTPUT_DIR/scan.log"
if [ "${MANTRA_COUNT:-0}" -gt 0 ]; then
    printf "  ${BOLD}${WHITE}│${NC}  ${RED}%-17s  │  %8s${NC}  ${BOLD}${WHITE}│${NC}\n" "mantra secrets" "$MANTRA_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
else
    printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-17s  │  %8s${NC}  ${BOLD}${WHITE}│${NC}\n" "mantra secrets" "0 (clean)" | tee -a "$OUTPUT_DIR/scan.log"
fi
echo -e "${BOLD}${WHITE}  └───────────────────┴────────────┘${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}${WHITE}✅  COLLECTION COMPLETE${NC}                                  ${BOLD}${GREEN}║${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Total unique :" "${URO_C:-$TOTAL} URLs" | tee -a "$OUTPUT_DIR/scan.log"
if [ "${MANTRA_COUNT:-0}" -gt 0 ]; then
    printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${RED}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Secret findings :" "⚠  ${MANTRA_COUNT} secrets/keys found!" | tee -a "$OUTPUT_DIR/scan.log"
else
    printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${DIM}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Secret findings :" "0  (clean)" | tee -a "$OUTPUT_DIR/scan.log"
fi
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Duration :" "${MM}m ${SS}s" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${CYAN}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Output :" "$OUTPUT_DIR/all-urls.txt" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

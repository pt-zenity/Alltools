#!/bin/bash
# ============================================================
# JavaScript File Analyzer
# Extracts endpoints, secrets, and links from JS files
# Usage: ./js-analyze.sh <target_url_or_domain>
# ============================================================

# NOTE: -e removed — individual steps must not abort the whole analysis
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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||' | sed 's|:.*||')
OUTPUT_DIR="/workspace/output/js_${DOMAIN}_${TIMESTAMP}"
SCAN_START=$(date +%s)

if [ -z "$TARGET" ]; then
    echo -e "${YELLOW}[!] Usage: $0 <target_url_or_domain>${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"/{js-files,endpoints,secrets}

# Pre-create output files so wc -l never fails
touch "$OUTPUT_DIR/js-files/js-urls.txt"
touch "$OUTPUT_DIR/js-files/combined.js"
touch "$OUTPUT_DIR/endpoints/api-endpoints.txt"
touch "$OUTPUT_DIR/endpoints/paths.txt"
touch "$OUTPUT_DIR/secrets/aws-keys.txt"
touch "$OUTPUT_DIR/secrets/potential-tokens.txt"

# ── Helpers ─────────────────────────────────────────────────
ok() {
    local label="$1" count="$2" elapsed="$3"
    echo -e "  ${GREEN}[✓]${NC} ${BOLD}${label}${NC} ${DIM}→${NC} ${CYAN}${count}${NC} ${DIM}(${elapsed}s)${NC}"
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
    echo -e "  ${DIM}│  ${CYAN}▶ ${label}${NC} ${DIM}running...${NC}" | tee -a "$OUTPUT_DIR/scan.log"
    stdbuf -oL "$@" >> "$logfile" 2>&1 &
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
    wait "$pid" 2>/dev/null || \
        echo -e "${YELLOW}  [WARN] ${label} exited non-zero (continuing)${NC}" \
            | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "  ${DIM}│  ${GREEN}✓ ${label}${NC} ${DIM}done${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

# ── Header ──────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}${WHITE}🔍  WEB CRAWLER TOOLKIT 2026 — JS ANALYZER${NC}             ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Target  :" "$TARGET"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Domain  :" "$DOMAIN"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${CYAN}%-40s${BOLD}${CYAN}║${NC}\n" "Output  :" "$OUTPUT_DIR"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${DIM}Target  :${NC} ${WHITE}$TARGET${NC}"
echo -e "  ${DIM}Domain  :${NC} ${WHITE}$DOMAIN${NC}"
echo -e "  ${DIM}Output  :${NC} ${CYAN}$OUTPUT_DIR${NC}"
echo ""

# ── Step 1: Collect JS URLs with katana ──────────────────────
STEP_START=$(date +%s)
if command -v katana &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}1/4${WHITE}]${NC} ${BOLD}katana${NC} ${DIM}— discover JS files via active crawl${NC}"
    run_tool "katana" "$OUTPUT_DIR/js-files/katana.log" \
        katana \
            -u "$TARGET" \
            -jc \
            -d 3 \
            -c 30 \
            -extension-match js \
            -o "$OUTPUT_DIR/js-files/js-urls.txt"
    ok "katana JS discovery" "$(wc -l < "$OUTPUT_DIR/js-files/js-urls.txt")" "$(elapsed_since $STEP_START)"
else
    skip "katana [1/4]"
fi

# ── Step 2: Get JS from gau/wayback ──────────────────────────
STEP_START=$(date +%s)
if command -v gau &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}2/4${WHITE}]${NC} ${BOLD}gau${NC} ${DIM}— JS files from wayback + commoncrawl${NC}"
    run_tool "gau-js" "$OUTPUT_DIR/js-files/gau.log" \
        bash -c "echo '$DOMAIN' | stdbuf -oL gau \
            --providers wayback,commoncrawl 2>&1 | \
            grep -E '\.js(\?|\$)' >> '$OUTPUT_DIR/js-files/js-urls.txt' || true"
    ok "gau JS discovery" "done" "$(elapsed_since $STEP_START)"
else
    skip "gau [2/4]"
fi

# Sort and dedup JS URL list
sort -u -o "$OUTPUT_DIR/js-files/js-urls.txt" "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || true
JS_COUNT=$(wc -l < "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || echo 0)
echo -e "  ${BLUE}[i]${NC} Total unique JS files: ${WHITE}${JS_COUNT}${NC}"

# ── Step 3: Download and analyze JS files ────────────────────
STEP_START=$(date +%s)
echo -e ""
echo -e "  ${BOLD}${WHITE}┌─[${CYAN}3/4${WHITE}]${NC} ${BOLD}download${NC} ${DIM}— fetch ${JS_COUNT} JS files${NC}"
if [ "$JS_COUNT" -gt 0 ]; then
    DOWNLOADED=0
    while IFS= read -r js_url; do
        [ -z "$js_url" ] && continue
        echo -e "  ${DIM}│  [$(date +%H:%M:%S)] ${js_url}${NC}"
        curl -s --max-time 10 -L "$js_url" >> "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null || true
        DOWNLOADED=$(( DOWNLOADED + 1 ))
    done < "$OUTPUT_DIR/js-files/js-urls.txt"
    ok "downloaded" "${DOWNLOADED} JS files" "$(elapsed_since $STEP_START)"
else
    echo -e "  ${DIM}  No JS files to download.${NC}"
fi

# ── Step 4: Pattern extraction ───────────────────────────────
STEP_START=$(date +%s)
echo -e ""
echo -e "  ${BOLD}${WHITE}┌─[${CYAN}4/4${WHITE}]${NC} ${BOLD}extract${NC} ${DIM}— pattern analysis from combined JS${NC}"

COMBINED_SIZE=$(wc -c < "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null || echo 0)
if [ "$COMBINED_SIZE" -gt 0 ]; then
    # API endpoints
    grep -oE '("|'"'"')(/api/[^"'"'"']+)("|'"'"')' "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null | \
        tr -d '"'"'" | sort -u > "$OUTPUT_DIR/endpoints/api-endpoints.txt" || true
    API_ENDPOINT_COUNT=$(wc -l < "$OUTPUT_DIR/endpoints/api-endpoints.txt" 2>/dev/null || echo 0)

    # Path routes
    grep -oE '("|'"'"')(/[a-zA-Z0-9_/-]{3,})("|'"'"')' "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null | \
        tr -d '"'"'" | sort -u > "$OUTPUT_DIR/endpoints/paths.txt" || true
    PATHS_COUNT=$(wc -l < "$OUTPUT_DIR/endpoints/paths.txt" 2>/dev/null || echo 0)

    # AWS keys
    grep -oE 'AKIA[0-9A-Z]{16}' "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null > \
        "$OUTPUT_DIR/secrets/aws-keys.txt" || true
    AWS_COUNT=$(wc -l < "$OUTPUT_DIR/secrets/aws-keys.txt" 2>/dev/null || echo 0)

    # Potential tokens / API keys
    grep -oE '"[a-zA-Z0-9_-]{32,}"' "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null | \
        head -100 > "$OUTPUT_DIR/secrets/potential-tokens.txt" || true
    TOKEN_COUNT=$(wc -l < "$OUTPUT_DIR/secrets/potential-tokens.txt" 2>/dev/null || echo 0)

    printf "  ${DIM}%-25s${NC}  ${WHITE}%s${NC}\n" "API endpoints    :" "$API_ENDPOINT_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
    printf "  ${DIM}%-25s${NC}  ${WHITE}%s${NC}\n" "Path routes      :" "$PATHS_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
    if [ "$AWS_COUNT" -gt 0 ] 2>/dev/null; then
        echo -e "  ${RED}[!] AWS key patterns : ${AWS_COUNT}  — CHECK IMMEDIATELY${NC}" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${DIM}%-25s${NC}  ${WHITE}%s${NC}\n" "AWS key patterns :" "$AWS_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
    fi
    if [ "$TOKEN_COUNT" -gt 0 ] 2>/dev/null; then
        echo -e "  ${YELLOW}[!] Potential tokens : ${TOKEN_COUNT}  — Review secrets/potential-tokens.txt${NC}" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${DIM}%-25s${NC}  ${WHITE}%s${NC}\n" "Potential tokens :" "$TOKEN_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
    fi
    ok "extraction" "done" "$(elapsed_since $STEP_START)"
else
    echo -e "  ${YELLOW}[WARN]${NC} combined.js is empty — nothing to extract" | tee -a "$OUTPUT_DIR/scan.log"
    API_ENDPOINT_COUNT=0; PATHS_COUNT=0; AWS_COUNT=0; TOKEN_COUNT=0
fi

SCAN_END=$(date +%s)
TOTAL_ELAPSED=$(( SCAN_END - SCAN_START ))
MM=$(( TOTAL_ELAPSED / 60 ))
SS=$(( TOTAL_ELAPSED % 60 ))

# ── Summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${BOLD}${CYAN}[ JS ANALYSIS RESULTS ]${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ┌──────────────────────┬────────────────────────┐${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}Category${NC}              ${BOLD}${WHITE}│${NC}  ${DIM}Count${NC}                   ${BOLD}${WHITE}│${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ├──────────────────────┼────────────────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

_jrow() {
    local label="$1"; local count="$2"; local alert="${3:-}"
    if [ "$count" -gt 0 ] 2>/dev/null && [ -n "$alert" ]; then
        printf "  ${BOLD}${WHITE}│${NC}  ${YELLOW}%-20s${NC}  ${BOLD}${WHITE}│${NC}  ${YELLOW}%6s %-17s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" "$alert" | tee -a "$OUTPUT_DIR/scan.log"
    elif [ "$count" -gt 0 ] 2>/dev/null; then
        printf "  ${BOLD}${WHITE}│${NC}  %-20s  ${BOLD}${WHITE}│${NC}  ${CYAN}%6s${NC}  ${DIM}%-15s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" "" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-20s  │  %6s  %-15s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" "" | tee -a "$OUTPUT_DIR/scan.log"
    fi
}
_jrow "JS files found"   "${JS_COUNT:-0}"             ""
_jrow "API endpoints"    "${API_ENDPOINT_COUNT:-0}"   ""
_jrow "Path routes"      "${PATHS_COUNT:-0}"          ""
_jrow "AWS keys"         "${AWS_COUNT:-0}"            "⚠️ CRITICAL"
_jrow "Potential tokens" "${TOKEN_COUNT:-0}"          "⚠️ Review"
echo -e "${BOLD}${WHITE}  └──────────────────────┴────────────────────────┘${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}${WHITE}✅  JS ANALYSIS COMPLETE${NC}                                 ${BOLD}${GREEN}║${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Duration :" "${MM}m ${SS}s" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${CYAN}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Output :" "$OUTPUT_DIR" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

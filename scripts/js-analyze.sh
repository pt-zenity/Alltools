#!/bin/bash
# ============================================================
# JavaScript File Analyzer v2.2
# Tools: katana + gau + SecretFinder + JSScanner + mantra
# Usage: ./js-analyze.sh <target_url_or_domain>
# ============================================================

# NOTE: -e removed — individual steps must not abort the whole analysis
set -uo pipefail

# ── Ensure Python venv tools are on PATH ────────────────────
export PATH="/opt/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:$PATH"
export VIRTUAL_ENV="/opt/venv"

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
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

mkdir -p "$OUTPUT_DIR"/{js-files,endpoints,secrets,secretfinder,jsscanner,mantra}

# Pre-create output files so wc -l never fails
touch "$OUTPUT_DIR/js-files/js-urls.txt"
touch "$OUTPUT_DIR/js-files/combined.js"
touch "$OUTPUT_DIR/endpoints/api-endpoints.txt"
touch "$OUTPUT_DIR/endpoints/paths.txt"
touch "$OUTPUT_DIR/secrets/aws-keys.txt"
touch "$OUTPUT_DIR/secrets/potential-tokens.txt"
touch "$OUTPUT_DIR/secretfinder/results.txt"
touch "$OUTPUT_DIR/jsscanner/results.txt"
touch "$OUTPUT_DIR/mantra/results.txt"

# ── Helpers ─────────────────────────────────────────────────
ok() {
    local label="$1" count="$2" elapsed="$3"
    echo -e "  ${GREEN}[✓]${NC} ${BOLD}${label}${NC} ${DIM}→${NC} ${CYAN}${count}${NC} ${DIM}(${elapsed}s)${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

skip() {
    echo -e "  ${DIM}[–] $1 — not installed, skipping${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

elapsed_since() { echo $(( $(date +%s) - $1 )); }

run_tool() {
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
    wait "$pid" 2>/dev/null || \
        echo -e "${YELLOW}  [WARN] ${label} exited non-zero (continuing)${NC}" \
            | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "  ${DIM}│  ${GREEN}✓ ${label}${NC} ${DIM}done${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

# ── Header ──────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}${WHITE}🔍  WEB CRAWLER TOOLKIT 2026 — JS ANALYZER v2.2${NC}        ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Target  :" "$TARGET"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Domain  :" "$DOMAIN"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${CYAN}%-40s${BOLD}${CYAN}║${NC}\n"  "Output  :" "$OUTPUT_DIR"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-54s${BOLD}${CYAN}║${NC}\n" "Tools: katana • gau • SecretFinder • JSScanner • mantra"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# PHASE 1: Collect JS URLs
# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  PHASE 1: JS FILE DISCOVERY  (2 tools)               ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"

# 1.1 katana
STEP_START=$(date +%s)
if command -v katana &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}1/2${WHITE}]${NC} ${BOLD}katana${NC} ${DIM}— discover JS files via active crawl${NC}"
    run_tool "katana" "$OUTPUT_DIR/js-files/katana.log" \
        katana \
            -u "$TARGET" \
            -d 3 \
            -c 30 \
            -silent \
            -extension-match js \
            -o "$OUTPUT_DIR/js-files/js-urls.txt"
    ok "katana JS discovery" "$(wc -l < "$OUTPUT_DIR/js-files/js-urls.txt")" "$(elapsed_since $STEP_START)"
else
    skip "katana [1/2]"
fi

# 1.2 gau
STEP_START=$(date +%s)
if command -v gau &>/dev/null; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}2/2${WHITE}]${NC} ${BOLD}gau${NC} ${DIM}— JS files from wayback + commoncrawl${NC}"
    run_tool "gau-js" "$OUTPUT_DIR/js-files/gau.log" \
        bash -c "echo '$DOMAIN' | gau \
            --providers wayback,commoncrawl 2>&1 | \
            grep -E '\.js(\?|\$)' >> '$OUTPUT_DIR/js-files/js-urls.txt' || true"
    ok "gau JS discovery" "done" "$(elapsed_since $STEP_START)"
else
    skip "gau [2/2]"
fi

# Sort and dedup JS URL list
sort -u -o "$OUTPUT_DIR/js-files/js-urls.txt" "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || true
JS_COUNT=$(wc -l < "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || echo 0)
echo -e ""
echo -e "  ${BLUE}[i]${NC} Total unique JS files found: ${BOLD}${WHITE}${JS_COUNT}${NC}"

# ─────────────────────────────────────────────────────────────
# PHASE 2: Download JS Files
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  PHASE 2: DOWNLOAD JS FILES                          ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

STEP_START=$(date +%s)
echo -e "  ${BOLD}${WHITE}┌─[1/1]${NC} ${BOLD}download${NC} ${DIM}— fetch ${JS_COUNT} JS files${NC}"
DOWNLOADED=0
if [ "$JS_COUNT" -gt 0 ]; then
    while IFS= read -r js_url; do
        [ -z "$js_url" ] && continue
        printf "  ${DIM}│  %-60s${NC}\r" "$(basename "$js_url")"
        curl -s --max-time 10 -L "$js_url" >> "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null || true
        DOWNLOADED=$(( DOWNLOADED + 1 ))
    done < "$OUTPUT_DIR/js-files/js-urls.txt"
    printf "\r%80s\r" ""
    ok "downloaded" "${DOWNLOADED} JS files → combined.js" "$(elapsed_since $STEP_START)"
else
    echo -e "  ${DIM}  No JS files to download — skipping.${NC}"
fi

COMBINED_SIZE=$(wc -c < "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null || echo 0)
echo -e "  ${DIM}combined.js size: ${COMBINED_SIZE} bytes${NC}"

# ─────────────────────────────────────────────────────────────
# PHASE 3: Secret Scanning (SecretFinder + mantra)
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  PHASE 3: SECRET SCANNING  (SecretFinder + mantra)   ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"

# 3.1 SecretFinder — per-JS-URL scanning
STEP_START=$(date +%s)
SF_SCRIPT="/opt/SecretFinder/SecretFinder.py"
if [ -f "$SF_SCRIPT" ] && [ "$JS_COUNT" -gt 0 ]; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}1/2${WHITE}]${NC} ${BOLD}SecretFinder${NC} ${DIM}— secrets/keys/tokens from ${JS_COUNT} JS URLs${NC}"
    SF_FOUND=0
    SF_PROCESSED=0
    while IFS= read -r js_url; do
        [ -z "$js_url" ] && continue
        SF_PROCESSED=$(( SF_PROCESSED + 1 ))
        printf "\r  ${DIM}│  [%d/%d] scanning...${NC}" "$SF_PROCESSED" "$JS_COUNT"
        python3 "$SF_SCRIPT" -i "$js_url" -o cli 2>/dev/null | \
            grep -vE "^\[|^$|^-{20}|SecretFinder" >> \
            "$OUTPUT_DIR/secretfinder/results.txt" || true
    done < "$OUTPUT_DIR/js-files/js-urls.txt"
    printf "\r%80s\r" ""
    SF_FOUND=$(wc -l < "$OUTPUT_DIR/secretfinder/results.txt" 2>/dev/null || echo 0)
    if [ "$SF_FOUND" -gt 0 ]; then
        echo -e "  ${RED}[!]${NC} ${BOLD}SecretFinder${NC}: ${YELLOW}${SF_FOUND} potential secrets found!${NC}" \
            | tee -a "$OUTPUT_DIR/scan.log"
    else
        ok "SecretFinder" "no secrets detected" "$(elapsed_since $STEP_START)"
    fi
elif [ ! -f "$SF_SCRIPT" ]; then
    skip "SecretFinder [1/2] — not installed at /opt/SecretFinder"
    SF_FOUND=0
else
    echo -e "  ${DIM}[–] SecretFinder — no JS files to scan${NC}"
    SF_FOUND=0
fi

# 3.2 mantra — secret hunting from URL list
STEP_START=$(date +%s)
if command -v mantra &>/dev/null && [ "$JS_COUNT" -gt 0 ]; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}2/2${WHITE}]${NC} ${BOLD}mantra${NC} ${DIM}— secret patterns in JS/HTML responses${NC}"
    run_tool "mantra" "$OUTPUT_DIR/mantra/results.txt" \
        bash -c "cat '$OUTPUT_DIR/js-files/js-urls.txt' | mantra 2>/dev/null"
    MANTRA_COUNT=$(wc -l < "$OUTPUT_DIR/mantra/results.txt" 2>/dev/null || echo 0)
    if [ "$MANTRA_COUNT" -gt 0 ]; then
        echo -e "  ${RED}[!]${NC} ${BOLD}mantra${NC}: ${YELLOW}${MANTRA_COUNT} secrets/keys found!${NC}" \
            | tee -a "$OUTPUT_DIR/scan.log"
    else
        ok "mantra" "no secrets detected" "$(elapsed_since $STEP_START)"
    fi
elif ! command -v mantra &>/dev/null; then
    skip "mantra [2/2]"
    MANTRA_COUNT=0
else
    echo -e "  ${DIM}[–] mantra — no JS files to scan${NC}"
    MANTRA_COUNT=0
fi

# ─────────────────────────────────────────────────────────────
# PHASE 4: JS Endpoint Extraction (JSScanner + patterns)
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  PHASE 4: ENDPOINT EXTRACTION  (JSScanner + regex)   ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"

# 4.1 JSScanner
STEP_START=$(date +%s)
JSS_SCRIPT="/opt/JSScanner/JSScanner.py"
if [ -f "$JSS_SCRIPT" ] && [ "$JS_COUNT" -gt 0 ]; then
    echo -e ""
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}1/2${WHITE}]${NC} ${BOLD}JSScanner${NC} ${DIM}— endpoints + secrets from ${JS_COUNT} JS URLs${NC}"
    JSS_PROCESSED=0
    while IFS= read -r js_url; do
        [ -z "$js_url" ] && continue
        JSS_PROCESSED=$(( JSS_PROCESSED + 1 ))
        printf "\r  ${DIM}│  [%d/%d] scanning...${NC}" "$JSS_PROCESSED" "$JS_COUNT"
        python3 "$JSS_SCRIPT" -u "$js_url" 2>/dev/null | \
            grep -vE "^$|^\[" >> "$OUTPUT_DIR/jsscanner/results.txt" || true
    done < "$OUTPUT_DIR/js-files/js-urls.txt"
    printf "\r%80s\r" ""
    JSS_COUNT=$(wc -l < "$OUTPUT_DIR/jsscanner/results.txt" 2>/dev/null || echo 0)
    ok "JSScanner" "${JSS_COUNT} findings" "$(elapsed_since $STEP_START)"
elif [ ! -f "$JSS_SCRIPT" ]; then
    skip "JSScanner [1/2] — not installed at /opt/JSScanner"
    JSS_COUNT=0
else
    echo -e "  ${DIM}[–] JSScanner — no JS files to scan${NC}"
    JSS_COUNT=0
fi

# 4.2 Regex pattern extraction from combined.js
STEP_START=$(date +%s)
echo -e ""
echo -e "  ${BOLD}${WHITE}┌─[${CYAN}2/2${WHITE}]${NC} ${BOLD}regex patterns${NC} ${DIM}— extract endpoints from combined.js${NC}"
API_ENDPOINT_COUNT=0; PATHS_COUNT=0; AWS_COUNT=0; TOKEN_COUNT=0

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

    # Potential tokens / API keys (32+ char alphanumeric strings)
    grep -oE '"[a-zA-Z0-9_-]{32,}"' "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null | \
        head -100 > "$OUTPUT_DIR/secrets/potential-tokens.txt" || true
    TOKEN_COUNT=$(wc -l < "$OUTPUT_DIR/secrets/potential-tokens.txt" 2>/dev/null || echo 0)

    ok "regex extraction" "done" "$(elapsed_since $STEP_START)"
else
    echo -e "  ${YELLOW}[WARN]${NC} combined.js is empty — nothing to extract" | tee -a "$OUTPUT_DIR/scan.log"
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

echo -e "${BOLD}${WHITE}  ┌──────────────────────────┬────────────────────────────┐${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-26s${NC}${BOLD}${WHITE}│${NC}  ${DIM}%-26s${NC}${BOLD}${WHITE}│${NC}\n" \
    "Category" "Result" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ├──────────────────────────┼────────────────────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

_jrow() {
    local label="$1" count="$2" alert="${3:-}"
    if [ "${count:-0}" -gt 0 ] 2>/dev/null && [ -n "$alert" ]; then
        printf "  ${BOLD}${WHITE}│${NC}  ${YELLOW}%-24s${NC}  ${BOLD}${WHITE}│${NC}  ${YELLOW}%5s  %-18s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" "$alert" | tee -a "$OUTPUT_DIR/scan.log"
    elif [ "${count:-0}" -gt 0 ] 2>/dev/null; then
        printf "  ${BOLD}${WHITE}│${NC}  %-24s  ${BOLD}${WHITE}│${NC}  ${CYAN}%5s${NC}  ${DIM}%-18s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" "" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-24s  │  %5s  %-18s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "${count:-0}" "—" | tee -a "$OUTPUT_DIR/scan.log"
    fi
}

echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}── Discovery ──────────────────────────────────${NC}  ${BOLD}${WHITE}│${NC}" \
    | tee -a "$OUTPUT_DIR/scan.log"
_jrow "JS files found"        "${JS_COUNT:-0}"             ""
_jrow "API endpoints"         "${API_ENDPOINT_COUNT:-0}"   ""
_jrow "Path routes"           "${PATHS_COUNT:-0}"          ""

echo -e "${BOLD}${WHITE}  ├──────────────────────────┼────────────────────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}── Secret Scanning ────────────────────────────${NC}  ${BOLD}${WHITE}│${NC}" \
    | tee -a "$OUTPUT_DIR/scan.log"
_jrow "SecretFinder hits"     "${SF_FOUND:-0}"             "⚠️  CHECK NOW"
_jrow "mantra secrets"        "${MANTRA_COUNT:-0}"         "⚠️  CHECK NOW"
_jrow "JSScanner findings"    "${JSS_COUNT:-0}"            "⚠️  Review"
_jrow "AWS key patterns"      "${AWS_COUNT:-0}"            "🔴 CRITICAL"
_jrow "Potential tokens"      "${TOKEN_COUNT:-0}"          "⚠️  Review"

echo -e "${BOLD}${WHITE}  └──────────────────────────┴────────────────────────────┘${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

# Output files list
echo -e "  ${DIM}Output files:${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${CYAN}  $OUTPUT_DIR/secretfinder/results.txt${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${CYAN}  $OUTPUT_DIR/jsscanner/results.txt${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${CYAN}  $OUTPUT_DIR/mantra/results.txt${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${CYAN}  $OUTPUT_DIR/endpoints/api-endpoints.txt${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${CYAN}  $OUTPUT_DIR/secrets/aws-keys.txt${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}${WHITE}✅  JS ANALYSIS COMPLETE${NC}                                 ${BOLD}${GREEN}║${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Duration :" "${MM}m ${SS}s" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${CYAN}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Output :" "$OUTPUT_DIR" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

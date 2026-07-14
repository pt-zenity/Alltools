#!/bin/bash
# ============================================================
# Full Reconnaissance Scan Script v2.1
# Usage: ./full-scan.sh <target_url> [options]
# ============================================================
# NOTE: -e removed intentionally — tools may return non-zero
# exit codes and we must NOT abort the scan; each tool uses || true
set -uo pipefail

# ── Ensure Python venv tools (waymore, uro, xnLinkFinder) are on PATH ───────
export PATH="/opt/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:$PATH"
export VIRTUAL_ENV="/opt/venv"

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Severity badge colors
CRIT='\033[1;31m'   # bright red   — CRITICAL
HIGH='\033[0;31m'   # red          — HIGH
MED='\033[1;33m'    # yellow       — MEDIUM
LOW='\033[0;36m'    # cyan         — LOW
INFO_C='\033[0;34m' # blue         — INFO

TARGET="${1:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
THREADS="${THREADS:-50}"
DEPTH="${DEPTH:-3}"
TIMEOUT="${TIMEOUT:-10}"
SCAN_START=$(date +%s)

if [ -z "$TARGET" ]; then
    echo -e "${RED}[!] Error: Target URL required${NC}"
    echo -e "Usage: $0 <target_url> [options]"
    exit 1
fi

# Extract domain from URL
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||' | sed 's|:.*||')
OUTPUT_DIR="/workspace/output/${DOMAIN}_${TIMESTAMP}"

# ── Waymore max processes (hard limit: 1–5) ─────────────────
WAYMORE_PROCS=$(( THREADS > 5 ? 5 : THREADS ))

mkdir -p "$OUTPUT_DIR"/{katana,gau,gospider,waymore,xnlink,httpx,subdomains,combined,reports}

# ── Pre-create all output files (wc -l never fails) ─────────
touch "$OUTPUT_DIR/katana/results.txt"
touch "$OUTPUT_DIR/gau/results.txt"
touch "$OUTPUT_DIR/gospider/combined.txt"
touch "$OUTPUT_DIR/waymore/results.txt"
touch "$OUTPUT_DIR/waymore/wayback.txt"
touch "$OUTPUT_DIR/xnlink/results.txt"
touch "$OUTPUT_DIR/httpx/alive-urls.txt"
touch "$OUTPUT_DIR/combined/all-urls-raw.txt"
touch "$OUTPUT_DIR/combined/all-urls-dedup.txt"
touch "$OUTPUT_DIR/combined/urls-with-params.txt"
touch "$OUTPUT_DIR/combined/js-files.txt"
touch "$OUTPUT_DIR/combined/api-endpoints.txt"
touch "$OUTPUT_DIR/combined/admin-pages.txt"

# Pre-create gf output files
GF_PATTERN_NAMES=(xss sqli ssrf idor lfi rce redirect debug_logic secrets upload)
for _p in "${GF_PATTERN_NAMES[@]}"; do
    touch "$OUTPUT_DIR/combined/gf-${_p}.txt"
done

# ── Logging helpers ─────────────────────────────────────────
log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}
warn() {
    echo -e "${YELLOW}[WARN][$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}
info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}
ok() {
    local label="$1"; local count="$2"; local elapsed="$3"
    echo -e "  ${GREEN}[✓]${NC} ${BOLD}${label}${NC} ${DIM}→${NC} ${CYAN}${count}${NC} ${DIM}(${elapsed}s)${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}
skip() {
    echo -e "  ${DIM}[–] $1 — not installed, skipping${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}
sep() {
    echo -e "${DIM}  ────────────────────────────────────────────────${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

phase_banner() {
    local num="$1"; local title="$2"
    echo "" | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
    printf "${BOLD}${CYAN}║${NC}  ${BOLD}${WHITE}PHASE %s: %-44s${BOLD}${CYAN}║${NC}\n" \
        "$num" "$title" | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

tool_header() {
    local step="$1"; local name="$2"; local desc="$3"
    echo "" | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "  ${BOLD}${WHITE}┌─[${CYAN}${step}${WHITE}]${NC} ${BOLD}${name}${NC} ${DIM}— ${desc}${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

# ── run_tool: quiet mode — shows only progress dots, not raw output ──────────
# Raw output still goes to logfile for debugging.
# Prints a progress dot every 2 seconds while tool runs.
run_tool() {
    local label="$1"
    local logfile="$2"
    shift 2
    [ "${1:-}" = "--" ] && shift

    echo -e "  ${DIM}│  ${CYAN}▶ ${label}${NC} ${DIM}running...${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"

    # Run tool, pipe all output to logfile only (not terminal)
    "$@" >> "$logfile" 2>&1 &
    local pid=$!

    # Show progress dots while tool runs (one dot per 2 seconds)
    local dots=""
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 2
        count=$(( count + 1 ))
        dots="${dots}."
        # Every 10 dots, reset to keep line clean
        if [ $(( count % 10 )) -eq 0 ]; then
            echo -e "  ${DIM}│  ${CYAN}▷ ${label}${NC} ${DIM}still running... (${count}×2s)${NC}" \
                | tee -a "$OUTPUT_DIR/scan.log"
            dots=""
        fi
        printf "\r  ${DIM}│  ▷ ${label} %s${NC}" "$dots" 2>/dev/null || true
    done
    printf "\r%80s\r" "" 2>/dev/null || true  # clear progress line

    # Check exit status
    wait "$pid" 2>/dev/null || \
        warn "${label} exited with non-zero status (continuing)"

    echo -e "  ${DIM}│  ${GREEN}✓ ${label}${NC} ${DIM}done${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

elapsed_since() {
    echo $(( $(date +%s) - $1 ))
}

# ── Scan Header Banner ───────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}${WHITE}🕷️  WEB CRAWLER TOOLKIT 2026 — FULL RECON SCAN${NC}         ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Target  :" "$TARGET"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Domain  :" "$DOMAIN"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Output  :" "$OUTPUT_DIR"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Threads :" "$THREADS  (waymore capped at ${WAYMORE_PROCS}/5)"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Depth   :" "$DEPTH"
printf "${BOLD}${CYAN}║${NC}  ${DIM}%-14s${NC}  ${WHITE}%-40s${BOLD}${CYAN}║${NC}\n" "Timeout :" "${TIMEOUT}s"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────
# PHASE 1: URL Collection
# ─────────────────────────────────────────────────────────────
phase_banner "1" "URL COLLECTION  (6 tools)"

# 1.1 katana
STEP_START=$(date +%s)
if command -v katana &>/dev/null; then
    tool_header "1/6" "katana" "active crawling with JS execution"
    run_tool "katana" "$OUTPUT_DIR/katana/tool.log" \
        katana \
            -u "$TARGET" \
            -d "$DEPTH" \
            -c "$THREADS" \
            -timeout "$TIMEOUT" \
            -silent \
            -rl 150 \
            -o "$OUTPUT_DIR/katana/results.txt"
    KATANA_COUNT=$(wc -l < "$OUTPUT_DIR/katana/results.txt" 2>/dev/null || echo 0)
    ok "katana" "$KATANA_COUNT URLs" "$(elapsed_since $STEP_START)"
else
    skip "katana [1/6]"
    KATANA_COUNT=0
fi

# 1.2 gau
STEP_START=$(date +%s)
if command -v gau &>/dev/null; then
    tool_header "2/6" "gau" "wayback + commoncrawl + otx + urlscan"
    run_tool "gau" "$OUTPUT_DIR/gau/tool.log" \
        bash -c "echo '$DOMAIN' | gau \
            --threads '$THREADS' \
            --timeout '$TIMEOUT' \
            --providers wayback,commoncrawl,otx,urlscan \
            --blacklist png,jpg,gif,jpeg,webp,svg,ico,css,woff,woff2,ttf,eot \
            --o '$OUTPUT_DIR/gau/results.txt'"
    GAU_COUNT=$(wc -l < "$OUTPUT_DIR/gau/results.txt" 2>/dev/null || echo 0)
    ok "gau" "$GAU_COUNT URLs" "$(elapsed_since $STEP_START)"
else
    skip "gau [2/6]"
    GAU_COUNT=0
fi

# 1.3 gospider
STEP_START=$(date +%s)
if command -v gospider &>/dev/null; then
    tool_header "3/6" "gospider" "spider with sitemap + robots + JS sources"
    run_tool "gospider" "$OUTPUT_DIR/gospider/tool.log" \
        gospider \
            -s "$TARGET" \
            -o "$OUTPUT_DIR/gospider/" \
            -c "$THREADS" \
            -d "$DEPTH" \
            -t "$TIMEOUT" \
            --js \
            --sitemap \
            --robots \
            --other-source \
            -a
    cat "$OUTPUT_DIR/gospider/"* 2>/dev/null | \
        grep -oE "https?://[^ ]+" > "$OUTPUT_DIR/gospider/combined.txt" || true
    GOSPIDER_COUNT=$(wc -l < "$OUTPUT_DIR/gospider/combined.txt" 2>/dev/null || echo 0)
    ok "gospider" "$GOSPIDER_COUNT URLs" "$(elapsed_since $STEP_START)"
else
    skip "gospider [3/6]"
    GOSPIDER_COUNT=0
fi

# 1.4 waymore (processes capped at WAYMORE_PROCS ≤ 5)
STEP_START=$(date +%s)
if command -v waymore &>/dev/null; then
    tool_header "4/6" "waymore" "extended archive search  [processes capped: ${WAYMORE_PROCS}/5]"
    run_tool "waymore" "$OUTPUT_DIR/waymore/tool.log" \
        waymore \
            -i "$DOMAIN" \
            -mode U \
            -oU "$OUTPUT_DIR/waymore/results.txt" \
            -p "$WAYMORE_PROCS"
    WAYMORE_COUNT=$(wc -l < "$OUTPUT_DIR/waymore/results.txt" 2>/dev/null || echo 0)
    ok "waymore" "$WAYMORE_COUNT URLs" "$(elapsed_since $STEP_START)"
else
    skip "waymore [4/6]"
    WAYMORE_COUNT=0
fi

# 1.5 xnLinkFinder
STEP_START=$(date +%s)
if command -v xnLinkFinder &>/dev/null; then
    tool_header "5/6" "xnLinkFinder" "link extraction from crawled pages"
    run_tool "xnLinkFinder" "$OUTPUT_DIR/xnlink/tool.log" \
        xnLinkFinder \
            -i "$TARGET" \
            -op "$OUTPUT_DIR/xnlink/results.txt" \
            -sp "$TARGET" \
            -sf "$DOMAIN" \
            -d "$DEPTH" \
            -p "$THREADS"
    XNLINK_COUNT=$(wc -l < "$OUTPUT_DIR/xnlink/results.txt" 2>/dev/null || echo 0)
    ok "xnLinkFinder" "$XNLINK_COUNT URLs" "$(elapsed_since $STEP_START)"
else
    skip "xnLinkFinder [5/6]"
    XNLINK_COUNT=0
fi

# 1.6 waybackurls
STEP_START=$(date +%s)
if command -v waybackurls &>/dev/null; then
    tool_header "6/6" "waybackurls" "wayback machine URL history"
    run_tool "waybackurls" "$OUTPUT_DIR/waymore/wayback_tool.log" \
        bash -c "echo '$DOMAIN' | waybackurls > '$OUTPUT_DIR/waymore/wayback.txt'"
    WAYBACK_COUNT=$(wc -l < "$OUTPUT_DIR/waymore/wayback.txt" 2>/dev/null || echo 0)
    ok "waybackurls" "$WAYBACK_COUNT URLs" "$(elapsed_since $STEP_START)"
else
    skip "waybackurls [6/6]"
    WAYBACK_COUNT=0
fi

# ─────────────────────────────────────────────────────────────
# PHASE 2: URL Deduplication
# ─────────────────────────────────────────────────────────────
phase_banner "2" "URL DEDUPLICATION"

STEP_START=$(date +%s)
echo -e "  ${DIM}Merging all tool outputs...${NC}" | tee -a "$OUTPUT_DIR/scan.log"
cat "$OUTPUT_DIR/katana/results.txt" \
    "$OUTPUT_DIR/gau/results.txt" \
    "$OUTPUT_DIR/gospider/combined.txt" \
    "$OUTPUT_DIR/waymore/results.txt" \
    "$OUTPUT_DIR/waymore/wayback.txt" \
    "$OUTPUT_DIR/xnlink/results.txt" \
    2>/dev/null | \
    grep -E "^https?://" | \
    sort -u > "$OUTPUT_DIR/combined/all-urls-raw.txt" || true

COMBINED_RAW=$(wc -l < "$OUTPUT_DIR/combined/all-urls-raw.txt" 2>/dev/null || echo 0)
echo -e "  ${DIM}Combined raw (pre-dedup) :${NC} ${WHITE}${COMBINED_RAW}${NC}" | tee -a "$OUTPUT_DIR/scan.log"

if command -v uro &>/dev/null; then
    echo -e "  ${DIM}Running uro deduplication...${NC}" | tee -a "$OUTPUT_DIR/scan.log"
    uro < "$OUTPUT_DIR/combined/all-urls-raw.txt" > "$OUTPUT_DIR/combined/all-urls-dedup.txt" 2>/dev/null || true
    DEDUP_COUNT=$(wc -l < "$OUTPUT_DIR/combined/all-urls-dedup.txt" 2>/dev/null || echo 0)
    REMOVED=$(( COMBINED_RAW - DEDUP_COUNT ))
    ok "dedup (uro)" "$DEDUP_COUNT unique  — removed ${REMOVED} duplicates" "$(elapsed_since $STEP_START)"
else
    cp "$OUTPUT_DIR/combined/all-urls-raw.txt" "$OUTPUT_DIR/combined/all-urls-dedup.txt" || true
    DEDUP_COUNT=$COMBINED_RAW
    ok "dedup (sort -u only)" "$DEDUP_COUNT unique" "$(elapsed_since $STEP_START)"
fi

# ─────────────────────────────────────────────────────────────
# PHASE 3: HTTP Probing
# ─────────────────────────────────────────────────────────────
phase_banner "3" "HTTP PROBING"

STEP_START=$(date +%s)
if command -v httpx &>/dev/null; then
    tool_header "1/1" "httpx" "probe alive URLs, detect tech stack + status codes"
    run_tool "httpx" "$OUTPUT_DIR/httpx/tool.log" \
        httpx \
            -l "$OUTPUT_DIR/combined/all-urls-dedup.txt" \
            -o "$OUTPUT_DIR/httpx/alive-urls.txt" \
            -json "$OUTPUT_DIR/httpx/results.json" \
            -title \
            -status-code \
            -content-length \
            -content-type \
            -web-server \
            -tech-detect \
            -follow-redirects \
            -threads "$THREADS" \
            -timeout "$TIMEOUT"
    ALIVE_COUNT=$(wc -l < "$OUTPUT_DIR/httpx/alive-urls.txt" 2>/dev/null || echo 0)
    ok "httpx" "$ALIVE_COUNT alive URLs" "$(elapsed_since $STEP_START)"
else
    skip "httpx [1/1]"
    ALIVE_COUNT=0
fi

# ─────────────────────────────────────────────────────────────
# PHASE 4: Security Pattern Matching (gf)
# ─────────────────────────────────────────────────────────────
phase_banner "4" "SECURITY PATTERN MATCHING  (gf)"

STEP_START=$(date +%s)

# gf severity mapping: pattern → severity level
# Format: "pattern:severity_label:color_var"
GF_PATTERNS=(
    "xss:XSS:CRIT"
    "sqli:SQLi:CRIT"
    "ssrf:SSRF:HIGH"
    "rce:RCE:CRIT"
    "lfi:LFI:HIGH"
    "idor:IDOR:MED"
    "redirect:REDIRECT:MED"
    "secrets:SECRETS:HIGH"
    "upload:UPLOAD:MED"
    "debug_logic:DEBUG:LOW"
)

# Counters for each severity
CRIT_TOTAL=0
HIGH_TOTAL=0
MED_TOTAL=0
LOW_TOTAL=0

# Associative array: name → count (bash 4+ only; fallback via declare)
declare -A GF_COUNTS 2>/dev/null || true

if command -v gf &>/dev/null; then
    echo -e "  ${DIM}Scanning ${DEDUP_COUNT} URLs against 10 security patterns...${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
    echo "" | tee -a "$OUTPUT_DIR/scan.log"

    for pattern_info in "${GF_PATTERNS[@]}"; do
        name="${pattern_info%%:*}"
        rest="${pattern_info#*:}"
        label="${rest%%:*}"
        sev_var="${rest##*:}"

        output_file="$OUTPUT_DIR/combined/gf-${name}.txt"

        # Guard: skip if pattern not installed
        if ! gf "$name" /dev/null > /dev/null 2>&1; then
            printf "  ${DIM}%-12s  %-8s  %s${NC}\n" \
                "$label" "SKIP" "pattern not installed" | tee -a "$OUTPUT_DIR/scan.log"
            GF_COUNTS[$name]=0
            continue
        fi

        gf "$name" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > "$output_file" 2>/dev/null || true
        COUNT=$(wc -l < "$output_file" 2>/dev/null || echo 0)
        GF_COUNTS[$name]=$COUNT

        if [ "$COUNT" -gt 0 ]; then
            # Color based on severity
            case "$sev_var" in
                CRIT)  SEV_COLOR="$CRIT";  CRIT_TOTAL=$(( CRIT_TOTAL + COUNT )) ;;
                HIGH)  SEV_COLOR="$HIGH";  HIGH_TOTAL=$(( HIGH_TOTAL + COUNT )) ;;
                MED)   SEV_COLOR="$MED";   MED_TOTAL=$(( MED_TOTAL + COUNT ))   ;;
                LOW)   SEV_COLOR="$LOW";   LOW_TOTAL=$(( LOW_TOTAL + COUNT ))   ;;
                *)     SEV_COLOR="$NC" ;;
            esac
            printf "  ${SEV_COLOR}[!] %-10s${NC}  ${BOLD}%-8s${NC}  ${YELLOW}%d potential findings${NC}\n" \
                "[$sev_var]" "$label" "$COUNT" | tee -a "$OUTPUT_DIR/scan.log"
        else
            printf "  ${GREEN}[✓] %-10s${NC}  ${DIM}%-8s  %d${NC}\n" \
                "[CLEAN]" "$label" "$COUNT" | tee -a "$OUTPUT_DIR/scan.log"
        fi
    done

    GF_GRAND_TOTAL=$(( CRIT_TOTAL + HIGH_TOTAL + MED_TOTAL + LOW_TOTAL ))

    echo "" | tee -a "$OUTPUT_DIR/scan.log"

    # ── Inline SECURITY FINDINGS summary ───────────────────────
    echo -e "${BOLD}${WHITE}  ┌────────────────────────────────────────────────┐${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${BOLD}${WHITE}  │         SECURITY FINDINGS SUMMARY              │${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${BOLD}${WHITE}  ├──────────────┬──────────────────────────────────┤${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"

    # CRITICAL row
    if [ "$CRIT_TOTAL" -gt 0 ]; then
        printf "  ${BOLD}${WHITE}│${NC}  ${CRIT}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${CRIT}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🔴 CRITICAL" "${CRIT_TOTAL} findings  (XSS, SQLi, RCE)" \
            | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${GREEN}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${DIM}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🟢 CRITICAL" "0 findings — clean" | tee -a "$OUTPUT_DIR/scan.log"
    fi

    # HIGH row
    if [ "$HIGH_TOTAL" -gt 0 ]; then
        printf "  ${BOLD}${WHITE}│${NC}  ${HIGH}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${HIGH}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🟠 HIGH" "${HIGH_TOTAL} findings  (SSRF, LFI, Secrets)" \
            | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${GREEN}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${DIM}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🟢 HIGH" "0 findings — clean" | tee -a "$OUTPUT_DIR/scan.log"
    fi

    # MEDIUM row
    if [ "$MED_TOTAL" -gt 0 ]; then
        printf "  ${BOLD}${WHITE}│${NC}  ${MED}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${MED}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🟡 MEDIUM" "${MED_TOTAL} findings  (IDOR, Redirect, Upload)" \
            | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${GREEN}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${DIM}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🟢 MEDIUM" "0 findings — clean" | tee -a "$OUTPUT_DIR/scan.log"
    fi

    # LOW row
    if [ "$LOW_TOTAL" -gt 0 ]; then
        printf "  ${BOLD}${WHITE}│${NC}  ${LOW}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${LOW}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🔵 LOW" "${LOW_TOTAL} findings  (Debug Logic)" \
            | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${GREEN}%-12s${NC}  ${BOLD}${WHITE}│${NC}  ${DIM}%-34s${BOLD}${WHITE}│${NC}\n" \
            "🟢 LOW" "0 findings — clean" | tee -a "$OUTPUT_DIR/scan.log"
    fi

    echo -e "${BOLD}${WHITE}  └──────────────┴──────────────────────────────────┘${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"

    ok "gf patterns" "$GF_GRAND_TOTAL total potential findings" "$(elapsed_since $STEP_START)"
else
    skip "gf (pattern scanner)"
    GF_GRAND_TOTAL=0
    CRIT_TOTAL=0; HIGH_TOTAL=0; MED_TOTAL=0; LOW_TOTAL=0
    for _p in "${GF_PATTERN_NAMES[@]}"; do
        GF_COUNTS[$_p]=0
    done
fi

# ─────────────────────────────────────────────────────────────
# PHASE 5: URL Categorization
# ─────────────────────────────────────────────────────────────
phase_banner "5" "URL CATEGORIZATION"

STEP_START=$(date +%s)
echo -e "  ${DIM}Categorizing ${DEDUP_COUNT} unique URLs...${NC}" | tee -a "$OUTPUT_DIR/scan.log"

grep -E "\?" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/urls-with-params.txt" 2>/dev/null || true

grep -E "\.js(\?|$)" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/js-files.txt" 2>/dev/null || true

grep -E "/api/|/v[0-9]+/|/rest/|/graphql" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/api-endpoints.txt" 2>/dev/null || true

grep -iE "admin|panel|dashboard|manage|backend|config|setup" \
    "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/admin-pages.txt" 2>/dev/null || true

PARAMS_COUNT=$(wc -l < "$OUTPUT_DIR/combined/urls-with-params.txt" 2>/dev/null || echo 0)
JS_COUNT=$(wc -l < "$OUTPUT_DIR/combined/js-files.txt" 2>/dev/null || echo 0)
API_COUNT=$(wc -l < "$OUTPUT_DIR/combined/api-endpoints.txt" 2>/dev/null || echo 0)
ADMIN_COUNT=$(wc -l < "$OUTPUT_DIR/combined/admin-pages.txt" 2>/dev/null || echo 0)

echo "" | tee -a "$OUTPUT_DIR/scan.log"
printf "  ${DIM}%-25s${NC}  ${BOLD}${WHITE}%s${NC}\n" "URLs with parameters :" "$PARAMS_COUNT" \
    | tee -a "$OUTPUT_DIR/scan.log"
printf "  ${DIM}%-25s${NC}  ${BOLD}${WHITE}%s${NC}\n" "JavaScript files     :" "$JS_COUNT" \
    | tee -a "$OUTPUT_DIR/scan.log"
printf "  ${DIM}%-25s${NC}  ${BOLD}${WHITE}%s${NC}\n" "API endpoints        :" "$API_COUNT" \
    | tee -a "$OUTPUT_DIR/scan.log"
printf "  ${DIM}%-25s${NC}  ${BOLD}${WHITE}%s${NC}\n" "Admin pages          :" "$ADMIN_COUNT" \
    | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"
ok "categorization" "done" "$(elapsed_since $STEP_START)"

# ─────────────────────────────────────────────────────────────
# PHASE 6: Generate Report
# ─────────────────────────────────────────────────────────────
phase_banner "6" "FINAL REPORT"

SCAN_END=$(date +%s)
TOTAL_ELAPSED=$(( SCAN_END - SCAN_START ))
TOTAL_MM=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SS=$(( TOTAL_ELAPSED % 60 ))

REPORT_FILE="$OUTPUT_DIR/reports/scan-report.txt"

# ── Write clean plain-text report (no ANSI color codes) ──────
{
printf '%-64s\n' ""
printf '==================================================================\n'
printf '   WEB CRAWLER TOOLKIT 2026 — FULL SCAN REPORT\n'
printf '==================================================================\n'
printf '\n'
printf '  %-18s %s\n'  "Target     :"  "$TARGET"
printf '  %-18s %s\n'  "Domain     :"  "$DOMAIN"
printf '  %-18s %s\n'  "Scan Date  :"  "$(date '+%Y-%m-%d %H:%M:%S')"
printf '  %-18s %dm %ds\n' "Duration   :"  "$TOTAL_MM" "$TOTAL_SS"
printf '  %-18s %s\n'  "Output Dir :"  "$OUTPUT_DIR"
printf '\n'
printf '==================================================================\n'
printf '  SECTION 1 — URL COLLECTION RESULTS\n'
printf '==================================================================\n'
printf '\n'
printf '  %-22s  %10s\n' "Tool" "URLs Found"
printf '  %-22s  %10s\n' "──────────────────────" "──────────"
printf '  %-22s  %10s\n' "katana"         "$KATANA_COUNT"
printf '  %-22s  %10s\n' "gau"            "$GAU_COUNT"
printf '  %-22s  %10s\n' "gospider"       "$GOSPIDER_COUNT"
printf '  %-22s  %10s\n' "waymore"        "$WAYMORE_COUNT"
printf '  %-22s  %10s\n' "waybackurls"    "$WAYBACK_COUNT"
printf '  %-22s  %10s\n' "xnLinkFinder"   "$XNLINK_COUNT"
printf '  %-22s  %10s\n' "──────────────────────" "──────────"
printf '  %-22s  %10s\n' "Combined (raw)"     "$COMBINED_RAW"
printf '  %-22s  %10s\n' "After dedup (uro)"  "$DEDUP_COUNT"
printf '  %-22s  %10s\n' "Alive (httpx)"      "$ALIVE_COUNT"
printf '\n'
printf '==================================================================\n'
printf '  SECTION 2 — SECURITY FINDINGS  (gf pattern scan)\n'
printf '==================================================================\n'
printf '\n'

# Determine overall risk level
if   [ "$CRIT_TOTAL" -gt 0 ]; then RISK_LABEL="*** CRITICAL RISK ***"
elif [ "$HIGH_TOTAL" -gt 0 ]; then RISK_LABEL="** HIGH RISK **"
elif [ "$MED_TOTAL"  -gt 0 ]; then RISK_LABEL="* MEDIUM RISK *"
elif [ "$LOW_TOTAL"  -gt 0 ]; then RISK_LABEL="LOW RISK"
else                                RISK_LABEL="ALL CLEAN"
fi

printf '  Overall Risk Level : %s\n' "$RISK_LABEL"
printf '  Total Findings     : %d\n' "$GF_GRAND_TOTAL"
printf '\n'
printf '  %-18s  %8s  %s\n' "Pattern" "Findings" "Severity"
printf '  %-18s  %8s  %s\n' "──────────────────" "────────" "────────"

for pattern_info in \
    "xss:XSS:CRITICAL" \
    "sqli:SQLi:CRITICAL" \
    "ssrf:SSRF:HIGH" \
    "rce:RCE:CRITICAL" \
    "lfi:LFI:HIGH" \
    "idor:IDOR:MEDIUM" \
    "redirect:REDIRECT:MEDIUM" \
    "secrets:SECRETS:HIGH" \
    "upload:UPLOAD:MEDIUM" \
    "debug_logic:DEBUG:LOW"
do
    _n="${pattern_info%%:*}"
    _rest="${pattern_info#*:}"
    _lbl="${_rest%%:*}"
    _sev="${_rest##*:}"
    _cnt="${GF_COUNTS[$_n]:-0}"
    if [ "$_cnt" -gt 0 ]; then
        printf '  %-18s  %8d  [%s] *** ATTENTION ***\n' "$_lbl" "$_cnt" "$_sev"
    else
        printf '  %-18s  %8d  [%s]\n' "$_lbl" "$_cnt" "$_sev"
    fi
done

printf '\n'
printf '==================================================================\n'
printf '  SECTION 3 — URL CATEGORIES\n'
printf '==================================================================\n'
printf '\n'
printf '  %-30s  %8s\n' "Category" "Count"
printf '  %-30s  %8s\n' "──────────────────────────────" "────────"
printf '  %-30s  %8s\n' "URLs with parameters"  "$PARAMS_COUNT"
printf '  %-30s  %8s\n' "JavaScript files"      "$JS_COUNT"
printf '  %-30s  %8s\n' "API endpoints"         "$API_COUNT"
printf '  %-30s  %8s\n' "Admin / sensitive pages" "$ADMIN_COUNT"
printf '\n'
printf '==================================================================\n'
printf '  SECTION 4 — OUTPUT FILES\n'
printf '==================================================================\n'
printf '\n'
printf '  All URLs (raw)         :  combined/all-urls-raw.txt\n'
printf '  All URLs (dedup)       :  combined/all-urls-dedup.txt\n'
printf '  URLs with parameters   :  combined/urls-with-params.txt\n'
printf '  JavaScript files       :  combined/js-files.txt\n'
printf '  API endpoints          :  combined/api-endpoints.txt\n'
printf '  Admin pages            :  combined/admin-pages.txt\n'
printf '  Alive URLs (httpx)     :  httpx/alive-urls.txt\n'
printf '  httpx JSON detail      :  httpx/results.json\n'
printf '\n'
printf '  gf Security Findings:\n'
for _p in xss sqli ssrf rce lfi idor redirect secrets upload debug_logic; do
    printf '    %-20s :  combined/gf-%s.txt\n' "gf-${_p}" "$_p"
done
printf '\n'
printf '  Scan logs              :  scan.log  (full output)\n'
printf '\n'
printf '==================================================================\n'
printf '  Scan completed in %dm %ds\n' "$TOTAL_MM" "$TOTAL_SS"
printf '==================================================================\n'
} > "$REPORT_FILE"

# ── Print the report to the terminal with colors ─────────────
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${BOLD}${WHITE}📋  SCAN REPORT${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

# Section 1: Collection results table (colored, aligned)
echo -e "  ${BOLD}${CYAN}[ URL COLLECTION RESULTS ]${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ┌────────────────────────┬────────────┐${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}Tool${NC}                    ${BOLD}${WHITE}│${NC}  ${DIM}URLs Found${NC}  ${BOLD}${WHITE}│${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ├────────────────────────┼────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

print_row() {
    local tool="$1"; local count="$2"
    if [ "$count" -gt 0 ] 2>/dev/null; then
        printf "  ${BOLD}${WHITE}│${NC}  %-22s  ${BOLD}${WHITE}│${NC}  ${CYAN}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$tool" "$count" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-22s  │  %8s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$tool" "$count" | tee -a "$OUTPUT_DIR/scan.log"
    fi
}

print_row "katana"        "$KATANA_COUNT"
print_row "gau"           "$GAU_COUNT"
print_row "gospider"      "$GOSPIDER_COUNT"
print_row "waymore"       "$WAYMORE_COUNT"
print_row "waybackurls"   "$WAYBACK_COUNT"
print_row "xnLinkFinder"  "$XNLINK_COUNT"
echo -e "${BOLD}${WHITE}  ├────────────────────────┼────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf   "  ${BOLD}${WHITE}│${NC}  %-22s  ${BOLD}${WHITE}│${NC}  ${WHITE}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" \
    "Combined (raw)" "$COMBINED_RAW" | tee -a "$OUTPUT_DIR/scan.log"
printf   "  ${BOLD}${WHITE}│${NC}  %-22s  ${BOLD}${WHITE}│${NC}  ${WHITE}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" \
    "After dedup" "$DEDUP_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
printf   "  ${BOLD}${WHITE}│${NC}  %-22s  ${BOLD}${WHITE}│${NC}  ${GREEN}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" \
    "Alive (httpx)" "$ALIVE_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  └────────────────────────┴────────────┘${NC}" | tee -a "$OUTPUT_DIR/scan.log"

echo "" | tee -a "$OUTPUT_DIR/scan.log"

# Section 2: Security findings (colored severity)
echo -e "  ${BOLD}${CYAN}[ SECURITY FINDINGS — gf Pattern Scan ]${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ┌─────────────────┬──────────┬───────────────────────────┐${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}Pattern${NC}          ${BOLD}${WHITE}│${NC}  ${DIM}Count${NC}   ${BOLD}${WHITE}│${NC}  ${DIM}Severity${NC}                   ${BOLD}${WHITE}│${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ├─────────────────┼──────────┼───────────────────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

print_gf_row() {
    local label="$1"; local count="$2"; local sev="$3"; local sev_label="$4"
    local count_color sev_color
    if [ "$count" -gt 0 ] 2>/dev/null; then
        case "$sev" in
            CRIT) count_color="$CRIT"; sev_color="$CRIT" ;;
            HIGH) count_color="$HIGH"; sev_color="$HIGH" ;;
            MED)  count_color="$MED";  sev_color="$MED"  ;;
            LOW)  count_color="$LOW";  sev_color="$LOW"  ;;
            *)    count_color="$WHITE"; sev_color="$WHITE" ;;
        esac
        printf "  ${BOLD}${WHITE}│${NC}  ${count_color}%-15s${NC}  ${BOLD}${WHITE}│${NC}  ${count_color}%6s${NC}  ${BOLD}${WHITE}│${NC}  ${sev_color}%-25s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" "$sev_label" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-15s  │  %6s  │  %-25s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" "$sev_label" | tee -a "$OUTPUT_DIR/scan.log"
    fi
}

print_gf_row "XSS"       "${GF_COUNTS[xss]:-0}"         "CRIT" "🔴 CRITICAL"
print_gf_row "SQLi"      "${GF_COUNTS[sqli]:-0}"        "CRIT" "🔴 CRITICAL"
print_gf_row "RCE"       "${GF_COUNTS[rce]:-0}"         "CRIT" "🔴 CRITICAL"
print_gf_row "SSRF"      "${GF_COUNTS[ssrf]:-0}"        "HIGH" "🟠 HIGH"
print_gf_row "LFI"       "${GF_COUNTS[lfi]:-0}"         "HIGH" "🟠 HIGH"
print_gf_row "Secrets"   "${GF_COUNTS[secrets]:-0}"     "HIGH" "🟠 HIGH"
print_gf_row "IDOR"      "${GF_COUNTS[idor]:-0}"        "MED"  "🟡 MEDIUM"
print_gf_row "Redirect"  "${GF_COUNTS[redirect]:-0}"    "MED"  "🟡 MEDIUM"
print_gf_row "Upload"    "${GF_COUNTS[upload]:-0}"      "MED"  "🟡 MEDIUM"
print_gf_row "Debug"     "${GF_COUNTS[debug_logic]:-0}" "LOW"  "🔵 LOW"

echo -e "${BOLD}${WHITE}  ├─────────────────┼──────────┼───────────────────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

# Grand total with overall risk color
if   [ "$CRIT_TOTAL" -gt 0 ]; then TOT_COLOR="$CRIT"; RISK_BADGE="🔴 CRITICAL RISK"
elif [ "$HIGH_TOTAL" -gt 0 ]; then TOT_COLOR="$HIGH"; RISK_BADGE="🟠 HIGH RISK"
elif [ "$MED_TOTAL"  -gt 0 ]; then TOT_COLOR="$MED";  RISK_BADGE="🟡 MEDIUM RISK"
elif [ "$LOW_TOTAL"  -gt 0 ]; then TOT_COLOR="$LOW";  RISK_BADGE="🔵 LOW RISK"
else                                TOT_COLOR="$GREEN"; RISK_BADGE="🟢 ALL CLEAN"
fi

printf "  ${BOLD}${WHITE}│${NC}  ${TOT_COLOR}%-15s${NC}  ${BOLD}${WHITE}│${NC}  ${TOT_COLOR}%6s${NC}  ${BOLD}${WHITE}│${NC}  ${TOT_COLOR}%-25s${NC}  ${BOLD}${WHITE}│${NC}\n" \
    "TOTAL" "$GF_GRAND_TOTAL" "$RISK_BADGE" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  └─────────────────┴──────────┴───────────────────────────┘${NC}" | tee -a "$OUTPUT_DIR/scan.log"

echo "" | tee -a "$OUTPUT_DIR/scan.log"

# Section 3: URL categories table
echo -e "  ${BOLD}${CYAN}[ URL CATEGORIES ]${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ┌──────────────────────────┬────────────┐${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  │${NC}  ${DIM}Category${NC}                  ${BOLD}${WHITE}│${NC}  ${DIM}Count${NC}       ${BOLD}${WHITE}│${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${WHITE}  ├──────────────────────────┼────────────┤${NC}" | tee -a "$OUTPUT_DIR/scan.log"

print_cat_row() {
    local label="$1"; local count="$2"
    if [ "$count" -gt 0 ] 2>/dev/null; then
        printf "  ${BOLD}${WHITE}│${NC}  %-24s  ${BOLD}${WHITE}│${NC}  ${CYAN}%8s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" | tee -a "$OUTPUT_DIR/scan.log"
    else
        printf "  ${BOLD}${WHITE}│${NC}  ${DIM}%-24s  │  %8s${NC}  ${BOLD}${WHITE}│${NC}\n" \
            "$label" "$count" | tee -a "$OUTPUT_DIR/scan.log"
    fi
}

print_cat_row "URLs with parameters"   "$PARAMS_COUNT"
print_cat_row "JavaScript files"       "$JS_COUNT"
print_cat_row "API endpoints"          "$API_COUNT"
print_cat_row "Admin / sensitive pages" "$ADMIN_COUNT"
echo -e "${BOLD}${WHITE}  └──────────────────────────┴────────────┘${NC}" | tee -a "$OUTPUT_DIR/scan.log"

echo "" | tee -a "$OUTPUT_DIR/scan.log"

# ── Final summary banner ─────────────────────────────────────
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}║${NC}  ${BOLD}${WHITE}✅  SCAN COMPLETE${NC}                                        ${BOLD}${GREEN}║${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Total URLs found :" "${DEDUP_COUNT}  (${COMBINED_RAW} raw)" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Alive URLs :"       "$ALIVE_COUNT" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${TOT_COLOR}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Security risk :"    "$RISK_BADGE  ($GF_GRAND_TOTAL findings)" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${BOLD}${WHITE}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Scan duration :"    "${TOTAL_MM}m ${TOTAL_SS}s" | tee -a "$OUTPUT_DIR/scan.log"
printf "${BOLD}${GREEN}║${NC}  ${DIM}%-20s${NC}  ${CYAN}%-35s${NC}  ${BOLD}${GREEN}║${NC}\n" "Report file :"      "$REPORT_FILE" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

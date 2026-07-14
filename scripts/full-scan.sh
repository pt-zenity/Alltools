#!/bin/bash
# ============================================================
# Full Reconnaissance Scan Script
# Usage: ./full-scan.sh <target_url> [options]
# ============================================================

# NOTE: -e removed intentionally — tools may return non-zero exit codes
# and we must NOT abort the whole scan; each tool gets || true
set -uo pipefail

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

# Pre-create output files so wc -l never fails even if tool exits early
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

# ── Logging helpers ─────────────────────────────────────────
log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

warn() {
    echo -e "${YELLOW}[WARN][$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

info() {
    echo -e "${BLUE}[INFO][$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

ok() {
    # Print a green checkmark status line: [✓] label → count items in Xs
    local label="$1"
    local count="$2"
    local elapsed="$3"
    echo -e "${GREEN}  [✓] ${WHITE}${label}${NC} ${DIM}→${NC} ${CYAN}${count} items${NC} ${DIM}(${elapsed}s)${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

skip() {
    echo -e "${DIM}  [–] $1 — not installed, skipping${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

# Banner separator line
sep() {
    echo -e "${DIM}  ────────────────────────────────────────────────${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

phase_banner() {
    local num="$1"
    local title="$2"
    echo "" | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
    printf "${BOLD}${CYAN}║${NC}  ${BOLD}${WHITE}PHASE %s: %-44s${CYAN}║${NC}\n" \
        "$num" "$title" | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

tool_header() {
    # [n/N] tool_name — brief description
    local step="$1"
    local name="$2"
    local desc="$3"
    echo "" | tee -a "$OUTPUT_DIR/scan.log"
    echo -e "${BOLD}${WHITE}  ┌─[${CYAN}${step}${WHITE}]${NC} ${BOLD}${name}${NC} ${DIM}— ${desc}${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

run_tool() {
    # run_tool <label> <logfile> <cmd...>
    # Streams every stdout+stderr line live through tee into logfile.
    # Never aborts the parent script on non-zero exit.
    local label="$1"
    local logfile="$2"
    shift 2
    # skip the "--" separator if present
    [ "${1:-}" = "--" ] && shift
    echo -e "${DIM}  │  ${CYAN}[$(date +%H:%M:%S)][${label}]${NC} ${DIM}starting...${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
    # stdbuf -oL forces line-buffered C stdio so Go/Python tools don't batch output
    stdbuf -oL "$@" 2>&1 | tee -a "$logfile" | tee -a "$OUTPUT_DIR/scan.log" || \
        warn "${label} exited with non-zero status (continuing)"
    echo -e "${DIM}  │  ${CYAN}[$(date +%H:%M:%S)][${label}]${NC} ${DIM}done.${NC}" \
        | tee -a "$OUTPUT_DIR/scan.log"
}

elapsed_since() {
    echo $(( $(date +%s) - $1 ))
}

# ── Scan Header Banner ───────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║        🕷️  FULL RECONNAISSANCE SCAN 2026  🕷️          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${DIM}Target  :${NC} ${WHITE}$TARGET${NC}"
echo -e "  ${DIM}Domain  :${NC} ${WHITE}$DOMAIN${NC}"
echo -e "  ${DIM}Output  :${NC} ${CYAN}$OUTPUT_DIR${NC}"
echo -e "  ${DIM}Threads :${NC} ${WHITE}$THREADS${NC}  ${DIM}(waymore capped at ${WAYMORE_PROCS})${NC}"
echo -e "  ${DIM}Depth   :${NC} ${WHITE}$DEPTH${NC}"
echo -e "  ${DIM}Timeout :${NC} ${WHITE}${TIMEOUT}s${NC}"
echo ""
sep

# ─────────────────────────────────────────────────────────────
# PHASE 1: URL Collection
# ─────────────────────────────────────────────────────────────
phase_banner "1" "URL COLLECTION"

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
            -jc \
            -fx \
            -xhr \
            -aff \
            -rl 150 \
            -o "$OUTPUT_DIR/katana/results.txt" \
            -jsonl "$OUTPUT_DIR/katana/results.jsonl"
    KATANA_COUNT=$(wc -l < "$OUTPUT_DIR/katana/results.txt" 2>/dev/null || echo 0)
    ok "katana" "$KATANA_COUNT" "$(elapsed_since $STEP_START)"
else
    skip "katana [1/6]"
    KATANA_COUNT=0
fi

# 1.2 gau
STEP_START=$(date +%s)
if command -v gau &>/dev/null; then
    tool_header "2/6" "gau" "wayback machine + commoncrawl + otx + urlscan"
    run_tool "gau" "$OUTPUT_DIR/gau/tool.log" \
        bash -c "echo '$DOMAIN' | stdbuf -oL gau \
            --threads '$THREADS' \
            --timeout '$TIMEOUT' \
            --providers wayback,commoncrawl,otx,urlscan \
            --blacklist png,jpg,gif,jpeg,webp,svg,ico,css,woff,woff2,ttf,eot \
            --o '$OUTPUT_DIR/gau/results.txt'"
    GAU_COUNT=$(wc -l < "$OUTPUT_DIR/gau/results.txt" 2>/dev/null || echo 0)
    ok "gau" "$GAU_COUNT" "$(elapsed_since $STEP_START)"
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
    # Merge all gospider output files into one
    cat "$OUTPUT_DIR/gospider/"* 2>/dev/null | \
        grep -oE "https?://[^ ]+" > "$OUTPUT_DIR/gospider/combined.txt" || true
    GOSPIDER_COUNT=$(wc -l < "$OUTPUT_DIR/gospider/combined.txt" 2>/dev/null || echo 0)
    ok "gospider" "$GOSPIDER_COUNT" "$(elapsed_since $STEP_START)"
else
    skip "gospider [3/6]"
    GOSPIDER_COUNT=0
fi

# 1.4 waymore
# IMPORTANT: waymore -p/--processes max is 5 — cap it here
STEP_START=$(date +%s)
if command -v waymore &>/dev/null; then
    tool_header "4/6" "waymore" "extended archive search (processes capped at ${WAYMORE_PROCS}/5)"
    # Pre-create the file so wc -l never hits "No such file" even if waymore
    # exits before writing (e.g. when it fails argument validation)
    touch "$OUTPUT_DIR/waymore/results.txt"
    run_tool "waymore" "$OUTPUT_DIR/waymore/tool.log" \
        waymore \
            -i "$DOMAIN" \
            -mode U \
            -oU "$OUTPUT_DIR/waymore/results.txt" \
            -p "$WAYMORE_PROCS"
    WAYMORE_COUNT=$(wc -l < "$OUTPUT_DIR/waymore/results.txt" 2>/dev/null || echo 0)
    ok "waymore" "$WAYMORE_COUNT" "$(elapsed_since $STEP_START)"
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
    ok "xnLinkFinder" "$XNLINK_COUNT" "$(elapsed_since $STEP_START)"
else
    skip "xnLinkFinder [5/6]"
    XNLINK_COUNT=0
fi

# 1.6 waybackurls
STEP_START=$(date +%s)
if command -v waybackurls &>/dev/null; then
    tool_header "6/6" "waybackurls" "wayback machine URL history"
    run_tool "waybackurls" "$OUTPUT_DIR/waymore/wayback_tool.log" \
        bash -c "echo '$DOMAIN' | stdbuf -oL waybackurls > '$OUTPUT_DIR/waymore/wayback.txt'"
    WAYBACK_COUNT=$(wc -l < "$OUTPUT_DIR/waymore/wayback.txt" 2>/dev/null || echo 0)
    ok "waybackurls" "$WAYBACK_COUNT" "$(elapsed_since $STEP_START)"
else
    skip "waybackurls [6/6]"
    WAYBACK_COUNT=0
fi

# ─────────────────────────────────────────────────────────────
# PHASE 2: URL Deduplication
# ─────────────────────────────────────────────────────────────
phase_banner "2" "URL DEDUPLICATION"

STEP_START=$(date +%s)
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
info "  Combined raw (pre-dedup)  : $COMBINED_RAW URLs"

# Deduplicate with uro if available
if command -v uro &>/dev/null; then
    info "  Running uro deduplication..."
    uro < "$OUTPUT_DIR/combined/all-urls-raw.txt" > "$OUTPUT_DIR/combined/all-urls-dedup.txt" 2>/dev/null || true
    DEDUP_COUNT=$(wc -l < "$OUTPUT_DIR/combined/all-urls-dedup.txt" 2>/dev/null || echo 0)
    REMOVED=$(( COMBINED_RAW - DEDUP_COUNT ))
    ok "dedup (uro)" "$DEDUP_COUNT unique  (removed ${REMOVED} dupes)" "$(elapsed_since $STEP_START)"
else
    cp "$OUTPUT_DIR/combined/all-urls-raw.txt" "$OUTPUT_DIR/combined/all-urls-dedup.txt" || true
    DEDUP_COUNT=$COMBINED_RAW
    ok "dedup (sort -u only)" "$DEDUP_COUNT" "$(elapsed_since $STEP_START)"
fi

# ─────────────────────────────────────────────────────────────
# PHASE 3: HTTP Probing
# ─────────────────────────────────────────────────────────────
phase_banner "3" "HTTP PROBING"

STEP_START=$(date +%s)
if command -v httpx &>/dev/null; then
    tool_header "1/1" "httpx" "probe alive URLs, detect tech stack"
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
    ok "httpx" "$ALIVE_COUNT alive" "$(elapsed_since $STEP_START)"
else
    skip "httpx"
    ALIVE_COUNT=0
fi

# ─────────────────────────────────────────────────────────────
# PHASE 4: URL Categorization
# ─────────────────────────────────────────────────────────────
phase_banner "4" "URL CATEGORIZATION"

STEP_START=$(date +%s)
if command -v gf &>/dev/null; then
    info "  Running gf pattern matching..."

    GF_PATTERNS=(
        "xss:xss"
        "sqli:sqli"
        "ssrf:ssrf"
        "idor:idor"
        "lfi:lfi"
        "rce:rce"
        "redirect:redirect"
        "debug_logic:debug_logic"
        "secrets:secrets"
        "upload:upload"
    )

    for pattern_info in "${GF_PATTERNS[@]}"; do
        name="${pattern_info%%:*}"
        pattern="${pattern_info##*:}"
        output_file="$OUTPUT_DIR/combined/gf-${name}.txt"
        touch "$output_file"
        gf "$pattern" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > "$output_file" 2>/dev/null || true
        COUNT=$(wc -l < "$output_file" 2>/dev/null || echo 0)
        if [ "$COUNT" -gt 0 ]; then
            echo -e "  ${GREEN}[!]${NC} ${BOLD}gf-${name}${NC} ${DIM}→${NC} ${YELLOW}${COUNT} potential findings${NC}" \
                | tee -a "$OUTPUT_DIR/scan.log"
        else
            echo -e "  ${DIM}    gf-${name} → ${COUNT}${NC}" | tee -a "$OUTPUT_DIR/scan.log"
        fi
    done
    ok "gf patterns" "done" "$(elapsed_since $STEP_START)"
else
    skip "gf (gf patterns)"
fi

# ─────────────────────────────────────────────────────────────
# PHASE 5: URL Analysis
# ─────────────────────────────────────────────────────────────
phase_banner "5" "URL ANALYSIS"

STEP_START=$(date +%s)

grep -E "\?" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/urls-with-params.txt" 2>/dev/null || true

grep -E "\.js(\?|$)" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/js-files.txt" 2>/dev/null || true

grep -E "/api/|/v[0-9]+/|/rest/|/graphql" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/api-endpoints.txt" 2>/dev/null || true

grep -iE "admin|panel|dashboard|manage|backend|config|setup" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/admin-pages.txt" 2>/dev/null || true

PARAMS_COUNT=$(wc -l < "$OUTPUT_DIR/combined/urls-with-params.txt" 2>/dev/null || echo 0)
JS_COUNT=$(wc -l < "$OUTPUT_DIR/combined/js-files.txt" 2>/dev/null || echo 0)
API_COUNT=$(wc -l < "$OUTPUT_DIR/combined/api-endpoints.txt" 2>/dev/null || echo 0)
ADMIN_COUNT=$(wc -l < "$OUTPUT_DIR/combined/admin-pages.txt" 2>/dev/null || echo 0)

echo -e "  ${DIM}URLs with parameters :${NC} ${WHITE}${PARAMS_COUNT}${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${DIM}JavaScript files     :${NC} ${WHITE}${JS_COUNT}${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${DIM}API endpoints        :${NC} ${WHITE}${API_COUNT}${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${DIM}Admin pages          :${NC} ${WHITE}${ADMIN_COUNT}${NC}" | tee -a "$OUTPUT_DIR/scan.log"
ok "analysis" "done" "$(elapsed_since $STEP_START)"

# ─────────────────────────────────────────────────────────────
# PHASE 6: Generate Report
# ─────────────────────────────────────────────────────────────
phase_banner "6" "FINAL REPORT"

SCAN_END=$(date +%s)
TOTAL_ELAPSED=$(( SCAN_END - SCAN_START ))
TOTAL_MM=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SS=$(( TOTAL_ELAPSED % 60 ))

REPORT_FILE="$OUTPUT_DIR/reports/scan-report.txt"
cat > "$REPORT_FILE" << EOF
╔══════════════════════════════════════════════════════════════╗
║          WEB CRAWLER TOOLKIT 2026 — SCAN REPORT              ║
╚══════════════════════════════════════════════════════════════╝

  Target     : $TARGET
  Domain     : $DOMAIN
  Scan Date  : $(date '+%Y-%m-%d %H:%M:%S')
  Duration   : ${TOTAL_MM}m ${TOTAL_SS}s
  Output Dir : $OUTPUT_DIR

┌──────────────────────────── URL COLLECTION ─────────────────────────────┐
│  Tool             │  URLs Found                                           │
├───────────────────┼──────────────────────────────────────────────────────┤
│  katana           │  ${KATANA_COUNT}
│  gau              │  ${GAU_COUNT}
│  gospider         │  ${GOSPIDER_COUNT}
│  waymore          │  ${WAYMORE_COUNT}
│  waybackurls      │  ${WAYBACK_COUNT}
│  xnLinkFinder     │  ${XNLINK_COUNT}
├───────────────────┼──────────────────────────────────────────────────────┤
│  Combined (raw)   │  ${COMBINED_RAW}
│  After dedup      │  ${DEDUP_COUNT}
│  Alive (httpx)    │  ${ALIVE_COUNT}
└───────────────────┴──────────────────────────────────────────────────────┘

┌──────────────────────────── URL CATEGORIES ─────────────────────────────┐
│  With parameters  │  ${PARAMS_COUNT}
│  JavaScript files │  ${JS_COUNT}
│  API endpoints    │  ${API_COUNT}
│  Admin pages      │  ${ADMIN_COUNT}
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────── OUTPUT FILES ───────────────────────────────┐
│  All URLs (dedup) : combined/all-urls-dedup.txt
│  With params      : combined/urls-with-params.txt
│  JS files         : combined/js-files.txt
│  API endpoints    : combined/api-endpoints.txt
│  Admin pages      : combined/admin-pages.txt
│  Alive URLs       : httpx/alive-urls.txt
│  httpx JSON       : httpx/results.json
└─────────────────────────────────────────────────────────────────────────┘
EOF

# Print the report to the terminal too
cat "$REPORT_FILE" | tee -a "$OUTPUT_DIR/scan.log"

# ── Final summary banner ─────────────────────────────────────
echo "" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}║            ✅  SCAN COMPLETE                         ║${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${DIM}Total URLs found :${NC} ${BOLD}${WHITE}${DEDUP_COUNT}${NC} ${DIM}(${COMBINED_RAW} raw, deduped)${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${DIM}Alive URLs       :${NC} ${BOLD}${WHITE}${ALIVE_COUNT}${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${DIM}Scan duration    :${NC} ${BOLD}${WHITE}${TOTAL_MM}m ${TOTAL_SS}s${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo -e "  ${DIM}Output dir       :${NC} ${CYAN}${OUTPUT_DIR}${NC}" | tee -a "$OUTPUT_DIR/scan.log"
echo "" | tee -a "$OUTPUT_DIR/scan.log"

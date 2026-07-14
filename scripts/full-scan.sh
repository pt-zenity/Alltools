#!/bin/bash
# ============================================================
# Full Reconnaissance Scan Script
# Usage: ./full-scan.sh <target_url> [options]
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

TARGET="${1:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
THREADS="${THREADS:-50}"
DEPTH="${DEPTH:-3}"
TIMEOUT="${TIMEOUT:-10}"

if [ -z "$TARGET" ]; then
    echo -e "${RED}[!] Error: Target URL required${NC}"
    echo -e "Usage: $0 <target_url> [options]"
    exit 1
fi

# Extract domain from URL
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||' | sed 's|:.*||')
OUTPUT_DIR="/workspace/output/${DOMAIN}_${TIMESTAMP}"

mkdir -p "$OUTPUT_DIR"/{katana,gau,gospider,waymore,xnlink,httpx,subdomains,combined,reports}

log() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

warn() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

info() {
    echo -e "${BLUE}[$(date +%H:%M:%S)] $1${NC}" | tee -a "$OUTPUT_DIR/scan.log"
}

# ──────────────────────────────────────────────────────────────
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║        🕷️  FULL RECONNAISSANCE SCAN 2026  🕷️          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${WHITE}Target:   ${CYAN}$TARGET${NC}"
echo -e "${WHITE}Domain:   ${CYAN}$DOMAIN${NC}"
echo -e "${WHITE}Output:   ${CYAN}$OUTPUT_DIR${NC}"
echo -e "${WHITE}Threads:  ${CYAN}$THREADS${NC}"
echo -e "${WHITE}Depth:    ${CYAN}$DEPTH${NC}"
echo ""

# ─── PHASE 1: URL Collection ─────────────────────────────────
log "=== PHASE 1: URL COLLECTION ==="

# 1.1 katana
if command -v katana &>/dev/null; then
    log "[1/6] Running katana..."
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
        -jsonl "$OUTPUT_DIR/katana/results.jsonl" \
        2>&1 | tail -5 || warn "katana encountered an issue"
    
    KATANA_COUNT=$(wc -l < "$OUTPUT_DIR/katana/results.txt" 2>/dev/null || echo 0)
    log "  katana found: $KATANA_COUNT URLs"
else
    warn "katana not available, skipping..."
fi

# 1.2 gau
if command -v gau &>/dev/null; then
    log "[2/6] Running gau (wayback machine + common crawl)..."
    echo "$DOMAIN" | gau \
        --threads "$THREADS" \
        --timeout "$TIMEOUT" \
        --providers wayback,commoncrawl,otx,urlscan \
        --blacklist png,jpg,gif,jpeg,webp,svg,ico,css,woff,woff2,ttf,eot \
        --o "$OUTPUT_DIR/gau/results.txt" \
        2>&1 | tail -5 || warn "gau encountered an issue"
    
    GAU_COUNT=$(wc -l < "$OUTPUT_DIR/gau/results.txt" 2>/dev/null || echo 0)
    log "  gau found: $GAU_COUNT URLs"
else
    warn "gau not available, skipping..."
fi

# 1.3 gospider
if command -v gospider &>/dev/null; then
    log "[3/6] Running gospider..."
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
        -a \
        2>&1 | tail -5 || warn "gospider encountered an issue"
    
    GOSPIDER_COUNT=$(cat "$OUTPUT_DIR/gospider/"* 2>/dev/null | wc -l || echo 0)
    log "  gospider found: $GOSPIDER_COUNT entries"
else
    warn "gospider not available, skipping..."
fi

# 1.4 waymore
if command -v waymore &>/dev/null; then
    log "[4/6] Running waymore..."
    waymore \
        -i "$DOMAIN" \
        -mode U \
        -oU "$OUTPUT_DIR/waymore/results.txt" \
        -p "$THREADS" \
        2>&1 | tail -5 || warn "waymore encountered an issue"
    
    WAYMORE_COUNT=$(wc -l < "$OUTPUT_DIR/waymore/results.txt" 2>/dev/null || echo 0)
    log "  waymore found: $WAYMORE_COUNT URLs"
else
    warn "waymore not available, skipping..."
fi

# 1.5 xnLinkFinder
if command -v xnLinkFinder &>/dev/null; then
    log "[5/6] Running xnLinkFinder..."
    xnLinkFinder \
        -i "$TARGET" \
        -op "$OUTPUT_DIR/xnlink/results.txt" \
        -sp "$TARGET" \
        -sf "$DOMAIN" \
        -d "$DEPTH" \
        -p "$THREADS" \
        2>&1 | tail -5 || warn "xnLinkFinder encountered an issue"
    
    XNLINK_COUNT=$(wc -l < "$OUTPUT_DIR/xnlink/results.txt" 2>/dev/null || echo 0)
    log "  xnLinkFinder found: $XNLINK_COUNT links"
else
    warn "xnLinkFinder not available, skipping..."
fi

# 1.6 waybackurls
if command -v waybackurls &>/dev/null; then
    log "[6/6] Running waybackurls..."
    echo "$DOMAIN" | waybackurls > "$OUTPUT_DIR/waymore/wayback.txt" 2>/dev/null || warn "waybackurls encountered an issue"
    WAYBACK_COUNT=$(wc -l < "$OUTPUT_DIR/waymore/wayback.txt" 2>/dev/null || echo 0)
    log "  waybackurls found: $WAYBACK_COUNT URLs"
fi

# ─── PHASE 2: URL Deduplication ──────────────────────────────
log "=== PHASE 2: URL DEDUPLICATION ==="

cat "$OUTPUT_DIR/katana/results.txt" \
    "$OUTPUT_DIR/gau/results.txt" \
    "$OUTPUT_DIR/gospider/"*.txt \
    "$OUTPUT_DIR/waymore/results.txt" \
    "$OUTPUT_DIR/waymore/wayback.txt" \
    "$OUTPUT_DIR/xnlink/results.txt" \
    2>/dev/null | \
    grep -E "^https?://" | \
    sort -u > "$OUTPUT_DIR/combined/all-urls-raw.txt"

COMBINED_RAW=$(wc -l < "$OUTPUT_DIR/combined/all-urls-raw.txt")
log "Total raw URLs: $COMBINED_RAW"

# Deduplicate with uro if available
if command -v uro &>/dev/null; then
    log "Deduplicating with uro..."
    uro < "$OUTPUT_DIR/combined/all-urls-raw.txt" > "$OUTPUT_DIR/combined/all-urls-dedup.txt" 2>/dev/null
    DEDUP_COUNT=$(wc -l < "$OUTPUT_DIR/combined/all-urls-dedup.txt")
    log "After dedup: $DEDUP_COUNT unique URLs"
else
    cp "$OUTPUT_DIR/combined/all-urls-raw.txt" "$OUTPUT_DIR/combined/all-urls-dedup.txt"
fi

# ─── PHASE 3: HTTP Probing ────────────────────────────────────
log "=== PHASE 3: HTTP PROBING ==="

if command -v httpx &>/dev/null; then
    log "Running httpx on discovered URLs..."
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
        -timeout "$TIMEOUT" \
        2>&1 | tail -10 || warn "httpx encountered an issue"
    
    ALIVE_COUNT=$(wc -l < "$OUTPUT_DIR/httpx/alive-urls.txt" 2>/dev/null || echo 0)
    log "Alive URLs: $ALIVE_COUNT"
else
    warn "httpx not available"
fi

# ─── PHASE 4: URL Categorization ─────────────────────────────
log "=== PHASE 4: URL CATEGORIZATION ==="

if command -v gf &>/dev/null; then
    log "Running gf patterns..."
    
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
        
        gf "$pattern" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > "$output_file" 2>/dev/null && \
            COUNT=$(wc -l < "$output_file") && \
            log "  gf-$name: $COUNT URLs" || true
    done
fi

# ─── PHASE 5: URL Analysis ────────────────────────────────────
log "=== PHASE 5: URL ANALYSIS ==="

# Extract endpoints with parameters
grep -E "\?" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/urls-with-params.txt" 2>/dev/null || true

# Extract JavaScript files
grep -E "\.js(\?|$)" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/js-files.txt" 2>/dev/null || true

# Extract API endpoints
grep -E "/api/|/v[0-9]+/|/rest/|/graphql" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/api-endpoints.txt" 2>/dev/null || true

# Extract admin pages
grep -iE "admin|panel|dashboard|manage|backend|config|setup" "$OUTPUT_DIR/combined/all-urls-dedup.txt" > \
    "$OUTPUT_DIR/combined/admin-pages.txt" 2>/dev/null || true

PARAMS_COUNT=$(wc -l < "$OUTPUT_DIR/combined/urls-with-params.txt" 2>/dev/null || echo 0)
JS_COUNT=$(wc -l < "$OUTPUT_DIR/combined/js-files.txt" 2>/dev/null || echo 0)
API_COUNT=$(wc -l < "$OUTPUT_DIR/combined/api-endpoints.txt" 2>/dev/null || echo 0)

log "  URLs with params: $PARAMS_COUNT"
log "  JS files: $JS_COUNT"
log "  API endpoints: $API_COUNT"

# ─── PHASE 6: Generate Report ────────────────────────────────
log "=== PHASE 6: GENERATING REPORT ==="

REPORT_FILE="$OUTPUT_DIR/reports/scan-report.txt"
cat > "$REPORT_FILE" << EOF
═══════════════════════════════════════════════════════
       WEB CRAWLER TOOLKIT 2026 - SCAN REPORT
═══════════════════════════════════════════════════════

Target:     $TARGET
Domain:     $DOMAIN
Scan Date:  $(date '+%Y-%m-%d %H:%M:%S UTC')
Output Dir: $OUTPUT_DIR

═══════════════════════ RESULTS ═══════════════════════

[URL Collection]
  katana URLs:       ${KATANA_COUNT:-0}
  gau URLs:          ${GAU_COUNT:-0}
  gospider URLs:     ${GOSPIDER_COUNT:-0}
  waymore URLs:      ${WAYMORE_COUNT:-0}
  waybackurls:       ${WAYBACK_COUNT:-0}
  xnLinkFinder:      ${XNLINK_COUNT:-0}

[Processed]
  Total (raw):       $COMBINED_RAW
  After dedup:       ${DEDUP_COUNT:-$COMBINED_RAW}
  Alive URLs:        ${ALIVE_COUNT:-0}

[URL Categories]
  With parameters:   $PARAMS_COUNT
  JavaScript files:  $JS_COUNT
  API endpoints:     $API_COUNT

═══════════════════════ FILES ══════════════════════════

  $OUTPUT_DIR/combined/all-urls-dedup.txt  (all unique URLs)
  $OUTPUT_DIR/combined/urls-with-params.txt
  $OUTPUT_DIR/combined/js-files.txt
  $OUTPUT_DIR/combined/api-endpoints.txt
  $OUTPUT_DIR/httpx/alive-urls.txt
  $OUTPUT_DIR/httpx/results.json

═══════════════════════════════════════════════════════
EOF

cat "$REPORT_FILE"

log "=== SCAN COMPLETE ==="
log "Results saved to: $OUTPUT_DIR"
log "Report: $REPORT_FILE"

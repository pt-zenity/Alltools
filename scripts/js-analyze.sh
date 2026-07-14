#!/bin/bash
# ============================================================
# JavaScript File Analyzer
# Extracts endpoints, secrets, and links from JS files
# Usage: ./js-analyze.sh <target_url_or_domain>
# ============================================================

# NOTE: -e removed — individual steps must not abort the whole analysis
set -uo pipefail

TARGET="${1:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DOMAIN=$(echo "$TARGET" | sed 's|https\?://||' | sed 's|/.*||')
OUTPUT_DIR="/workspace/output/js_${DOMAIN}_${TIMESTAMP}"

if [ -z "$TARGET" ]; then
    echo "[!] Usage: $0 <target_url_or_domain>"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"/{js-files,endpoints,secrets}

echo "[*] JavaScript Analysis for: $TARGET"
echo "[*] Output: $OUTPUT_DIR"
echo ""

# ── helper: stream a tool live ───────────────────────────────
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

# ── Step 1: Collect JS URLs with katana ──────────────────────
if command -v katana &>/dev/null; then
    echo "[1] Discovering JS files with katana..."
    run_tool "katana" "$OUTPUT_DIR/js-files/katana.log" \
        katana \
            -u "$TARGET" \
            -jc \
            -d 3 \
            -c 30 \
            -extension-match js \
            -o "$OUTPUT_DIR/js-files/js-urls.txt"
else
    echo "[WARN] katana not found, skipping JS discovery via katana."
fi

# ── Step 2: Get JS from gau/wayback ──────────────────────────
if command -v gau &>/dev/null; then
    echo "[2] Getting JS files from wayback/commoncrawl..."
    run_tool "gau-js" "$OUTPUT_DIR/js-files/gau.log" \
        bash -c "echo '$DOMAIN' | stdbuf -oL gau \
            --providers wayback,commoncrawl 2>&1 | \
            grep -E '\.js(\?|$)' >> '$OUTPUT_DIR/js-files/js-urls.txt' || true"
else
    echo "[WARN] gau not found, skipping JS discovery via gau."
fi

# Sort and dedup
sort -u -o "$OUTPUT_DIR/js-files/js-urls.txt" "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || true
JS_COUNT=$(wc -l < "$OUTPUT_DIR/js-files/js-urls.txt" 2>/dev/null || echo 0)
echo "[*] Found $JS_COUNT unique JS files"

# ── Step 3: Download and analyze JS files ────────────────────
echo "[3] Downloading and analyzing JS files..."
if [ "$JS_COUNT" -gt 0 ]; then
    while IFS= read -r js_url; do
        [ -z "$js_url" ] && continue
        echo "  [$(date +%H:%M:%S)] Fetching: $js_url"
        curl -s --max-time 10 -L "$js_url" >> "$OUTPUT_DIR/js-files/combined.js" 2>/dev/null || true
    done < "$OUTPUT_DIR/js-files/js-urls.txt"
    echo "[3] Download complete."
else
    echo "[3] No JS files to download."
fi

# ── Step 4: Pattern extraction ───────────────────────────────
echo "[4] Extracting patterns from JS..."
if [ -f "$OUTPUT_DIR/js-files/combined.js" ]; then
    echo "  Extracting API endpoints..."
    grep -oE '("|'"'"')(/api/[^"'"'"']+)("|'"'"')' "$OUTPUT_DIR/js-files/combined.js" | \
        tr -d '"'"'" | sort -u > "$OUTPUT_DIR/endpoints/api-endpoints.txt" 2>/dev/null || true
    API_ENDPOINT_COUNT=$(wc -l < "$OUTPUT_DIR/endpoints/api-endpoints.txt" 2>/dev/null || echo 0)
    echo "  API endpoints found: $API_ENDPOINT_COUNT"

    echo "  Extracting path routes..."
    grep -oE '("|'"'"')(/[a-zA-Z0-9_/-]{3,})("|'"'"')' "$OUTPUT_DIR/js-files/combined.js" | \
        tr -d '"'"'" | sort -u > "$OUTPUT_DIR/endpoints/paths.txt" 2>/dev/null || true
    PATHS_COUNT=$(wc -l < "$OUTPUT_DIR/endpoints/paths.txt" 2>/dev/null || echo 0)
    echo "  Paths found: $PATHS_COUNT"

    echo "  Scanning for AWS keys..."
    grep -oE 'AKIA[0-9A-Z]{16}' "$OUTPUT_DIR/js-files/combined.js" > \
        "$OUTPUT_DIR/secrets/aws-keys.txt" 2>/dev/null || true
    AWS_COUNT=$(wc -l < "$OUTPUT_DIR/secrets/aws-keys.txt" 2>/dev/null || echo 0)
    echo "  Potential AWS keys: $AWS_COUNT"

    echo "  Scanning for potential tokens..."
    grep -oE '"[a-zA-Z0-9_-]{32,}"' "$OUTPUT_DIR/js-files/combined.js" | \
        head -100 > "$OUTPUT_DIR/secrets/potential-tokens.txt" 2>/dev/null || true
    TOKEN_COUNT=$(wc -l < "$OUTPUT_DIR/secrets/potential-tokens.txt" 2>/dev/null || echo 0)
    echo "  Potential tokens: $TOKEN_COUNT"
else
    echo "[WARN] No combined.js generated — nothing to extract."
fi

echo ""
echo "[✓] Analysis complete. Output: $OUTPUT_DIR"

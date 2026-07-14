#!/bin/bash
# =============================================================
# deploy.sh — Deploy files to crawler-toolkit container
# 
# METHOD 1 (default): HTTP API  — no SSH needed
#   ./deploy.sh scripts          deploy all scan scripts
#   ./deploy.sh all              deploy scripts + dashboard + restart
#   ./deploy.sh server           deploy server.js only
#   ./deploy.sh <file> <remote>  deploy single file to custom path
#
# METHOD 2: SCP via SSH password (requires -p 9022:22 in docker run)
#   SCP_MODE=1 ./deploy.sh scripts
#   SCP_MODE=1 VPS_HOST=23.111.15.50 VPS_SSH_PORT=9022 ./deploy.sh all
# =============================================================
set -euo pipefail

VPS_HOST="${VPS_HOST:-23.111.15.50}"
VPS_PORT="${VPS_PORT:-8888}"
VPS_SSH_PORT="${VPS_SSH_PORT:-9022}"
VPS_SSH_USER="${VPS_SSH_USER:-root}"
VPS_SSH_PASS="${VPS_SSH_PASS:-CrawlerKit2026!}"
VPS_API="http://${VPS_HOST}:${VPS_PORT}"
REMOTE_BASE="${REMOTE_BASE:-/workspace}"
SCP_MODE="${SCP_MODE:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Colors ──────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

# ── HTTP upload (via /api/upload/file) ──────────────────────
http_upload() {
    local local_path="$1"
    local remote_path="$2"
    [ ! -f "$local_path" ] && echo -e "  ${RED}[!] Not found: ${local_path}${NC}" && return 1

    local b64
    b64=$(base64 -w 0 "$local_path")
    local payload
    payload=$(python3 -c "import json,sys; print(json.dumps({'path': sys.argv[1], 'content': sys.argv[2], 'encoding': 'base64', 'executable': True}))" "$remote_path" "$b64")

    local result
    result=$(curl -sf -X POST "${VPS_API}/api/upload/file" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null) || {
        # Fallback: use exec+base64 method (works on old server versions too)
        result=$(curl -sf -X POST "${VPS_API}/api/exec" \
            -H "Content-Type: application/json" \
            -d "{\"command\":\"mkdir -p '$(dirname "$remote_path")' && echo '${b64}' | base64 -d > '${remote_path}' && chmod +x '${remote_path}' && echo OK\"}" 2>/dev/null)
        local stdout
        stdout=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stdout','').strip())" 2>/dev/null)
        [ "$stdout" = "OK" ] && echo -e "  ${GREEN}[✓]${NC} $(basename "$local_path") → ${remote_path} ${CYAN}(exec fallback)${NC}" && return 0
        echo -e "  ${RED}[✗]${NC} Failed: $local_path" && return 1
    }
    local ok
    ok=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d.get('ok') else 'FAIL')" 2>/dev/null)
    if [ "$ok" = "OK" ]; then
        local size
        size=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('size',0))" 2>/dev/null)
        echo -e "  ${GREEN}[✓]${NC} $(basename "$local_path") → ${remote_path} ${CYAN}(${size}B)${NC}"
    else
        echo -e "  ${RED}[✗]${NC} Failed: $local_path — $result"
        return 1
    fi
}

# ── SCP upload (via sshpass + scp) ───────────────────────────
scp_upload() {
    local local_path="$1"
    local remote_path="$2"
    [ ! -f "$local_path" ] && echo -e "  ${RED}[!] Not found: ${local_path}${NC}" && return 1

    if ! command -v sshpass &>/dev/null; then
        echo -e "  ${YELLOW}[!] sshpass not found — install with: apt-get install sshpass${NC}"
        return 1
    fi

    sshpass -p "$VPS_SSH_PASS" scp \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -P "$VPS_SSH_PORT" \
        "$local_path" \
        "${VPS_SSH_USER}@${VPS_HOST}:${remote_path}" 2>/dev/null && \
    sshpass -p "$VPS_SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -p "$VPS_SSH_PORT" \
        "${VPS_SSH_USER}@${VPS_HOST}" \
        "chmod +x '${remote_path}' 2>/dev/null; echo OK" 2>/dev/null | grep -q "OK" && \
    echo -e "  ${GREEN}[✓]${NC} $(basename "$local_path") → ${remote_path} ${CYAN}(SCP)${NC}" || {
        echo -e "  ${RED}[✗]${NC} SCP failed: $local_path"
        return 1
    }
}

# ── Remote exec ──────────────────────────────────────────────
exec_remote() {
    local cmd="$1"
    if [ "$SCP_MODE" = "1" ]; then
        sshpass -p "$VPS_SSH_PASS" ssh \
            -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            -p "$VPS_SSH_PORT" "${VPS_SSH_USER}@${VPS_HOST}" "$cmd" 2>/dev/null || true
    else
        curl -sf -X POST "${VPS_API}/api/exec" \
            -H "Content-Type: application/json" \
            -d "{\"command\":\"${cmd}\"}" | \
            python3 -c "import sys,json; print(json.load(sys.stdin).get('stdout','').strip())" 2>/dev/null || true
    fi
}

# ── Upload dispatcher ────────────────────────────────────────
upload_file() {
    local local_path="$1"
    local remote_path="$2"
    if [ "$SCP_MODE" = "1" ]; then
        scp_upload "$local_path" "$remote_path"
    else
        http_upload "$local_path" "$remote_path"
    fi
}

# ── Header ───────────────────────────────────────────────────
TARGET="${1:-all}"

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║     🚀  CRAWLER-TOOLKIT DEPLOY                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
if [ "$SCP_MODE" = "1" ]; then
    echo -e "  ${YELLOW}Mode    :${NC} SCP via SSH password"
    echo -e "  ${YELLOW}SSH     :${NC} ${VPS_SSH_USER}@${VPS_HOST}:${VPS_SSH_PORT}"
    echo -e "  ${YELLOW}Pass    :${NC} ${VPS_SSH_PASS}"
else
    echo -e "  ${CYAN}Mode    :${NC} HTTP API (no SSH needed)"
    echo -e "  ${CYAN}API     :${NC} ${VPS_API}"
fi
echo ""

# ── Single file deploy ───────────────────────────────────────
if [ "$TARGET" != "all" ] && [ "$TARGET" != "scripts" ] && [ "$TARGET" != "scripts/" ] && [ "$TARGET" != "server" ] && [ -f "$TARGET" ]; then
    REMOTE="${2:-${REMOTE_BASE}/$(basename "$TARGET")}"
    upload_file "$TARGET" "$REMOTE"
    exit 0
fi

# ── Scripts ──────────────────────────────────────────────────
if [ "$TARGET" = "all" ] || [[ "$TARGET" == scripts* ]]; then
    echo -e "${WHITE}[*] Deploying scan scripts...${NC}"
    for f in scripts/full-scan.sh scripts/collect-urls.sh scripts/crawl-only.sh scripts/js-analyze.sh; do
        [ -f "$f" ] && upload_file "$f" "${REMOTE_BASE}/${f}" || true
    done
fi

# ── Dashboard / server.js ────────────────────────────────────
if [ "$TARGET" = "all" ] || [ "$TARGET" = "server" ]; then
    echo ""
    echo -e "${WHITE}[*] Deploying dashboard files...${NC}"
    for f in dashboard/server.js dashboard/public/static/app.js dashboard/public/static/style.css; do
        [ -f "$f" ] && upload_file "$f" "${REMOTE_BASE}/${f}" || true
    done
fi

# ── Restart node server ──────────────────────────────────────
if [ "$TARGET" = "all" ] || [ "$TARGET" = "server" ]; then
    echo ""
    echo -e "${WHITE}[*] Restarting node server...${NC}"
    exec_remote "pkill -f 'node.*server.js' 2>/dev/null; sleep 1; cd /workspace/dashboard && nohup node server.js >/workspace/dashboard/server.log 2>&1 & sleep 2 && echo RESTARTED"
    sleep 2
fi

# ── Health check ─────────────────────────────────────────────
echo ""
echo -e "${WHITE}[*] Health check...${NC}"
HEALTH=$(curl -sf "${VPS_API}/api/health" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','?'))" 2>/dev/null || echo "unreachable")
echo -e "  ${GREEN}[✓]${NC} API version: ${BOLD}${HEALTH}${NC}"
echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
echo -e "${YELLOW}NOTE — SSH/SCP Setup:${NC}"
echo -e "  For SCP mode, rebuild container with: docker run -p 8888:3000 -p 9022:22 ..."
echo -e "  Then use: SCP_MODE=1 VPS_SSH_PORT=9022 ./deploy.sh scripts"

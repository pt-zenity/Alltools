#!/bin/bash
# ============================================================
# Entrypoint script for Web Crawler Toolkit 2026
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         🕷️  WEB CRAWLER TOOLKIT 2026 - ULTRA EDITION  🕷️      ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Tools: katana • gau • waymore • gospider • xnLinkFinder    ║"
    echo "║         httpx • nuclei • dnsx • subfinder • gf              ║"
    echo "║         cariddi • mantra • gitleaks                        ║"
    echo "║         SecretFinder • JSScanner  (Python)                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check tool availability
check_tools() {
    echo -e "${BLUE}[*] Checking installed tools...${NC}"
    
    TOOLS=(
        "katana:Katana (crawling framework)"
        "gau:GAU (URL collector)"
        "gospider:GoSpider (web spider)"
        "httpx:HTTPx (HTTP probe)"
        "subfinder:Subfinder (subdomain)"
        "dnsx:DNSx (DNS toolkit)"
        "naabu:Naabu (port scanner)"
        "nuclei:Nuclei (vuln scanner)"
        "waybackurls:Wayback URLs"
        "anew:Anew (dedup)"
        "gf:GF (grep patterns)"
        "unfurl:Unfurl (URL parser)"
        "qsreplace:QSReplace"
        "waymore:Waymore (Python)"
        "xnLinkFinder:xnLinkFinder (Python)"
        "uro:URO (URL dedup)"
        "cariddi:Cariddi (deep crawler)"
        "mantra:Mantra (secret hunter)"
        "gitleaks:Gitleaks (credential leak scanner)"
        "node:Node.js"
        "python3:Python 3"
    )
    # Note: SecretFinder and JSScanner are Python scripts (not in PATH)
    # Check them separately as file presence
    if [ -f /opt/SecretFinder/SecretFinder.py ]; then
        echo -e "  ${GREEN}✓${NC} ${WHITE}SecretFinder (Python script)${NC} - /opt/SecretFinder/SecretFinder.py"
    else
        echo -e "  ${RED}✗${NC} ${WHITE}SecretFinder (Python script)${NC} - ${RED}NOT FOUND at /opt/SecretFinder/${NC}"
        ALL_OK=false
    fi
    if [ -f /opt/JSScanner/JSScanner.py ]; then
        echo -e "  ${GREEN}✓${NC} ${WHITE}JSScanner (Python script)${NC} - /opt/JSScanner/JSScanner.py"
    else
        echo -e "  ${RED}✗${NC} ${WHITE}JSScanner (Python script)${NC} - ${RED}NOT FOUND at /opt/JSScanner/${NC}"
        ALL_OK=false
    fi
    
    ALL_OK=true
    for item in "${TOOLS[@]}"; do
        tool="${item%%:*}"
        desc="${item##*:}"
        if command -v "$tool" &>/dev/null; then
            VER=$(command "$tool" --version 2>/dev/null | head -1 || command "$tool" -version 2>/dev/null | head -1 || echo "installed")
            echo -e "  ${GREEN}✓${NC} ${WHITE}${desc}${NC} - ${VER}"
        else
            echo -e "  ${RED}✗${NC} ${WHITE}${desc}${NC} - ${RED}NOT FOUND${NC}"
            ALL_OK=false
        fi
    done
    
    if $ALL_OK; then
        echo -e "\n${GREEN}[✓] All tools are ready!${NC}\n"
    else
        echo -e "\n${YELLOW}[!] Some tools may be missing. Check the setup.${NC}\n"
    fi
}

# Main logic
case "$1" in
    "dashboard"|"web"|"ui")
        print_banner
        check_tools
        # Start SSH daemon for remote access (password: CrawlerKit2026!)
        # Auto-install openssh if missing (handles containers built without it)
        if ! command -v sshd &>/dev/null; then
            echo -e "${YELLOW}[*] Installing openssh-server + sftp-server...${NC}"
            apk add --no-cache openssh-server openssh-sftp-server 2>/dev/null || true
        fi
        if command -v sshd &>/dev/null; then
            # Ensure host keys exist
            ssh-keygen -A 2>/dev/null || true
            # Ensure root password is set
            echo 'root:CrawlerKit2026!' | chpasswd 2>/dev/null || true
            # Write sshd_config with SFTP subsystem (idempotent)
            printf 'Port 22\nPermitRootLogin yes\nPasswordAuthentication yes\nChallengeResponseAuthentication no\nSubsystem sftp /usr/lib/ssh/sftp-server\n' \
                > /etc/ssh/sshd_config
            /usr/sbin/sshd 2>/dev/null && \
                echo -e "${GREEN}[✓] SSH server started on port 22 (SCP/SFTP ready)${NC}" || \
                echo -e "${YELLOW}[!] SSH server failed to start${NC}"
        fi
        echo -e "${GREEN}[*] Starting Web Dashboard on port 3000...${NC}"
        cd /workspace/dashboard && node server.js
        ;;
    "check"|"status")
        print_banner
        check_tools
        ;;
    "bash"|"shell")
        print_banner
        check_tools
        exec /bin/bash
        ;;
    "scan")
        print_banner
        check_tools
        if [ -z "$2" ]; then
            echo -e "${RED}[!] Usage: docker run crawler-toolkit scan <target_url>${NC}"
            exit 1
        fi
        exec /workspace/scripts/full-scan.sh "$2" "${@:3}"
        ;;
    "crawl")
        print_banner
        check_tools
        if [ -z "$2" ]; then
            echo -e "${RED}[!] Usage: docker run crawler-toolkit crawl <target_url> [options]${NC}"
            exit 1
        fi
        exec /workspace/scripts/crawl-only.sh "$2" "${@:3}"
        ;;
    "urls")
        print_banner
        if [ -z "$2" ]; then
            echo -e "${RED}[!] Usage: docker run crawler-toolkit urls <domain>${NC}"
            exit 1
        fi
        exec /workspace/scripts/collect-urls.sh "$2" "${@:3}"
        ;;
    "help"|"-h"|"--help"|"")
        print_banner
        echo -e "${WHITE}USAGE:${NC}"
        echo -e "  docker run crawler-toolkit ${CYAN}<command>${NC} [options]"
        echo ""
        echo -e "${WHITE}COMMANDS:${NC}"
        echo -e "  ${CYAN}dashboard${NC}    Start web dashboard UI (port 3000)"
        echo -e "  ${CYAN}check${NC}        Check all tool availability"
        echo -e "  ${CYAN}scan${NC}         Full reconnaissance scan on target"
        echo -e "  ${CYAN}crawl${NC}        Crawl target URLs"
        echo -e "  ${CYAN}urls${NC}         Collect all URLs from target domain"
        echo -e "  ${CYAN}bash${NC}         Interactive shell"
        echo -e "  ${CYAN}help${NC}         Show this help"
        echo ""
        echo -e "${WHITE}EXAMPLES:${NC}"
        echo -e "  ${YELLOW}docker run -p 3000:3000 crawler-toolkit dashboard${NC}"
        echo -e "  ${YELLOW}docker run crawler-toolkit scan https://example.com${NC}"
        echo -e "  ${YELLOW}docker run crawler-toolkit urls example.com${NC}"
        echo -e "  ${YELLOW}docker run -it crawler-toolkit bash${NC}"
        echo ""
        echo -e "${WHITE}OUTPUT:${NC}"
        echo -e "  All results are saved to ${CYAN}/workspace/output/${NC}"
        echo ""
        ;;
    *)
        exec "$@"
        ;;
esac

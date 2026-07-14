#!/bin/bash
# ============================================================
# Web Crawler Toolkit 2026 - Installation Script
# Supports: Docker, Docker Compose, or Native Alpine/Linux
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Config
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_METHOD="${INSTALL_METHOD:-docker}"

# ── Banner ────────────────────────────────────
banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║       🕷️  WEB CRAWLER TOOLKIT 2026 - INSTALLATION WIZARD         ║
║                                                                  ║
║   Tools: katana • gau • waymore • gospider • xnLinkFinder        ║
║          httpx • nuclei • dnsx • subfinder • gf • uro            ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

# ── Logging ───────────────────────────────────
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${CYAN}${BOLD}▶ $1${NC}"; }

# ── Check requirements ────────────────────────
check_requirements() {
    log_step "Checking system requirements..."
    
    local REQUIRED=()
    
    if [ "$INSTALL_METHOD" = "docker" ] || [ "$INSTALL_METHOD" = "compose" ]; then
        REQUIRED+=("docker")
        [ "$INSTALL_METHOD" = "compose" ] && REQUIRED+=("docker compose")
    else
        REQUIRED+=("curl" "wget" "git" "go" "python3" "node" "npm")
    fi
    
    local ALL_OK=true
    for cmd in "${REQUIRED[@]}"; do
        if command -v ${cmd%% *} &>/dev/null; then
            log_success "$cmd found"
        else
            log_error "$cmd NOT found"
            ALL_OK=false
        fi
    done
    
    if ! $ALL_OK; then
        log_error "Missing requirements. Please install them first."
        exit 1
    fi
    
    log_success "All requirements satisfied"
}

# ── Docker Installation ───────────────────────
install_docker() {
    log_step "Building Docker image..."
    
    cd "$REPO_DIR"
    
    echo "Building crawler-toolkit:2026 image..."
    docker build \
        --target final \
        -t crawler-toolkit:2026 \
        -t crawler-toolkit:latest \
        --progress=plain \
        . 2>&1
    
    log_success "Docker image built: crawler-toolkit:2026"
    
    # Create directory structure
    mkdir -p output targets logs data config wordlists
    
    log_step "Verifying installation..."
    docker run --rm crawler-toolkit:2026 check
    
    echo ""
    log_success "=== Docker installation complete! ==="
    echo ""
    echo -e "${WHITE}Start the dashboard:${NC}"
    echo -e "  ${CYAN}docker run -p 3000:3000 -v \$(pwd)/output:/workspace/output crawler-toolkit:2026${NC}"
    echo ""
    echo -e "${WHITE}Or use Docker Compose:${NC}"
    echo -e "  ${CYAN}docker compose up -d${NC}"
    echo ""
    echo -e "${WHITE}Dashboard URL:${NC} ${GREEN}http://localhost:3000${NC}"
}

# ── Docker Compose Installation ───────────────
install_compose() {
    log_step "Setting up with Docker Compose..."
    
    cd "$REPO_DIR"
    
    # Build first
    install_docker
    
    log_step "Starting services with Docker Compose..."
    docker compose up -d
    
    # Wait for healthy
    echo "Waiting for services to start..."
    local max_wait=60
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if curl -sf http://localhost:3000/api/health &>/dev/null; then
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    
    if curl -sf http://localhost:3000/api/health &>/dev/null; then
        log_success "Dashboard is running!"
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  Dashboard: http://localhost:3000     ║${NC}"
        echo -e "${GREEN}║  Status:    docker compose ps         ║${NC}"
        echo -e "${GREEN}║  Logs:      docker compose logs -f    ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    else
        log_warn "Dashboard may still be starting. Check: docker compose logs"
    fi
}

# ── Native/Alpine Installation ────────────────
install_native() {
    log_step "Installing tools natively..."
    
    # Detect OS
    if [ -f /etc/alpine-release ]; then
        log_info "Detected Alpine Linux"
        install_alpine
    elif [ -f /etc/debian_version ]; then
        log_info "Detected Debian/Ubuntu"
        install_debian
    elif [ -f /etc/redhat-release ]; then
        log_info "Detected RHEL/CentOS/Fedora"
        install_rhel
    else
        log_warn "Unknown OS, attempting generic install..."
        install_go_tools
        install_python_tools
    fi
}

# ── Alpine installation ────────────────────────
install_alpine() {
    log_step "Installing Alpine packages..."
    
    apk update && apk upgrade
    apk add --no-cache \
        bash curl wget git ca-certificates \
        go python3 python3-dev py3-pip \
        nodejs npm \
        gcc g++ musl-dev make \
        jq parallel grep \
        openssl-dev libffi-dev \
        libxml2-dev libxslt-dev
    
    install_go_tools
    install_python_tools
    install_node_tools
    setup_workspace
}

# ── Debian/Ubuntu installation ─────────────────
install_debian() {
    log_step "Installing Debian packages..."
    
    apt-get update && apt-get upgrade -y
    apt-get install -y \
        curl wget git ca-certificates \
        golang-go \
        python3 python3-pip python3-venv \
        nodejs npm \
        build-essential \
        jq parallel
    
    install_go_tools
    install_python_tools
    install_node_tools
    setup_workspace
}

# ── RHEL/CentOS installation ───────────────────
install_rhel() {
    log_step "Installing RHEL packages..."
    
    dnf update -y
    dnf install -y \
        curl wget git ca-certificates \
        golang \
        python3 python3-pip \
        nodejs npm \
        gcc gcc-c++ make \
        jq
    
    install_go_tools
    install_python_tools
    install_node_tools
    setup_workspace
}

# ── Go tools ──────────────────────────────────
install_go_tools() {
    log_step "Installing Go-based tools..."
    
    export GOPATH="${HOME}/go"
    export PATH="$PATH:$GOPATH/bin"
    mkdir -p "$GOPATH/bin"
    
    TOOLS=(
        "katana:github.com/projectdiscovery/katana/cmd/katana@latest"
        "httpx:github.com/projectdiscovery/httpx/cmd/httpx@latest"
        "gau:github.com/lc/gau/v2/cmd/gau@latest"
        "gospider:github.com/jaeles-project/gospider@latest"
        "subfinder:github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        "nuclei:github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        "dnsx:github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
        "naabu:github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
        "waybackurls:github.com/tomnomnom/waybackurls@latest"
        "anew:github.com/tomnomnom/anew@latest"
        "gf:github.com/tomnomnom/gf@latest"
        "qsreplace:github.com/tomnomnom/qsreplace@latest"
        "unfurl:github.com/tomnomnom/unfurl@latest"
    )
    
    for tool_info in "${TOOLS[@]}"; do
        name="${tool_info%%:*}"
        pkg="${tool_info##*:}"
        echo -n "  Installing $name... "
        if go install "$pkg" 2>/dev/null; then
            log_success "$name installed"
        else
            log_warn "$name installation failed (non-critical)"
        fi
    done
    
    # Copy to /usr/local/bin
    cp "$GOPATH/bin/"* /usr/local/bin/ 2>/dev/null || true
    
    log_success "Go tools installed"
}

# ── Python tools ──────────────────────────────
install_python_tools() {
    log_step "Installing Python-based tools..."
    
    # Create virtual environment
    python3 -m venv /opt/venv 2>/dev/null || pip3 install virtualenv
    
    ACTIVATE=""
    if [ -f /opt/venv/bin/activate ]; then
        ACTIVATE=". /opt/venv/bin/activate && "
    fi
    
    PYTHON_TOOLS="waymore xnLinkFinder uro requests beautifulsoup4 lxml httpie rich colorama"
    
    eval "${ACTIVATE}pip install --upgrade pip"
    for tool in $PYTHON_TOOLS; do
        echo -n "  Installing $tool... "
        if eval "${ACTIVATE}pip install $tool" &>/dev/null; then
            log_success "$tool installed"
        else
            log_warn "$tool installation failed (non-critical)"
        fi
    done
    
    # Add venv to PATH
    echo 'export PATH="/opt/venv/bin:$PATH"' >> ~/.bashrc
    echo 'export PATH="/opt/venv/bin:$PATH"' >> ~/.profile
    
    log_success "Python tools installed"
}

# ── Node.js tools ─────────────────────────────
install_node_tools() {
    log_step "Installing Node.js tools..."
    
    cd "$REPO_DIR/dashboard"
    npm install --production
    
    log_success "Node.js dashboard dependencies installed"
}

# ── Setup workspace ───────────────────────────
setup_workspace() {
    log_step "Setting up workspace..."
    
    mkdir -p \
        /workspace/output \
        /workspace/targets \
        /workspace/config \
        /workspace/wordlists \
        /workspace/scripts \
        /logs /data
    
    # Copy scripts
    cp -r "$REPO_DIR/scripts/"* /workspace/scripts/ 2>/dev/null || true
    chmod +x /workspace/scripts/*.sh 2>/dev/null || true
    
    # Setup gf patterns
    mkdir -p ~/.gf
    if command -v git &>/dev/null; then
        git clone --depth=1 https://github.com/1ndianl33t/Gf-Patterns ~/.gf 2>/dev/null || true
    fi
    
    log_success "Workspace configured at /workspace"
}

# ── Show usage ────────────────────────────────
show_help() {
    cat << 'EOF'
USAGE:
  ./setup.sh [METHOD]

INSTALL METHODS:
  docker    Build Docker image only (default)
  compose   Build and start with Docker Compose
  native    Install tools natively (Alpine/Debian/RHEL)
  help      Show this help

ENVIRONMENT VARIABLES:
  INSTALL_METHOD=docker|compose|native  Override install method

EXAMPLES:
  ./setup.sh                    # Docker build
  ./setup.sh compose            # Docker Compose (start services)
  ./setup.sh native             # Native install (run as root)
  INSTALL_METHOD=compose ./setup.sh  # Via env var

POST-INSTALL:
  Dashboard:   http://localhost:3000
  Quick scan:  docker run crawler-toolkit:2026 scan https://example.com
  Shell:       docker run -it crawler-toolkit:2026 bash
EOF
}

# ── Main ──────────────────────────────────────
banner

METHOD="${1:-$INSTALL_METHOD}"

case "$METHOD" in
    "docker")
        check_requirements
        install_docker
        ;;
    "compose")
        check_requirements
        install_compose
        ;;
    "native")
        # Must be root for native install
        if [ "$(id -u)" != "0" ]; then
            log_error "Native installation requires root privileges. Run with sudo."
            exit 1
        fi
        install_native
        
        log_success "=== Native installation complete! ==="
        echo ""
        echo -e "${WHITE}Start dashboard:${NC}"
        echo -e "  ${CYAN}cd $REPO_DIR/dashboard && node server.js${NC}"
        echo -e "${WHITE}Or with PM2:${NC}"
        echo -e "  ${CYAN}npm install -g pm2 && pm2 start $REPO_DIR/dashboard/server.js --name crawler-dashboard${NC}"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        log_error "Unknown method: $METHOD"
        show_help
        exit 1
        ;;
esac

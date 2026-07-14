# ============================================================
# Web Crawler Toolkit 2026 - Ultra Complete Edition
# Tools: katana + gau + waymore + gospider + xnLinkFinder + httpx + nodejs
# Base: Alpine Linux (minimal & fast)
# ============================================================

FROM alpine:3.19 AS base

LABEL maintainer="crawler-toolkit-2026"
LABEL description="Ultimate Web Crawler Toolkit 2026 - katana + gau + waymore + gospider + xnLinkFinder + httpx + nodejs"
LABEL version="2026.1.0"

# ── System dependencies ──────────────────────────────────────
RUN apk update && apk upgrade && \
    apk add --no-cache \
        # Core utilities
        bash curl wget git ca-certificates \
        # Go build essentials
        go \
        # Python & pip
        python3 python3-dev py3-pip py3-setuptools py3-wheel \
        # Node.js & npm
        nodejs npm \
        # C/C++ build tools (for compiled extensions)
        gcc g++ musl-dev make \
        # Network tools
        nmap bind-tools iputils \
        # Text processing
        jq parallel grep sed gawk \
        # TLS/SSL
        openssl openssl-dev libffi-dev \
        # Additional libraries
        libxml2-dev libxslt-dev zlib-dev \
        # Procps for process management
        procps \
        # Time utilities
        tzdata \
        # GNU coreutils — provides stdbuf for line-buffered tool output
        coreutils && \
    # Set timezone
    cp /usr/share/zoneinfo/UTC /etc/localtime && \
    echo "UTC" > /etc/timezone && \
    # Cleanup
    rm -rf /var/cache/apk/*

# ── Go environment ────────────────────────────────────────────
ENV GOPATH=/go
ENV GOROOT=/usr/lib/go
ENV PATH=$PATH:$GOPATH/bin:/usr/local/go/bin
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64
ENV GO111MODULE=on

RUN mkdir -p $GOPATH/bin $GOPATH/src $GOPATH/pkg

# ── Stage: Go tools builder ───────────────────────────────────
FROM base AS go-builder

# Install Go tools (all in one layer for cache efficiency)
RUN echo "==> Installing Go-based crawler tools..." && \
    # ── 1. katana (next-gen crawling framework by projectdiscovery) ──
    echo "[1/5] Installing katana..." && \
    go install github.com/projectdiscovery/katana/cmd/katana@latest && \
    echo "katana: OK" && \
    # ── 2. httpx (fast HTTP probe) ──
    echo "[2/5] Installing httpx..." && \
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    echo "httpx: OK" && \
    # ── 3. gau (Get All URLs - wayback machine + commoncrawl) ──
    echo "[3/5] Installing gau..." && \
    go install github.com/lc/gau/v2/cmd/gau@latest && \
    echo "gau: OK" && \
    # ── 4. gospider (fast web spider) ──
    echo "[4/5] Installing gospider..." && \
    go install github.com/jaeles-project/gospider@latest && \
    echo "gospider: OK" && \
    # ── 5. subfinder (subdomain discovery) ──
    echo "[5/5] Installing subfinder..." && \
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    echo "subfinder: OK"

# Additional ProjectDiscovery tools
RUN echo "==> Installing additional PD tools..." && \
    # nuclei (vulnerability scanner)
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest && \
    echo "nuclei: OK" && \
    # dnsx (DNS toolkit)
    go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest && \
    echo "dnsx: OK" && \
    # naabu (port scanner)
    go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest && \
    echo "naabu: OK" && \
    # waybackurls
    go install github.com/tomnomnom/waybackurls@latest && \
    echo "waybackurls: OK" && \
    # anew (append new lines to file)
    go install github.com/tomnomnom/anew@latest && \
    echo "anew: OK" && \
    # gf (grep with patterns)
    go install github.com/tomnomnom/gf@latest && \
    echo "gf: OK" && \
    # qsreplace (replace values in query strings)
    go install github.com/tomnomnom/qsreplace@latest && \
    echo "qsreplace: OK" && \
    # unfurl (pull out bits of URLs)
    go install github.com/tomnomnom/unfurl@latest && \
    echo "unfurl: OK" && \
    # fff (fetch for files)
    go install github.com/tomnomnom/fff@latest && \
    echo "fff: OK"

# ── Stage: Python tools ───────────────────────────────────────
FROM base AS python-builder

WORKDIR /opt/python-tools

# Install Python virtual environment tool
RUN pip3 install --break-system-packages virtualenv 2>/dev/null || pip3 install virtualenv

# Create venv for Python tools
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# ── waymore (comprehensive URL collection) ──
RUN echo "[Python] Installing waymore..." && \
    pip install waymore && \
    echo "waymore: OK"

# ── xnLinkFinder (URL/link extractor) ──
RUN echo "[Python] Installing xnLinkFinder..." && \
    pip install xnLinkFinder && \
    echo "xnLinkFinder: OK"

# Additional Python recon tools
RUN echo "[Python] Installing additional tools..." && \
    pip install \
        # URL manipulation
        uro \
        # robots.txt parser
        robotparser-cli 2>/dev/null || true && \
    pip install \
        # SecretFinder dependencies
        requests \
        lxml \
        html5lib \
        beautifulsoup4 \
        # HTTP toolkit
        httpie \
        # DNS
        dnspython \
        # Colorful output
        colorama \
        rich \
        tabulate \
        tqdm && \
    echo "Python tools: OK"

# ── uro (URL deduplication) ──
RUN pip install uro 2>/dev/null && echo "uro: OK" || echo "uro already installed"

# ── Stage: Node.js tools ──────────────────────────────────────
FROM base AS node-builder

WORKDIR /opt/node-tools

# Install Node.js global tools
RUN npm config set fund false && npm config set audit false && \
    npm install -g \
        # URL analysis
        node-url \
        # JS link extractor
        link-js \
        # HTTP request library
        axios \
        # Web scraping
        cheerio \
        # Puppeteer for JS rendering (headless Chrome)
        puppeteer \
        # URL parsing
        whatwg-url \
        # CLI tools
        commander \
        chalk \
        ora \
        # Output
        json2csv && \
    echo "Node.js tools: OK"

# ── Final stage: Combined image ───────────────────────────────
FROM base AS final

# Copy Go binaries
COPY --from=go-builder /go/bin/ /usr/local/bin/

# Copy Python venv
COPY --from=python-builder /opt/venv /opt/venv

# Copy Node modules (global)
COPY --from=node-builder /usr/lib/node_modules /usr/lib/node_modules
COPY --from=node-builder /usr/bin/node /usr/bin/node

# Set Python venv path
ENV PATH="/opt/venv/bin:/usr/local/bin:$PATH"
ENV VIRTUAL_ENV="/opt/venv"

# ── Create workspace structure ────────────────────────────────
RUN mkdir -p \
    /workspace/targets \
    /workspace/output \
    /workspace/output/urls \
    /workspace/output/alive \
    /workspace/output/katana \
    /workspace/output/gospider \
    /workspace/output/gau \
    /workspace/output/waymore \
    /workspace/output/xnlink \
    /workspace/output/httpx \
    /workspace/output/subdomains \
    /workspace/output/combined \
    /workspace/scripts \
    /workspace/config \
    /workspace/wordlists \
    /workspace/reports \
    /data \
    /logs

WORKDIR /workspace

# ── Copy scripts and configs ──────────────────────────────────
COPY scripts/ /workspace/scripts/
COPY config/   /workspace/config/
COPY wordlists/ /workspace/wordlists/

RUN chmod +x /workspace/scripts/*.sh 2>/dev/null || true && \
    chmod +x /workspace/scripts/*.py 2>/dev/null || true

# ── Install Node.js Web Dashboard ────────────────────────────
COPY dashboard/ /workspace/dashboard/
WORKDIR /workspace/dashboard
RUN npm install --production 2>/dev/null || true

WORKDIR /workspace

# ── Setup gf patterns ────────────────────────────────────────
RUN mkdir -p /root/.gf && \
    git clone --depth=1 https://github.com/1ndianl33t/Gf-Patterns /root/.gf 2>/dev/null || true && \
    # Add missing patterns that Gf-Patterns repo doesn't include
    printf '{"flags":"-iE","patterns":["apikey","api_key","secret","token","password","passwd","auth","authorization","bearer","access_token","private_key","client_secret","aws_secret","db_password","api_secret"]}' > /root/.gf/secrets.json && \
    printf '{"flags":"-iE","patterns":["upload","file","attachment","multipart","enctype","fileupload","img","image","photo","avatar","media"]}' > /root/.gf/upload.json && \
    echo "gf patterns setup done"

# ── SSH server for remote access ─────────────────────────────
RUN apk add --no-cache openssh-server socat && \
    ssh-keygen -A && \
    # Set root password for SSH access
    echo 'root:CrawlerKit2026!' | chpasswd && \
    # Configure sshd: allow root login with password
    printf 'Port 22\nPermitRootLogin yes\nPasswordAuthentication yes\nChallengeResponseAuthentication no\n' > /etc/ssh/sshd_config && \
    echo "SSH setup done"

# ── Entrypoint ────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 3000 = dashboard, 22 = SSH
EXPOSE 3000 22

VOLUME ["/workspace/output", "/workspace/targets", "/data", "/logs"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["dashboard"]

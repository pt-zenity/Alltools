# 🕷️ Web Crawler Toolkit 2026 — Ultra Complete Edition

> **The most comprehensive web crawler & URL discovery toolkit for 2026**  
> Combining: `katana` + `gau` + `waymore` + `gospider` + `xnLinkFinder` + `httpx` + Node.js  
> Built on: **Alpine Linux** (minimal & fast)

---

## 🚀 Quick Start

### Option 1: Docker (Recommended)
```bash
# Build image
docker build -t crawler-toolkit:2026 .

# Start web dashboard
docker run -p 3000:3000 -v $(pwd)/output:/workspace/output crawler-toolkit:2026

# Open dashboard → http://localhost:3000
```

### Option 2: Docker Compose (Full Stack)
```bash
docker compose up -d
# Dashboard → http://localhost:3000
```

### Option 3: Auto Setup Script
```bash
chmod +x setup.sh
./setup.sh docker     # Docker build only
./setup.sh compose    # Docker Compose (auto-start)
./setup.sh native     # Native install (root required)
```

---

## 🛠️ Tools Included

| Tool | Version | Type | Description |
|------|---------|------|-------------|
| **katana** | latest | Go | Next-gen crawling framework (ProjectDiscovery) |
| **gau** | latest | Go | Get All URLs — Wayback + CommonCrawl + OTX |
| **waymore** | latest | Python | Advanced URL collection from web archives |
| **gospider** | latest | Go | Fast web spider with JS support |
| **xnLinkFinder** | latest | Python | Link/endpoint extractor from responses |
| **httpx** | latest | Go | Fast HTTP probe & tech detection |
| **subfinder** | latest | Go | Passive subdomain discovery |
| **nuclei** | latest | Go | YAML-based vulnerability scanner |
| **dnsx** | latest | Go | DNS toolkit & bruteforce |
| **naabu** | latest | Go | Fast port scanner |
| **waybackurls** | latest | Go | Wayback Machine URL fetcher |
| **anew** | latest | Go | Append new unique lines |
| **gf** | latest | Go | Grep with vuln patterns |
| **uro** | latest | Python | URL deduplication |
| **unfurl** | latest | Go | URL component extractor |
| **Node.js** | 20+ | Runtime | Dashboard & JS tools |
| **Python 3** | 3.11+ | Runtime | Python-based tools |

---

## 📋 Usage Examples

### Run Full Reconnaissance Scan
```bash
# Via Docker
docker run -v $(pwd)/output:/workspace/output \
  crawler-toolkit:2026 scan https://example.com

# With custom options
DEPTH=5 THREADS=100 docker run \
  -e DEPTH -e THREADS \
  -v $(pwd)/output:/workspace/output \
  crawler-toolkit:2026 scan https://example.com
```

### Collect All URLs
```bash
docker run -v $(pwd)/output:/workspace/output \
  crawler-toolkit:2026 urls example.com
```

### Crawl Website
```bash
docker run -v $(pwd)/output:/workspace/output \
  crawler-toolkit:2026 crawl https://example.com 3 50
```

### Interactive Shell
```bash
docker run -it -v $(pwd)/output:/workspace/output \
  crawler-toolkit:2026 bash
```

### Individual Tool Usage
```bash
# katana
docker run crawler-toolkit:2026 katana -u https://example.com -d 3 -jc

# gau
docker run crawler-toolkit:2026 sh -c "echo 'example.com' | gau --threads 20"

# httpx
docker run -i crawler-toolkit:2026 httpx -sc -title < urls.txt

# waymore
docker run crawler-toolkit:2026 waymore -i example.com -mode U -oU /workspace/output/urls.txt
```

---

## 🌐 Web Dashboard

The toolkit includes a **Node.js web dashboard** accessible at `http://localhost:3000`

### Dashboard Features:
- 🎯 **Scan Launcher** — Start full recon, crawl-only, URL collection, or JS analysis
- 📊 **Live Output** — Real-time terminal output via WebSocket
- 🗂️ **File Browser** — Browse, view, and download scan results
- 🔧 **Tool Status** — Check availability and versions of all tools
- 💻 **Terminal** — Execute commands directly from browser
- 📈 **Job History** — Track all past and active scans
- 📖 **Documentation** — Built-in usage guide for all tools

---

## 🏗️ Architecture

```
crawler-toolkit/
├── Dockerfile              # Multi-stage Alpine build
├── docker-compose.yml      # Full stack configuration
├── entrypoint.sh           # Container entry point
├── setup.sh                # Installation wizard
├── config/
│   └── config.ini          # Tool configuration
├── scripts/
│   ├── full-scan.sh        # Full reconnaissance pipeline
│   ├── crawl-only.sh       # Crawling script
│   ├── collect-urls.sh     # URL collection
│   └── js-analyze.sh       # JavaScript analysis
├── dashboard/              # Node.js web interface
│   ├── server.js           # Express + WebSocket server
│   ├── package.json
│   └── public/
│       ├── index.html      # SPA frontend
│       └── static/
│           ├── app.js      # Frontend application
│           └── style.css   # Dark cyber theme
└── wordlists/              # Custom wordlists
```

---

## 🔄 Scan Pipeline (Full Recon)

```
Target URL
    │
    ├─► Phase 1: URL Collection (parallel)
    │       ├─► katana        (active crawling)
    │       ├─► gau           (passive wayback/commoncrawl)
    │       ├─► gospider      (spider + sitemap + robots)
    │       ├─► waymore       (web archive collection)
    │       └─► waybackurls   (wayback machine)
    │
    ├─► Phase 2: Deduplication
    │       └─► uro           (smart URL dedup)
    │
    ├─► Phase 3: HTTP Probing
    │       └─► httpx         (alive check + tech detect)
    │
    ├─► Phase 4: Pattern Matching
    │       └─► gf            (xss/sqli/ssrf/lfi patterns)
    │
    ├─► Phase 5: URL Categorization
    │       ├─► URLs with params
    │       ├─► JavaScript files
    │       ├─► API endpoints
    │       └─► Admin pages
    │
    └─► Phase 6: Report Generation
```

---

## 📁 Output Structure

```
output/<domain>_<timestamp>/
├── katana/
│   ├── results.txt      # All discovered URLs
│   └── results.jsonl    # JSON format with metadata
├── gau/
│   └── results.txt
├── gospider/
│   └── *.txt
├── waymore/
│   ├── results.txt
│   └── wayback.txt
├── xnlink/
│   └── results.txt
├── httpx/
│   ├── alive-urls.txt   # Live URLs with status
│   └── results.json     # Detailed JSON results
├── combined/
│   ├── all-urls-raw.txt     # All raw URLs
│   ├── all-urls-dedup.txt   # Deduplicated URLs
│   ├── urls-with-params.txt # URLs with parameters
│   ├── js-files.txt         # JavaScript files
│   ├── api-endpoints.txt    # API endpoints
│   └── gf-*.txt             # Vulnerability patterns
└── reports/
    └── scan-report.txt  # Summary report
```

---

## 🔧 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 3000 | Dashboard port |
| `THREADS` | 50 | Default thread count |
| `DEPTH` | 3 | Default crawl depth |
| `TIMEOUT` | 10 | Request timeout (seconds) |
| `OUTPUT_DIR` | /workspace/output | Output directory |
| `NODE_ENV` | production | Node.js environment |

---

## 🐳 Docker Commands Reference

```bash
# Build
docker build -t crawler-toolkit:2026 .

# Run dashboard
docker run -d -p 3000:3000 \
  --name crawler \
  -v $(pwd)/output:/workspace/output \
  crawler-toolkit:2026

# Run scan
docker run --rm \
  -v $(pwd)/output:/workspace/output \
  crawler-toolkit:2026 scan https://example.com

# Check tool status
docker run --rm crawler-toolkit:2026 check

# Interactive shell
docker run -it --rm crawler-toolkit:2026 bash

# View logs
docker logs -f crawler

# Stop
docker stop crawler

# Compose up
docker compose up -d

# Compose down
docker compose down

# Compose rebuild
docker compose up -d --build
```

---

## ⚡ Power Tips

```bash
# Combine gau + httpx in one pipeline
echo "example.com" | gau | httpx -sc -title

# Fast subdomain + URL collection
subfinder -d example.com -silent | \
  httpx -silent | \
  katana -d 2 -silent

# Find XSS/SQLi candidates
katana -u https://example.com -d 3 -jc -silent | \
  gf xss | anew xss-candidates.txt

katana -u https://example.com -d 3 -jc -silent | \
  gf sqli | anew sqli-candidates.txt

# Full pipeline one-liner
TARGET="https://example.com"
DOMAIN="example.com"
{
  katana -u $TARGET -d 3 -jc -silent
  echo $DOMAIN | gau --blacklist png,jpg,gif,css
  echo $DOMAIN | waybackurls
  gospider -s $TARGET --js -q
} | uro | sort -u | \
  httpx -sc -title -silent | \
  tee alive-with-info.txt
```

---

## 📄 License

MIT License - Use responsibly and only on targets you have permission to test.

---

**Built for security researchers, bug bounty hunters, and web application testers.**  
*Always obtain proper authorization before scanning any target.*

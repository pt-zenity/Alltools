# ============================================================
# Makefile for Web Crawler Toolkit 2026
# ============================================================

.PHONY: all build run stop restart logs shell scan urls crawl check clean help

IMAGE_NAME = crawler-toolkit
TAG = 2026
CONTAINER_NAME = crawler-toolkit
PORT = 3000

all: build run

# ── Docker Build ──────────────────────────────
build:
	@echo "🔨 Building $(IMAGE_NAME):$(TAG)..."
	docker build --target final -t $(IMAGE_NAME):$(TAG) -t $(IMAGE_NAME):latest .
	@echo "✓ Build complete"

build-no-cache:
	@echo "🔨 Building $(IMAGE_NAME):$(TAG) (no cache)..."
	docker build --no-cache --target final -t $(IMAGE_NAME):$(TAG) -t $(IMAGE_NAME):latest .

# ── Docker Run ────────────────────────────────
run:
	@echo "🚀 Starting dashboard on port $(PORT)..."
	@mkdir -p output targets logs data
	docker run -d \
		--name $(CONTAINER_NAME) \
		-p $(PORT):3000 \
		-v $$(pwd)/output:/workspace/output \
		-v $$(pwd)/targets:/workspace/targets \
		-v $$(pwd)/logs:/logs \
		$(IMAGE_NAME):$(TAG) dashboard
	@echo "✓ Dashboard running at http://localhost:$(PORT)"

# ── Docker Compose ────────────────────────────
up:
	docker compose up -d
	@echo "✓ Services started. Dashboard: http://localhost:$(PORT)"

down:
	docker compose down

restart:
	docker compose restart

rebuild:
	docker compose up -d --build

# ── Scan Operations ───────────────────────────
scan:
	@if [ -z "$(TARGET)" ]; then echo "❌ Usage: make scan TARGET=https://example.com"; exit 1; fi
	@mkdir -p output
	docker run --rm \
		-v $$(pwd)/output:/workspace/output \
		-e THREADS=$(THREADS) -e DEPTH=$(DEPTH) \
		$(IMAGE_NAME):$(TAG) scan $(TARGET)

crawl:
	@if [ -z "$(TARGET)" ]; then echo "❌ Usage: make crawl TARGET=https://example.com"; exit 1; fi
	@mkdir -p output
	docker run --rm \
		-v $$(pwd)/output:/workspace/output \
		$(IMAGE_NAME):$(TAG) crawl $(TARGET)

urls:
	@if [ -z "$(DOMAIN)" ]; then echo "❌ Usage: make urls DOMAIN=example.com"; exit 1; fi
	@mkdir -p output
	docker run --rm \
		-v $$(pwd)/output:/workspace/output \
		$(IMAGE_NAME):$(TAG) urls $(DOMAIN)

# ── Management ────────────────────────────────
stop:
	-docker stop $(CONTAINER_NAME) 2>/dev/null
	-docker rm $(CONTAINER_NAME) 2>/dev/null
	@echo "✓ Container stopped"

logs:
	docker logs -f $(CONTAINER_NAME)

shell:
	docker run -it --rm \
		-v $$(pwd)/output:/workspace/output \
		$(IMAGE_NAME):$(TAG) bash

check:
	docker run --rm $(IMAGE_NAME):$(TAG) check

# ── Cleanup ───────────────────────────────────
clean:
	-docker stop $(CONTAINER_NAME) 2>/dev/null
	-docker rm $(CONTAINER_NAME) 2>/dev/null
	@echo "✓ Cleaned up containers"

clean-all: clean
	-docker rmi $(IMAGE_NAME):$(TAG) $(IMAGE_NAME):latest 2>/dev/null
	@echo "✓ Cleaned up images"

clean-output:
	rm -rf output/*
	@echo "✓ Output directory cleared"

# ── Help ──────────────────────────────────────
help:
	@echo ""
	@echo "🕷️  Web Crawler Toolkit 2026 - Makefile"
	@echo "========================================"
	@echo ""
	@echo "  Build:"
	@echo "    make build          Build Docker image"
	@echo "    make build-no-cache Build without cache"
	@echo ""
	@echo "  Run:"
	@echo "    make run            Start dashboard (port $(PORT))"
	@echo "    make up             Start with Docker Compose"
	@echo "    make down           Stop Docker Compose services"
	@echo "    make restart        Restart services"
	@echo "    make rebuild        Rebuild and restart"
	@echo ""
	@echo "  Scan:"
	@echo "    make scan TARGET=https://example.com"
	@echo "    make crawl TARGET=https://example.com"
	@echo "    make urls DOMAIN=example.com"
	@echo ""
	@echo "  Management:"
	@echo "    make stop           Stop container"
	@echo "    make logs           View container logs"
	@echo "    make shell          Open interactive shell"
	@echo "    make check          Check tool availability"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make clean          Remove containers"
	@echo "    make clean-all      Remove containers + images"
	@echo "    make clean-output   Clear output directory"
	@echo ""
	@echo "  Options:"
	@echo "    TARGET=<url>        Scan target URL"
	@echo "    DOMAIN=<domain>     Target domain"
	@echo "    THREADS=50          Thread count"
	@echo "    DEPTH=3             Crawl depth"
	@echo "    PORT=3000           Dashboard port"
	@echo ""

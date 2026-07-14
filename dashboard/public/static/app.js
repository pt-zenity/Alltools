/**
 * Web Crawler Toolkit 2026 - Frontend Application
 * FIXED: Real-time streaming output via WebSocket subscribe/replay
 */

// ── State ─────────────────────────────────────
const state = {
  ws: null,
  wsReady: false,
  wsReconnectTimer: null,
  currentPage: 'dashboard',
  activeJobs: new Map(),
  jobHistory: [],
  tools: [],
  outputs: [],
  currentScanJobId: null,
  terminalHistory: [],
  selectedFile: null,
  scanType: 'full-scan',
  refreshIntervals: {},
  // live output tracking
  outputLineCount: 0,
  outputAutoScroll: true,
  maxOutputLines: 3000,
};

// ── Tool Definitions ──────────────────────────
const TOOL_INFO = {
  katana:       { icon: '⚡', color: '#6366f1', desc: 'Next-generation crawling framework by ProjectDiscovery. Headless JS support, smart filtering, and structured output.', tags: ['Go','Crawling','JS Rendering','ProjectDiscovery'], cmd: 'katana -u <URL> -d 3 -c 50 -jc -o output.txt' },
  gau:          { icon: '🌐', color: '#22c55e', desc: 'Get All URLs — fetches known URLs from Wayback Machine, OTX, URLScan, and CommonCrawl archives.', tags: ['Go','Passive Recon','Wayback','CommonCrawl'], cmd: 'echo "domain.com" | gau --threads 30 --providers wayback,commoncrawl' },
  waymore:      { icon: '📡', color: '#f59e0b', desc: 'Advanced URL collection tool combining multiple web archive sources with smart filtering and deduplication.', tags: ['Python','URL Collection','Passive','Multi-source'], cmd: 'waymore -i domain.com -mode U -oU output.txt' },
  gospider:     { icon: '🕷️', color: '#06b6d4', desc: 'Fast web spider with sitemap parsing, robots.txt discovery, and JS endpoint extraction capabilities.', tags: ['Go','Spidering','Robots.txt','Sitemap'], cmd: 'gospider -s <URL> -o output/ -c 50 -d 3 --js --sitemap' },
  xnLinkFinder: { icon: '🔗', color: '#a855f7', desc: 'Python-based link finder that discovers endpoints in HTML, JS, and other response bodies via regex patterns.', tags: ['Python','Link Extraction','JS Analysis','Regex'], cmd: 'xnLinkFinder -i <URL> -op output.txt -sp <URL> -d 3' },
  httpx:        { icon: '🔍', color: '#ef4444', desc: 'Fast HTTP toolkit for probing URLs. Detects status codes, titles, technologies, and web server information.', tags: ['Go','HTTP Probing','Tech Detection','ProjectDiscovery'], cmd: 'httpx -l urls.txt -o alive.txt -title -sc -ct -server' },
  subfinder:    { icon: '🌿', color: '#22c55e', desc: 'Passive subdomain discovery tool using 100+ data sources including DNS resolvers and certificate logs.', tags: ['Go','Subdomains','Passive','OSINT'], cmd: 'subfinder -d domain.com -o subdomains.txt' },
  nuclei:       { icon: '☢️', color: '#f59e0b', desc: 'Fast and customizable vulnerability scanner based on YAML templates. 10000+ community templates.', tags: ['Go','Vulnerability','Templates','ProjectDiscovery'], cmd: 'nuclei -u <URL> -t cves/ -o results.txt' },
  dnsx:         { icon: '🧮', color: '#06b6d4', desc: 'Fast and multi-purpose DNS toolkit for running various probes, DNS bruteforcing, and zone transfers.', tags: ['Go','DNS','Recon','ProjectDiscovery'], cmd: 'dnsx -d domain.com -a -aaaa -cname -mx -o dns.txt' },
  naabu:        { icon: '🔌', color: '#6366f1', desc: 'Fast port scanner built around SYN/CONNECT probes with service discovery and rate limiting.', tags: ['Go','Port Scanner','Network','ProjectDiscovery'], cmd: 'naabu -host domain.com -p 80,443,8080 -o ports.txt' },
  waybackurls:  { icon: '⏮️', color: '#a855f7', desc: 'Fetch all known URLs from the Wayback Machine for a given domain. Simple and fast.', tags: ['Go','Wayback','URLs','tomnomnom'], cmd: 'echo "domain.com" | waybackurls > urls.txt' },
  anew:         { icon: '✨', color: '#22c55e', desc: 'Append new lines to file, skipping duplicates. Essential for pipeline-based URL collection workflows.', tags: ['Go','Dedup','Pipeline','tomnomnom'], cmd: 'cat new-urls.txt | anew all-urls.txt' },
  gf:           { icon: '🎯', color: '#ef4444', desc: 'Grep with patterns — find XSS, SQLi, SSRF, LFI, and other vulnerability patterns in URL lists.', tags: ['Go','Pattern Match','Vuln Patterns','tomnomnom'], cmd: 'gf xss urls.txt | gf sqli | tee vuln-urls.txt' },
  uro:          { icon: '🧹', color: '#06b6d4', desc: 'URL deduplication tool that intelligently removes duplicate and low-value URLs from collections.', tags: ['Python','Dedup','URL Filter','Optimization'], cmd: 'cat urls.txt | uro > deduped.txt' },
  unfurl:       { icon: '🔓', color: '#f59e0b', desc: 'Pull out bits of URLs. Extract paths, domains, parameters, values, and more from URL lists.', tags: ['Go','URL Parsing','Extraction','tomnomnom'], cmd: 'cat urls.txt | unfurl domains' },
  node:         { icon: '🟢', color: '#22c55e', desc: 'Node.js runtime for JavaScript execution. Powering the dashboard and custom JS-based scrapers.', tags: ['Runtime','JavaScript','V8','Dashboard'], cmd: 'node --version' },
  python3:      { icon: '🐍', color: '#f59e0b', desc: 'Python 3 runtime for Python-based tools like waymore, xnLinkFinder, and uro.', tags: ['Runtime','Python','Scripting'], cmd: 'python3 --version' }
};

// ── Initialize ────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initClock();
  initNavigation();
  initSidebarToggle();
  initWebSocket();
  initScanForm();
  initTerminal();
  initOutputControls();
  loadDashboard();

  state.refreshIntervals.dashboard = setInterval(loadDashboard, 15000);
});

// ── Clock ─────────────────────────────────────
function initClock() {
  const update = () => {
    const now = new Date();
    const el = document.getElementById('clock');
    if (el) el.textContent = now.toUTCString().replace(' GMT','').split(',')[1]?.trim().substring(0,17) || '';
  };
  update();
  setInterval(update, 1000);
}

// ── Navigation ────────────────────────────────
function initNavigation() {
  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', e => {
      e.preventDefault();
      navigateTo(item.dataset.page);
    });
  });
}

function navigateTo(page) {
  document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
  const navItem = document.querySelector(`.nav-item[data-page="${page}"]`);
  if (navItem) navItem.classList.add('active');

  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const pageEl = document.getElementById(`page-${page}`);
  if (pageEl) pageEl.classList.add('active');

  const titles = { dashboard:'Dashboard', scan:'New Scan', jobs:'Jobs', results:'Results', tools:'Tools', terminal:'Terminal', docs:'Documentation' };
  const titleEl = document.getElementById('page-title');
  if (titleEl) titleEl.textContent = titles[page] || page;
  state.currentPage = page;

  if (page === 'tools'   && state.tools.length === 0) loadTools();
  if (page === 'results') loadOutputs();
  if (page === 'jobs')    loadJobs();
  if (page === 'docs')    loadDocs();
}

// ── Sidebar Toggle ────────────────────────────
function initSidebarToggle() {
  const btn = document.getElementById('sidebar-toggle');
  if (btn) btn.addEventListener('click', () => {
    document.getElementById('sidebar')?.classList.toggle('collapsed');
  });
}

// ── WebSocket ─────────────────────────────────
function initWebSocket() {
  if (state.ws && state.ws.readyState === WebSocket.OPEN) return;

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}`;

  state.ws = new WebSocket(wsUrl);
  state.wsReady = false;

  state.ws.onopen = () => {
    state.wsReady = true;
    setWsStatus('connected');
    if (state.wsReconnectTimer) { clearTimeout(state.wsReconnectTimer); state.wsReconnectTimer = null; }

    // Re-subscribe to current job if there is one running
    if (state.currentScanJobId) {
      subscribeToJob(state.currentScanJobId, state.outputLineCount);
    }
  };

  state.ws.onmessage = event => {
    try { handleWsMessage(JSON.parse(event.data)); } catch {}
  };

  state.ws.onclose = () => {
    state.wsReady = false;
    setWsStatus('disconnected');
    state.wsReconnectTimer = setTimeout(initWebSocket, 3000);
  };

  state.ws.onerror = () => {
    state.wsReady = false;
    setWsStatus('disconnected');
  };
}

function wsSend(obj) {
  if (state.ws && state.ws.readyState === WebSocket.OPEN) {
    state.ws.send(JSON.stringify(obj));
  }
}

function subscribeToJob(jobId, fromLine = 0) {
  wsSend({ type: 'subscribe', jobId, from: fromLine });
}

function setWsStatus(status) {
  const dot  = document.getElementById('ws-dot');
  const text = document.getElementById('ws-text');
  if (dot)  dot.className  = `ws-dot ${status}`;
  if (text) text.textContent = status === 'connected' ? 'Connected' : 'Disconnected';
}

// ── WebSocket message handler ─────────────────
function handleWsMessage(data) {
  switch (data.type) {
    case 'connected':
      break;

    case 'job-started':
      state.activeJobs.set(data.jobId, {
        id: data.jobId, type: data.scanType,
        target: data.target, status: 'running', startTime: data.timestamp, lineCount: 0
      });
      updateJobBadge();

      // If this is the current scan, subscribe and show panel
      if (state.currentScanJobId === data.jobId) {
        subscribeToJob(data.jobId);
        showOutputPanel(data.jobId, data.scanType, data.target);
      }

      toast(`Scan started: ${data.target || data.jobId.substring(0,8)}`, 'info');
      if (state.currentPage === 'jobs') loadJobs();
      break;

    case 'job-output':
      if (data.replay) {
        // Replayed lines: append only if we're actually watching this job
        if (state.currentScanJobId === data.jobId) {
          appendOutputLine(data.line, data.stream, true);
        }
      } else {
        // Live line
        if (state.currentScanJobId === data.jobId) {
          appendOutputLine(data.line, data.stream);
          updateOutputStats(data.lineNum);
        }
        // Update jobs page live counter
        const activeJobEl = document.getElementById(`job-linecount-${data.jobId}`);
        if (activeJobEl) activeJobEl.textContent = `${data.lineNum} lines`;
      }
      break;

    case 'job-complete':
      state.activeJobs.delete(data.jobId);
      updateJobBadge();

      if (state.currentScanJobId === data.jobId) {
        finalizeOutputPanel(data);
      }

      toast(
        `Scan finished! ${data.lineCount} lines · exit ${data.exitCode}`,
        data.exitCode === 0 ? 'success' : 'warning'
      );
      if (state.currentPage === 'jobs') loadJobs();
      loadDashboard();
      break;

    case 'job-stopped':
      state.activeJobs.delete(data.jobId);
      updateJobBadge();
      if (state.currentScanJobId === data.jobId) {
        appendOutputLine('⚠ Scan stopped by user.', 'warning');
        setScanRunning(false);
      }
      toast('Job stopped', 'warning');
      if (state.currentPage === 'jobs') loadJobs();
      break;

    case 'job-error':
      toast(`Error: ${data.message}`, 'error');
      if (state.currentScanJobId === data.jobId) {
        appendOutputLine(`✕ Error: ${data.message}`, 'stderr');
        setScanRunning(false);
      }
      break;
  }
}

// ── Output Panel ──────────────────────────────

function initOutputControls() {
  // Auto-scroll toggle
  const terminal = document.getElementById('output-terminal');
  if (terminal) {
    terminal.addEventListener('scroll', () => {
      const atBottom = terminal.scrollTop + terminal.clientHeight >= terminal.scrollHeight - 40;
      state.outputAutoScroll = atBottom;
      const btn = document.getElementById('autoscroll-btn');
      if (btn) btn.classList.toggle('active', state.outputAutoScroll);
    });
  }
}

function showOutputPanel(jobId, scanType, target) {
  const panel = document.getElementById('scan-output-panel');
  if (!panel) return;

  panel.style.display = 'block';

  // Update header info
  const jobIdEl = document.getElementById('live-job-id');
  if (jobIdEl) jobIdEl.textContent = jobId.substring(0, 8);

  const scanLabelEl = document.getElementById('live-scan-label');
  if (scanLabelEl) scanLabelEl.textContent = `${scanType} → ${target || ''}`;

  setScanRunning(true);

  // Clear terminal
  const terminal = document.getElementById('output-terminal');
  if (terminal) {
    terminal.innerHTML = '';
    state.outputLineCount = 0;
    state.outputAutoScroll = true;
  }

  updateOutputStats(0);
  panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function setScanRunning(running) {
  const stopBtn  = document.getElementById('stop-btn');
  const statusEl = document.getElementById('live-scan-status');

  if (stopBtn)  stopBtn.disabled = !running;
  if (statusEl) {
    statusEl.textContent  = running ? '● RUNNING' : '■ DONE';
    statusEl.className    = `live-status ${running ? 'running' : 'done'}`;
  }
}

function updateOutputStats(lineNum) {
  state.outputLineCount = lineNum;
  const el = document.getElementById('output-line-count');
  if (el) el.textContent = `${lineNum} lines`;
}

function finalizeOutputPanel(data) {
  setScanRunning(false);

  const durationEl = document.getElementById('live-duration');
  if (durationEl && data.duration) {
    const sec = Math.round(data.duration / 1000);
    durationEl.textContent = sec >= 60 ? `${Math.floor(sec/60)}m ${sec%60}s` : `${sec}s`;
  }

  appendOutputLine(
    `\n━━━ Scan complete ━━━  exit=${data.exitCode}  lines=${data.lineCount}  ${data.duration ? Math.round(data.duration/1000)+'s' : ''}`,
    'success'
  );

  if (data.outputFiles && data.outputFiles.length > 0) {
    appendOutputLine(`📁 ${data.outputFiles.length} output file(s) written.`, 'info');
  }
}

/**
 * Append one line to the output terminal.
 * @param {string} text
 * @param {string} stream  'stdout' | 'stderr' | 'info' | 'success' | 'warning'
 * @param {boolean} silent  don't scroll (batch replay)
 */
function appendOutputLine(text, stream = 'stdout', silent = false) {
  const terminal = document.getElementById('output-terminal');
  if (!terminal) return;

  // Trim old lines to avoid DOM blowup
  while (terminal.children.length > state.maxOutputLines) {
    terminal.removeChild(terminal.firstChild);
  }

  // Strip common ANSI escape codes for clean display
  const clean = stripAnsi(text);
  if (!clean && !text.startsWith('\n')) return;

  const div = document.createElement('div');
  div.className = `terminal-line ${stream}`;

  // Highlight URLs in stdout
  const htmlContent = stream === 'stdout'
    ? highlightUrls(escapeHtml(clean))
    : escapeHtml(clean);

  // Prefix icon based on stream
  const prefix = {
    stderr:  '<span class="line-prefix stderr-prefix">ERR</span>',
    info:    '<span class="line-prefix info-prefix">INF</span>',
    success: '<span class="line-prefix ok-prefix"> OK</span>',
    warning: '<span class="line-prefix warn-prefix">WRN</span>',
    stdout:  ''
  }[stream] || '';

  div.innerHTML = `${prefix}<span class="terminal-text">${htmlContent}</span>`;
  terminal.appendChild(div);

  if (!silent && state.outputAutoScroll) {
    terminal.scrollTop = terminal.scrollHeight;
  }
}

function toggleAutoScroll() {
  state.outputAutoScroll = !state.outputAutoScroll;
  const btn = document.getElementById('autoscroll-btn');
  if (btn) btn.classList.toggle('active', state.outputAutoScroll);
  if (state.outputAutoScroll) {
    const terminal = document.getElementById('output-terminal');
    if (terminal) terminal.scrollTop = terminal.scrollHeight;
  }
}

function scrollToBottom() {
  const terminal = document.getElementById('output-terminal');
  if (terminal) terminal.scrollTop = terminal.scrollHeight;
  state.outputAutoScroll = true;
}

// ── Dashboard ─────────────────────────────────
async function loadDashboard() {
  try {
    const [sysData, toolsData, outputsData, historyData] = await Promise.all([
      fetch('/api/system').then(r => r.json()),
      fetch('/api/tools').then(r => r.json()),
      fetch('/api/outputs').then(r => r.json()),
      fetch('/api/jobs/history').then(r => r.json())
    ]);

    const available = toolsData.tools?.filter(t => t.available).length || 0;
    state.tools     = toolsData.tools || [];

    setStatValue('stat-active-count',  sysData.activeJobs  || 0);
    setStatValue('stat-total-count',   sysData.totalJobs   || 0);
    setStatValue('stat-outputs-count', outputsData.length  || 0);
    setStatValue('stat-tools-count',   `${available}/${state.tools.length}`);

    state.jobHistory = historyData;
    renderRecentJobs(historyData.slice(0, 5));
    renderToolStatusGrid(state.tools.slice(0, 12));
  } catch (e) {
    console.error('Dashboard load error:', e);
  }
}

function setStatValue(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

function renderRecentJobs(jobs) {
  const container = document.getElementById('recent-jobs-list');
  if (!container) return;
  if (!jobs || jobs.length === 0) {
    container.innerHTML = `<div class="empty-state"><i class="fas fa-inbox"></i><p>No jobs yet</p></div>`;
    return;
  }
  container.innerHTML = jobs.map(job => `
    <div class="job-item">
      <div class="job-status-indicator ${job.status}"></div>
      <div class="job-info">
        <div class="job-target">${escapeHtml(job.options?.target || 'Unknown')}</div>
        <div class="job-meta">${formatTime(job.startTime)} · ${job.type} · ${job.lineCount||0} lines</div>
      </div>
      <span class="job-type-badge">${job.type}</span>
    </div>
  `).join('');
}

function renderToolStatusGrid(tools) {
  const container = document.getElementById('tool-status-grid');
  if (!container) return;
  if (!tools || tools.length === 0) {
    container.innerHTML = '<div class="loading-spinner"><i class="fas fa-spinner fa-spin"></i> Loading...</div>';
    return;
  }
  container.innerHTML = tools.map(tool => `
    <div class="tool-card ${tool.available ? 'available' : 'unavailable'}">
      <div class="tool-status-dot ${tool.available ? 'ok' : 'fail'}"></div>
      <div>
        <div class="tool-card-name">${tool.name}</div>
        <div class="tool-card-ver">${tool.version}</div>
      </div>
    </div>
  `).join('');
}

// ── Tools Page ────────────────────────────────
async function loadTools() {
  try {
    const data = await fetch('/api/tools').then(r => r.json());
    state.tools = data.tools || [];
    renderToolsDetail(state.tools);
    renderToolStatusGrid(state.tools.slice(0, 12));
    const available = state.tools.filter(t => t.available).length;
    setStatValue('stat-tools-count', `${available}/${state.tools.length}`);
  } catch (e) { console.error('Tools load error:', e); }
}

function renderToolsDetail(tools) {
  const container = document.getElementById('tools-detail-grid');
  if (!container) return;
  container.innerHTML = tools.map(tool => {
    const info = TOOL_INFO[tool.name] || {};
    return `
      <div class="tool-detail-card">
        <div class="tool-detail-header">
          <div class="tool-detail-icon" style="background:${info.color||'#6366f1'}22;color:${info.color||'#6366f1'}">${info.icon||'🔧'}</div>
          <div><div class="tool-detail-name">${tool.name}</div></div>
          <span class="tool-detail-status ${tool.available?'ok':'fail'}">${tool.available?'● Available':'● Missing'}</span>
        </div>
        <div class="tool-detail-body">
          <p class="tool-detail-desc">${info.desc||'Security/recon tool'}</p>
          <div class="tool-detail-ver">${tool.version||'version unknown'}</div>
          ${info.cmd?`<div class="tool-detail-ver"><strong>Example:</strong><br><code>${escapeHtml(info.cmd)}</code></div>`:''}
          <div class="tool-detail-tags">${(info.tags||[]).map(t=>`<span class="tool-tag">${t}</span>`).join('')}</div>
        </div>
      </div>`;
  }).join('');
}

// ── Scan Form ─────────────────────────────────
function initScanForm() {
  document.querySelectorAll('.scan-type-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.scan-type-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      state.scanType = btn.dataset.type;
    });
  });

  const depthInput   = document.getElementById('scan-depth');
  const threadsInput = document.getElementById('scan-threads');
  if (depthInput)   depthInput.addEventListener('input',   () => { document.getElementById('scan-depth-val').textContent   = depthInput.value; });
  if (threadsInput) threadsInput.addEventListener('input', () => { document.getElementById('scan-threads-val').textContent = threadsInput.value; });

  const scanTypeSelect = document.getElementById('scan-type');
  if (scanTypeSelect) {
    scanTypeSelect.addEventListener('change', () => {
      const customGroup = document.getElementById('custom-cmd-group');
      if (customGroup) customGroup.style.display = scanTypeSelect.value === 'custom' ? 'flex' : 'none';
    });
  }

  const quickTarget = document.getElementById('quick-target');
  if (quickTarget) quickTarget.addEventListener('keypress', e => { if (e.key === 'Enter') quickScan(); });

  const scanTarget = document.getElementById('scan-target');
  if (scanTarget) scanTarget.addEventListener('keypress', e => { if (e.key === 'Enter') startScan(); });
}

function quickScan() {
  const target = document.getElementById('quick-target')?.value?.trim();
  if (!target) { toast('Please enter a target URL', 'warning'); return; }
  navigateTo('scan');
  const scanTargetEl = document.getElementById('scan-target');
  if (scanTargetEl) scanTargetEl.value = target;
  setTimeout(startScan, 300);
}

async function startScan() {
  const target  = document.getElementById('scan-target')?.value?.trim();
  const type    = document.getElementById('scan-type')?.value || 'full-scan';
  const depth   = document.getElementById('scan-depth')?.value || '3';
  const threads = document.getElementById('scan-threads')?.value || '50';
  const command = document.getElementById('scan-custom-cmd')?.value?.trim();

  if (!target && type !== 'custom') {
    toast('Please enter a target URL or domain', 'warning');
    return;
  }

  // Prepare terminal immediately (optimistic)
  const jobIdTemp = '--------';
  const terminal = document.getElementById('output-terminal');
  if (terminal) {
    terminal.innerHTML = '';
    state.outputLineCount = 0;
    state.outputAutoScroll = true;
    appendOutputLine(`► Starting ${type} scan on ${target || command}…`, 'info');
  }

  const panel = document.getElementById('scan-output-panel');
  if (panel) {
    panel.style.display = 'block';
    panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
    const scanLabelEl = document.getElementById('live-scan-label');
    if (scanLabelEl) scanLabelEl.textContent = `${type} → ${target || ''}`;
    setScanRunning(true);
  }

  try {
    const response = await fetch('/api/scan/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, target, depth, threads, command })
    });

    const data = await response.json();

    if (data.error) {
      toast(`Error: ${data.error}`, 'error');
      setScanRunning(false);
      return;
    }

    if (data.jobId) {
      state.currentScanJobId = data.jobId;

      const jobIdEl = document.getElementById('live-job-id');
      if (jobIdEl) jobIdEl.textContent = data.jobId.substring(0, 8);

      // Subscribe immediately so we get all output
      subscribeToJob(data.jobId, 0);

      toast(`Job started: ${data.jobId.substring(0,8)}`, 'success');
      updateJobBadge();
    }
  } catch (e) {
    toast('Failed to start scan: ' + e.message, 'error');
    setScanRunning(false);
  }
}

function resetScanForm() {
  const fields = ['scan-target','scan-type','scan-depth','scan-threads'];
  const vals   = ['','full-scan','3','50'];
  fields.forEach((id, i) => {
    const el = document.getElementById(id);
    if (el) el.value = vals[i];
  });
  setStatValue('scan-depth-val',   '3');
  setStatValue('scan-threads-val', '50');
  const panel = document.getElementById('scan-output-panel');
  if (panel) panel.style.display = 'none';
  state.currentScanJobId = null;
}

async function stopCurrentScan() {
  if (!state.currentScanJobId) return;
  try {
    await fetch(`/api/scan/stop/${state.currentScanJobId}`, { method: 'POST' });
    toast('Stop signal sent', 'warning');
  } catch (e) {
    toast('Failed to stop: ' + e.message, 'error');
  }
}

function clearOutput() {
  const terminal = document.getElementById('output-terminal');
  if (terminal) { terminal.innerHTML = ''; state.outputLineCount = 0; }
}

// ── Jobs Page ─────────────────────────────────
async function loadJobs() {
  try {
    const [activeData, historyData] = await Promise.all([
      fetch('/api/jobs/active').then(r => r.json()),
      fetch('/api/jobs/history').then(r => r.json())
    ]);
    renderActiveJobs(activeData);
    renderJobHistory(historyData);
    updateJobBadge(activeData.length);
  } catch {}
}

function renderActiveJobs(jobs) {
  const container = document.getElementById('jobs-active-list');
  if (!container) return;
  if (!jobs || jobs.length === 0) {
    container.innerHTML = `<div class="empty-state"><i class="fas fa-pause-circle"></i><p>No active jobs</p></div>`;
    return;
  }
  container.innerHTML = jobs.map(job => `
    <div class="job-item active-job-row" id="job-row-${job.id}">
      <div class="job-status-indicator running"></div>
      <div class="job-info">
        <div class="job-target">${escapeHtml(job.options?.target || 'Custom job')}</div>
        <div class="job-meta">
          Started: ${formatTime(job.startTime)} ·
          <span id="job-linecount-${job.id}">${job.lineCount||0} lines</span>
        </div>
      </div>
      <span class="job-type-badge">${job.type}</span>
      <button class="btn-sm" onclick="viewJobOutput('${job.id}')">
        <i class="fas fa-terminal"></i> View
      </button>
      <button class="btn-sm btn-danger" onclick="stopJob('${job.id}')">
        <i class="fas fa-stop"></i> Stop
      </button>
    </div>
  `).join('');
}

function renderJobHistory(jobs) {
  const container = document.getElementById('jobs-history-list');
  if (!container) return;
  if (!jobs || jobs.length === 0) {
    container.innerHTML = `<div class="empty-state"><i class="fas fa-history"></i><p>No job history</p></div>`;
    return;
  }
  container.innerHTML = jobs.map(job => `
    <div class="job-item">
      <div class="job-status-indicator ${job.status}"></div>
      <div class="job-info">
        <div class="job-target">${escapeHtml(job.options?.target || 'Custom job')}</div>
        <div class="job-meta">${formatTime(job.startTime)} · exit ${job.exitCode ?? '-'} · ${job.lineCount||0} lines</div>
      </div>
      <span class="job-type-badge">${job.type}</span>
      <button class="btn-sm" onclick="viewJobOutput('${job.id}')">
        <i class="fas fa-terminal"></i> Logs
      </button>
    </div>
  `).join('');
}

// View a job's output in the scan panel
async function viewJobOutput(jobId) {
  navigateTo('scan');
  state.currentScanJobId = jobId;

  const terminal = document.getElementById('output-terminal');
  if (terminal) {
    terminal.innerHTML = '';
    state.outputLineCount = 0;
    state.outputAutoScroll = true;
    appendOutputLine(`► Loading output for job ${jobId.substring(0,8)}…`, 'info');
  }

  const panel = document.getElementById('scan-output-panel');
  if (panel) {
    panel.style.display = 'block';
    const jobIdEl = document.getElementById('live-job-id');
    if (jobIdEl) jobIdEl.textContent = jobId.substring(0, 8);
  }

  // Fetch buffered output via REST
  try {
    const data = await fetch(`/api/jobs/${jobId}/output`).then(r => r.json());
    if (terminal) terminal.innerHTML = '';

    const isRunning = data.status === 'running';
    setScanRunning(isRunning);

    data.lines.forEach(entry => appendOutputLine(entry.text, entry.stream, true));
    updateOutputStats(data.lineCount);

    if (isRunning) {
      // Subscribe to live updates from where we left off
      subscribeToJob(jobId, data.lines.length);
      appendOutputLine('── live output below ──', 'info');
    } else {
      appendOutputLine(`── job ${data.status} ──`, 'success');
    }

    // Scroll to bottom after replay
    if (terminal) terminal.scrollTop = terminal.scrollHeight;
  } catch (e) {
    appendOutputLine(`Error loading output: ${e.message}`, 'stderr');
  }
}

async function stopJob(jobId) {
  try {
    await fetch(`/api/scan/stop/${jobId}`, { method: 'POST' });
    toast('Job stopped', 'warning');
    loadJobs();
  } catch { toast('Failed to stop job', 'error'); }
}

function updateJobBadge(count) {
  const badge = document.getElementById('active-job-badge');
  const n = count !== undefined ? count : state.activeJobs.size;
  if (badge) {
    badge.textContent = n;
    badge.classList.toggle('visible', n > 0);
  }
}

// ── Tab switching ─────────────────────────────
document.addEventListener('click', e => {
  if (!e.target.classList.contains('tab')) return;
  const container = e.target.closest('.panel');
  if (!container) return;

  container.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  e.target.classList.add('active');

  const tab = e.target.dataset.tab;
  const active  = document.getElementById('jobs-active-list');
  const history = document.getElementById('jobs-history-list');
  if (active)  active.style.display  = tab === 'active'  ? 'flex' : 'none';
  if (history) history.style.display = tab === 'history' ? 'flex' : 'none';
});

// ── Results / Outputs ─────────────────────────
async function loadOutputs() {
  try {
    const outputs = await fetch('/api/outputs').then(r => r.json());
    state.outputs = outputs;
    renderFileTree(outputs);
  } catch {}
}

function renderFileTree(outputs) {
  const tree = document.getElementById('output-tree');
  if (!tree) return;
  if (!outputs || outputs.length === 0) {
    tree.innerHTML = `<div class="empty-state"><i class="fas fa-folder-open"></i><p>No output files yet</p></div>`;
    return;
  }
  tree.innerHTML = outputs.map(dir => `
    <div class="file-tree-dir" id="dir-${dir.name}">
      <div class="file-tree-dir-name" onclick="toggleDir('${escapeHtml(dir.name)}')">
        <i class="fas fa-folder"></i>
        <span title="${escapeHtml(dir.name)}">${dir.name.length > 30 ? dir.name.substring(0,30)+'…' : escapeHtml(dir.name)}</span>
        <span class="file-size">${dir.fileCount} files · ${formatSize(dir.totalSize)}</span>
      </div>
      <div class="file-tree-files" id="files-${dir.name}">
        <div class="loading-spinner"><i class="fas fa-spinner fa-spin"></i></div>
      </div>
    </div>
  `).join('');
}

async function toggleDir(dirName) {
  const dirEl   = document.getElementById(`dir-${dirName}`);
  const filesEl = document.getElementById(`files-${dirName}`);
  if (!dirEl) return;

  if (dirEl.classList.contains('open')) { dirEl.classList.remove('open'); return; }
  dirEl.classList.add('open');

  if (filesEl && filesEl.querySelector('.loading-spinner')) {
    try {
      const files = await fetch(`/api/outputs/${encodeURIComponent(dirName)}/files`).then(r => r.json());
      filesEl.innerHTML = files.map(file => `
        <div class="file-tree-file" onclick="viewFile('${escapeHtml(file.path)}', '${escapeHtml(file.name)}')">
          <i class="${getFileIcon(file.name)}"></i>
          <span>${escapeHtml(file.name)}</span>
          <span class="file-size">${formatSize(file.size)}</span>
        </div>
      `).join('') || '<div class="file-tree-file"><span>No files</span></div>';
    } catch {
      filesEl.innerHTML = '<div class="file-tree-file"><span>Error loading files</span></div>';
    }
  }
}

async function viewFile(filePath, fileName) {
  state.selectedFile = filePath;
  document.querySelectorAll('.file-tree-file').forEach(f => f.classList.remove('active'));
  event?.target?.closest?.('.file-tree-file')?.classList.add('active');

  const viewer = document.getElementById('file-viewer');
  if (!viewer) return;
  viewer.innerHTML = `<div class="loading-spinner"><i class="fas fa-spinner fa-spin"></i> Loading…</div>`;

  try {
    const data = await fetch(`/api/file?path=${encodeURIComponent(filePath)}&lines=1000`).then(r => r.json());
    const lineCount = data.content.split('\n').length;
    viewer.innerHTML = `
      <div class="file-viewer-header">${escapeHtml(fileName)} · ${lineCount} lines${data.truncated?' (truncated)':''}</div>
      <pre>${escapeHtml(data.content)}</pre>`;

    const actions = document.getElementById('file-viewer-actions');
    const dlBtn   = document.getElementById('download-file-btn');
    if (actions && dlBtn) {
      actions.style.display = 'flex';
      dlBtn.onclick = () => window.open(`/api/download?path=${encodeURIComponent(filePath)}`);
    }

    const header = document.querySelector('#page-results .panel-header h3');
    if (header) header.textContent = `File: ${fileName}`;
  } catch {
    viewer.innerHTML = `<div class="file-viewer-placeholder"><i class="fas fa-exclamation-triangle"></i><p>Error loading file</p></div>`;
  }
}

// ── Terminal Page ─────────────────────────────
function initTerminal() {
  const input = document.getElementById('terminal-input');
  if (!input) return;

  let histIdx = -1;
  input.addEventListener('keypress', e => { if (e.key === 'Enter') execTerminalCmd(); });
  input.addEventListener('keydown',  e => {
    if (e.key === 'ArrowUp') {
      histIdx = Math.min(histIdx + 1, state.terminalHistory.length - 1);
      input.value = state.terminalHistory[histIdx] || '';
    } else if (e.key === 'ArrowDown') {
      histIdx = Math.max(histIdx - 1, -1);
      input.value = histIdx >= 0 ? state.terminalHistory[histIdx] : '';
    }
  });
}

async function execTerminalCmd() {
  const input = document.getElementById('terminal-input');
  const cmd = input?.value?.trim();
  if (!cmd) return;

  state.terminalHistory.unshift(cmd);
  input.value = '';

  appendToTerminalHistory(`$ ${cmd}`, 'prompt');

  try {
    const data = await fetch('/api/exec', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command: cmd, timeout: 30000 })
    }).then(r => r.json());

    if (data.stdout) data.stdout.split('\n').forEach(line => { if (line.trim()) appendToTerminalHistory(line, 'stdout'); });
    if (data.stderr) data.stderr.split('\n').forEach(line => { if (line.trim()) appendToTerminalHistory(line, 'stderr'); });
    appendToTerminalHistory(`[exit: ${data.exitCode}]`, data.exitCode === 0 ? 'success' : 'warning');
  } catch (e) {
    appendToTerminalHistory(`Error: ${e.message}`, 'stderr');
  }
}

function appendToTerminalHistory(text, type) {
  const history = document.getElementById('terminal-history');
  if (!history) return;

  const line = document.createElement('div');
  line.className = 'terminal-line';
  const cls = { prompt:'info', stdout:'stdout', stderr:'stderr', success:'success', warning:'warning' }[type] || 'stdout';
  line.innerHTML = `<span class="terminal-text ${cls}">${escapeHtml(text)}</span>`;
  history.appendChild(line);
  history.scrollTop = history.scrollHeight;
}

// ── Docs Page ─────────────────────────────────
function loadDocs() {
  const container = document.getElementById('docs-content');
  if (!container || container.dataset.loaded) return;
  container.dataset.loaded = '1';

  container.innerHTML = `
    <div class="docs-grid">
      <div class="docs-card"><h3><i class="fas fa-spider"></i> katana - Next-Gen Crawler</h3>
        <pre>katana -u https://target.com -d 3 -c 50 -jc -fx -xhr -aff -rl 150 -o output.txt</pre>
        <ul><li><code>-d</code> Crawl depth</li><li><code>-jc</code> JS crawling</li><li><code>-fx</code> Extract from responses</li><li><code>-xhr</code> Capture XHR requests</li></ul></div>
      <div class="docs-card"><h3><i class="fas fa-globe"></i> gau - Get All URLs</h3>
        <pre>echo "target.com" | gau --threads 30 --providers wayback,commoncrawl,otx,urlscan --blacklist png,jpg,gif,css</pre>
        <ul><li><code>--providers</code> Choose sources</li><li><code>--blacklist</code> Skip extensions</li><li><code>--subs</code> Include subdomains</li></ul></div>
      <div class="docs-card"><h3><i class="fas fa-satellite"></i> waymore</h3>
        <pre>waymore -i target.com -mode U -oU urls.txt -p 50</pre>
        <ul><li><code>-mode U</code> URL mode</li><li><code>-mode R</code> Response mode</li></ul></div>
      <div class="docs-card"><h3><i class="fas fa-spider"></i> gospider</h3>
        <pre>gospider -s https://target.com -o output/ -c 50 -d 3 --js --sitemap --robots</pre></div>
      <div class="docs-card"><h3><i class="fas fa-search"></i> httpx - HTTP Probe</h3>
        <pre>httpx -l urls.txt -o alive.txt -title -sc -ct -server -tech-detect -threads 50</pre></div>
      <div class="docs-card"><h3><i class="fas fa-magic"></i> Full Pipeline</h3>
        <pre>TARGET="https://example.com"; DOMAIN="example.com"
katana -u $TARGET -d 3 -jc | anew urls.txt
echo $DOMAIN | gau | anew urls.txt
cat urls.txt | uro | sort -u > dedup.txt
httpx -l dedup.txt -o alive.txt -sc -title
gf xss dedup.txt > xss.txt
gf sqli dedup.txt > sqli.txt</pre></div>
      <div class="docs-card"><h3><i class="fab fa-docker"></i> Docker Usage</h3>
        <pre>docker compose up -d          # Start dashboard on port 8888
docker exec -it crawler-toolkit bash   # Shell
docker logs -f crawler-toolkit         # Logs</pre></div>
    </div>`;
}

// ── Utility Functions ─────────────────────────
function stripAnsi(str) {
  // Remove ANSI escape codes (colors, cursor movement, etc.)
  return String(str || '').replace(/\x1B\[[0-9;]*[mGKHFABCDsuJr]/g, '').replace(/\x1B\][^\x07]*\x07/g, '');
}

function highlightUrls(html) {
  return html.replace(/(https?:\/\/[^\s&"<>]+)/g,
    '<a href="$1" target="_blank" rel="noopener" class="output-url">$1</a>');
}

function formatTime(iso) {
  if (!iso) return 'N/A';
  return new Date(iso).toLocaleTimeString();
}

function formatSize(bytes) {
  if (!bytes || bytes === 0) return '0B';
  const k = 1024, sizes = ['B','KB','MB','GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + sizes[i];
}

function escapeHtml(text) {
  const map = { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#039;' };
  return String(text || '').replace(/[&<>"']/g, m => map[m]);
}

function getFileIcon(name) {
  if (name.endsWith('.txt'))               return 'fas fa-file-alt';
  if (name.endsWith('.json') || name.endsWith('.jsonl')) return 'fas fa-file-code';
  if (name.endsWith('.log'))               return 'fas fa-file-medical';
  if (name.endsWith('.csv'))               return 'fas fa-file-csv';
  if (name.endsWith('.html'))              return 'fab fa-html5';
  if (name.endsWith('.js'))                return 'fab fa-js';
  return 'fas fa-file';
}

function toast(message, type = 'info') {
  const container = document.getElementById('toast-container');
  if (!container) return;
  const el   = document.createElement('div');
  const icons = { success:'✓', error:'✕', info:'ℹ', warning:'⚠' };
  el.className = `toast ${type}`;
  el.innerHTML = `<span>${icons[type]||'ℹ'}</span>${escapeHtml(message)}`;
  container.appendChild(el);
  setTimeout(() => {
    el.style.opacity   = '0';
    el.style.transform = 'translateX(100%)';
    el.style.transition = 'all 0.3s';
    setTimeout(() => el.remove(), 300);
  }, 4000);
}

function refreshPage() {
  loadDashboard();
  if (state.currentPage === 'tools')   loadTools();
  if (state.currentPage === 'results') loadOutputs();
  if (state.currentPage === 'jobs')    loadJobs();
  toast('Refreshed', 'info');
}

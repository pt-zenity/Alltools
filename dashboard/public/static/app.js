/**
 * Web Crawler Toolkit 2026 - Frontend Application
 */

// ── State ─────────────────────────────────────
const state = {
  ws: null,
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
  refreshIntervals: {}
};

// ── Tool Definitions ──────────────────────────
const TOOL_INFO = {
  katana: {
    icon: '⚡', color: '#6366f1',
    desc: 'Next-generation crawling framework by ProjectDiscovery. Headless JS support, smart filtering, and structured output.',
    tags: ['Go', 'Crawling', 'JS Rendering', 'ProjectDiscovery'],
    cmd: 'katana -u <URL> -d 3 -c 50 -jc -o output.txt'
  },
  gau: {
    icon: '🌐', color: '#22c55e',
    desc: 'Get All URLs — fetches known URLs from Wayback Machine, OTX, URLScan, and CommonCrawl archives.',
    tags: ['Go', 'Passive Recon', 'Wayback', 'CommonCrawl'],
    cmd: 'echo "domain.com" | gau --threads 30 --providers wayback,commoncrawl'
  },
  waymore: {
    icon: '📡', color: '#f59e0b',
    desc: 'Advanced URL collection tool combining multiple web archive sources with smart filtering and deduplication.',
    tags: ['Python', 'URL Collection', 'Passive', 'Multi-source'],
    cmd: 'waymore -i domain.com -mode U -oU output.txt'
  },
  gospider: {
    icon: '🕷️', color: '#06b6d4',
    desc: 'Fast web spider with sitemap parsing, robots.txt discovery, and JS endpoint extraction capabilities.',
    tags: ['Go', 'Spidering', 'Robots.txt', 'Sitemap'],
    cmd: 'gospider -s <URL> -o output/ -c 50 -d 3 --js --sitemap'
  },
  xnLinkFinder: {
    icon: '🔗', color: '#a855f7',
    desc: 'Python-based link finder that discovers endpoints in HTML, JS, and other response bodies via regex patterns.',
    tags: ['Python', 'Link Extraction', 'JS Analysis', 'Regex'],
    cmd: 'xnLinkFinder -i <URL> -op output.txt -sp <URL> -d 3'
  },
  httpx: {
    icon: '🔍', color: '#ef4444',
    desc: 'Fast HTTP toolkit for probing URLs. Detects status codes, titles, technologies, and web server information.',
    tags: ['Go', 'HTTP Probing', 'Tech Detection', 'ProjectDiscovery'],
    cmd: 'httpx -l urls.txt -o alive.txt -title -sc -ct -server'
  },
  subfinder: {
    icon: '🌿', color: '#22c55e',
    desc: 'Passive subdomain discovery tool using 100+ data sources including DNS resolvers and certificate logs.',
    tags: ['Go', 'Subdomains', 'Passive', 'OSINT'],
    cmd: 'subfinder -d domain.com -o subdomains.txt'
  },
  nuclei: {
    icon: '☢️', color: '#f59e0b',
    desc: 'Fast and customizable vulnerability scanner based on YAML templates. 10000+ community templates.',
    tags: ['Go', 'Vulnerability', 'Templates', 'ProjectDiscovery'],
    cmd: 'nuclei -u <URL> -t cves/ -o results.txt'
  },
  dnsx: {
    icon: '🧮', color: '#06b6d4',
    desc: 'Fast and multi-purpose DNS toolkit for running various probes, DNS bruteforcing, and zone transfers.',
    tags: ['Go', 'DNS', 'Recon', 'ProjectDiscovery'],
    cmd: 'dnsx -d domain.com -a -aaaa -cname -mx -o dns.txt'
  },
  naabu: {
    icon: '🔌', color: '#6366f1',
    desc: 'Fast port scanner built around SYN/CONNECT probes with service discovery and rate limiting.',
    tags: ['Go', 'Port Scanner', 'Network', 'ProjectDiscovery'],
    cmd: 'naabu -host domain.com -p 80,443,8080 -o ports.txt'
  },
  waybackurls: {
    icon: '⏮️', color: '#a855f7',
    desc: 'Fetch all known URLs from the Wayback Machine for a given domain. Simple and fast.',
    tags: ['Go', 'Wayback', 'URLs', 'tomnomnom'],
    cmd: 'echo "domain.com" | waybackurls > urls.txt'
  },
  anew: {
    icon: '✨', color: '#22c55e',
    desc: 'Append new lines to file, skipping duplicates. Essential for pipeline-based URL collection workflows.',
    tags: ['Go', 'Dedup', 'Pipeline', 'tomnomnom'],
    cmd: 'cat new-urls.txt | anew all-urls.txt'
  },
  gf: {
    icon: '🎯', color: '#ef4444',
    desc: 'Grep with patterns — find XSS, SQLi, SSRF, LFI, and other vulnerability patterns in URL lists.',
    tags: ['Go', 'Pattern Match', 'Vuln Patterns', 'tomnomnom'],
    cmd: 'gf xss urls.txt | gf sqli | tee vuln-urls.txt'
  },
  uro: {
    icon: '🧹', color: '#06b6d4',
    desc: 'URL deduplication tool that intelligently removes duplicate and low-value URLs from collections.',
    tags: ['Python', 'Dedup', 'URL Filter', 'Optimization'],
    cmd: 'cat urls.txt | uro > deduped.txt'
  },
  unfurl: {
    icon: '🔓', color: '#f59e0b',
    desc: 'Pull out bits of URLs. Extract paths, domains, parameters, values, and more from URL lists.',
    tags: ['Go', 'URL Parsing', 'Extraction', 'tomnomnom'],
    cmd: 'cat urls.txt | unfurl domains'
  },
  node: {
    icon: '🟢', color: '#22c55e',
    desc: 'Node.js runtime for JavaScript execution. Powering the dashboard and custom JS-based scrapers.',
    tags: ['Runtime', 'JavaScript', 'V8', 'Dashboard'],
    cmd: 'node --version'
  },
  python3: {
    icon: '🐍', color: '#f59e0b',
    desc: 'Python 3 runtime for Python-based tools like waymore, xnLinkFinder, and uro.',
    tags: ['Runtime', 'Python', 'Scripting'],
    cmd: 'python3 --version'
  }
};

// ── Initialize ────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initClock();
  initNavigation();
  initSidebarToggle();
  initWebSocket();
  initScanForm();
  initTerminal();
  loadDashboard();

  // Auto refresh
  state.refreshIntervals.dashboard = setInterval(loadDashboard, 10000);
});

// ── Clock ─────────────────────────────────────
function initClock() {
  const update = () => {
    const now = new Date();
    document.getElementById('clock').textContent =
      now.toUTCString().replace(' GMT', ' UTC').split(',')[1].trim().substring(0, 17);
  };
  update();
  setInterval(update, 1000);
}

// ── Navigation ────────────────────────────────
function initNavigation() {
  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', e => {
      e.preventDefault();
      const page = item.dataset.page;
      navigateTo(page);
    });
  });
}

function navigateTo(page) {
  // Update nav items
  document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
  const navItem = document.querySelector(`.nav-item[data-page="${page}"]`);
  if (navItem) navItem.classList.add('active');

  // Switch pages
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const pageEl = document.getElementById(`page-${page}`);
  if (pageEl) pageEl.classList.add('active');

  // Update title
  const titles = {
    dashboard: 'Dashboard',
    scan: 'New Scan',
    jobs: 'Jobs',
    results: 'Results',
    tools: 'Tools',
    terminal: 'Terminal',
    docs: 'Documentation'
  };
  document.getElementById('page-title').textContent = titles[page] || page;
  state.currentPage = page;

  // Page-specific loading
  if (page === 'tools' && state.tools.length === 0) loadTools();
  if (page === 'results') loadOutputs();
  if (page === 'jobs') loadJobs();
  if (page === 'docs') loadDocs();
}

// ── Sidebar Toggle ────────────────────────────
function initSidebarToggle() {
  document.getElementById('sidebar-toggle').addEventListener('click', () => {
    document.getElementById('sidebar').classList.toggle('collapsed');
  });
}

// ── WebSocket ─────────────────────────────────
function initWebSocket() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}`;
  
  state.ws = new WebSocket(wsUrl);

  state.ws.onopen = () => {
    setWsStatus('connected');
    if (state.wsReconnectTimer) {
      clearTimeout(state.wsReconnectTimer);
      state.wsReconnectTimer = null;
    }
  };

  state.ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      handleWsMessage(data);
    } catch (e) {}
  };

  state.ws.onclose = () => {
    setWsStatus('disconnected');
    state.wsReconnectTimer = setTimeout(initWebSocket, 3000);
  };

  state.ws.onerror = () => {
    setWsStatus('disconnected');
  };
}

function setWsStatus(status) {
  const dot = document.getElementById('ws-dot');
  const text = document.getElementById('ws-text');
  dot.className = `ws-dot ${status}`;
  text.textContent = status === 'connected' ? 'Connected' : 'Disconnected';
}

function handleWsMessage(data) {
  switch (data.type) {
    case 'job-started':
      state.activeJobs.set(data.jobId, {
        id: data.jobId, type: data.scanType,
        target: data.options?.target || '-',
        status: 'running', startTime: data.timestamp
      });
      updateJobBadge();
      toast(`Scan started: ${data.target || 'job'}`, 'info');
      if (state.currentPage === 'jobs') loadJobs();
      break;

    case 'job-output':
      if (state.currentScanJobId === data.jobId) {
        appendTerminalLine(data.line, data.stream);
      }
      break;

    case 'job-complete':
      state.activeJobs.delete(data.jobId);
      updateJobBadge();
      toast(`Scan completed! Exit: ${data.exitCode}`, data.exitCode === 0 ? 'success' : 'warning');
      if (state.currentPage === 'jobs') loadJobs();
      if (state.currentScanJobId === data.jobId) {
        appendTerminalLine(`\n✓ Scan completed (exit: ${data.exitCode})`, 'success');
        document.getElementById('stop-btn').disabled = true;
      }
      loadDashboard();
      break;

    case 'job-stopped':
      state.activeJobs.delete(data.jobId);
      updateJobBadge();
      toast('Job stopped', 'warning');
      break;

    case 'job-error':
      toast(`Error: ${data.message}`, 'error');
      break;
  }
}

// ── Dashboard ─────────────────────────────────
async function loadDashboard() {
  try {
    const [systemData, toolsData, outputsData, historyData] = await Promise.all([
      fetch('/api/system').then(r => r.json()),
      fetch('/api/tools').then(r => r.json()),
      fetch('/api/outputs').then(r => r.json()),
      fetch('/api/jobs/history').then(r => r.json())
    ]);

    const available = toolsData.tools?.filter(t => t.available).length || 0;
    state.tools = toolsData.tools || [];

    setStatValue('stat-active-count', systemData.activeJobs || 0);
    setStatValue('stat-total-count', systemData.totalJobs || 0);
    setStatValue('stat-outputs-count', outputsData.length || 0);
    setStatValue('stat-tools-count', `${available}/${state.tools.length}`);

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
  if (!jobs || jobs.length === 0) {
    container.innerHTML = `<div class="empty-state"><i class="fas fa-inbox"></i><p>No jobs yet</p></div>`;
    return;
  }

  container.innerHTML = jobs.map(job => `
    <div class="job-item">
      <div class="job-status-indicator ${job.status}"></div>
      <div class="job-info">
        <div class="job-target">${job.options?.target || 'Unknown target'}</div>
        <div class="job-meta">${formatTime(job.startTime)} · ${job.type}</div>
      </div>
      <span class="job-type-badge">${job.type}</span>
    </div>
  `).join('');
}

function renderToolStatusGrid(tools) {
  const container = document.getElementById('tool-status-grid');
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
  } catch (e) {
    console.error('Tools load error:', e);
  }
}

function renderToolsDetail(tools) {
  const container = document.getElementById('tools-detail-grid');
  if (!container) return;

  container.innerHTML = tools.map(tool => {
    const info = TOOL_INFO[tool.name] || {};
    return `
      <div class="tool-detail-card">
        <div class="tool-detail-header">
          <div class="tool-detail-icon" style="background: ${info.color || '#6366f1'}22; color: ${info.color || '#6366f1'}">
            ${info.icon || '🔧'}
          </div>
          <div>
            <div class="tool-detail-name">${tool.name}</div>
          </div>
          <span class="tool-detail-status ${tool.available ? 'ok' : 'fail'}">
            ${tool.available ? '● Available' : '● Missing'}
          </span>
        </div>
        <div class="tool-detail-body">
          <p class="tool-detail-desc">${info.desc || 'Security/recon tool'}</p>
          <div class="tool-detail-ver">${tool.version || 'version unknown'}</div>
          ${info.cmd ? `<div class="tool-detail-ver"><strong>Example:</strong><br>${info.cmd}</div>` : ''}
          <div class="tool-detail-tags">
            ${(info.tags || []).map(t => `<span class="tool-tag">${t}</span>`).join('')}
          </div>
        </div>
      </div>
    `;
  }).join('');
}

// ── Scan Form ─────────────────────────────────
function initScanForm() {
  // Scan type selector
  document.querySelectorAll('.scan-type-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.scan-type-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      state.scanType = btn.dataset.type;
    });
  });

  // Range inputs
  const depthInput = document.getElementById('scan-depth');
  const threadsInput = document.getElementById('scan-threads');
  
  if (depthInput) {
    depthInput.addEventListener('input', () => {
      document.getElementById('scan-depth-val').textContent = depthInput.value;
    });
  }

  if (threadsInput) {
    threadsInput.addEventListener('input', () => {
      document.getElementById('scan-threads-val').textContent = threadsInput.value;
    });
  }

  // Custom command toggle
  const scanTypeSelect = document.getElementById('scan-type');
  if (scanTypeSelect) {
    scanTypeSelect.addEventListener('change', () => {
      const customGroup = document.getElementById('custom-cmd-group');
      if (customGroup) {
        customGroup.style.display = scanTypeSelect.value === 'custom' ? 'flex' : 'none';
      }
    });
  }

  // Enter key for quick target
  const quickTarget = document.getElementById('quick-target');
  if (quickTarget) {
    quickTarget.addEventListener('keypress', e => {
      if (e.key === 'Enter') quickScan();
    });
  }

  // Enter key for scan target
  const scanTarget = document.getElementById('scan-target');
  if (scanTarget) {
    scanTarget.addEventListener('keypress', e => {
      if (e.key === 'Enter') startScan();
    });
  }
}

function quickScan() {
  const target = document.getElementById('quick-target').value.trim();
  if (!target) {
    toast('Please enter a target URL', 'warning');
    return;
  }
  navigateTo('scan');
  document.getElementById('scan-target').value = target;
  document.getElementById('scan-type').value = state.scanType;
  setTimeout(() => startScan(), 300);
}

async function startScan() {
  const target = document.getElementById('scan-target')?.value?.trim();
  const type = document.getElementById('scan-type')?.value || 'full-scan';
  const depth = document.getElementById('scan-depth')?.value || '3';
  const threads = document.getElementById('scan-threads')?.value || '50';
  const command = document.getElementById('scan-custom-cmd')?.value?.trim();

  if (!target && type !== 'custom') {
    toast('Please enter a target URL or domain', 'warning');
    return;
  }

  try {
    const response = await fetch('/api/scan/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, target, depth, threads, command })
    });

    const data = await response.json();
    if (data.jobId) {
      state.currentScanJobId = data.jobId;
      
      // Show output panel
      const outputPanel = document.getElementById('scan-output-panel');
      if (outputPanel) {
        outputPanel.style.display = 'block';
        document.getElementById('live-job-id').textContent = data.jobId.substring(0, 8);
        document.getElementById('stop-btn').disabled = false;
      }

      // Clear terminal
      const terminal = document.getElementById('output-terminal');
      if (terminal) {
        terminal.innerHTML = `
          <div class="terminal-line">
            <span class="terminal-prompt">$</span>
            <span class="terminal-text info">Starting ${type} scan on ${target}...</span>
          </div>
        `;
      }

      toast(`Scan started! Job: ${data.jobId.substring(0, 8)}`, 'success');
      updateJobBadge();
      
      // Scroll to output
      outputPanel?.scrollIntoView({ behavior: 'smooth' });
    }
  } catch (e) {
    toast('Failed to start scan: ' + e.message, 'error');
  }
}

function resetScanForm() {
  document.getElementById('scan-target').value = '';
  document.getElementById('scan-type').value = 'full-scan';
  document.getElementById('scan-depth').value = '3';
  document.getElementById('scan-threads').value = '50';
  document.getElementById('scan-depth-val').textContent = '3';
  document.getElementById('scan-threads-val').textContent = '50';
  const outputPanel = document.getElementById('scan-output-panel');
  if (outputPanel) outputPanel.style.display = 'none';
}

async function stopCurrentScan() {
  if (!state.currentScanJobId) return;
  try {
    await fetch(`/api/scan/stop/${state.currentScanJobId}`, { method: 'POST' });
    toast('Scan stopped', 'warning');
    state.currentScanJobId = null;
  } catch (e) {
    toast('Failed to stop scan', 'error');
  }
}

function clearOutput() {
  const terminal = document.getElementById('output-terminal');
  if (terminal) terminal.innerHTML = '';
}

function appendTerminalLine(text, stream = 'stdout') {
  const terminal = document.getElementById('output-terminal');
  if (!terminal) return;

  const line = document.createElement('div');
  line.className = 'terminal-line';
  
  const textClass = {
    'stdout': 'stdout',
    'stderr': 'stderr',
    'success': 'success',
    'info': 'info',
    'warning': 'warning'
  }[stream] || 'stdout';

  line.innerHTML = `
    <span class="terminal-text ${textClass}">${escapeHtml(text)}</span>
  `;
  
  terminal.appendChild(line);
  terminal.scrollTop = terminal.scrollHeight;
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
  } catch (e) {}
}

function renderActiveJobs(jobs) {
  const container = document.getElementById('jobs-active-list');
  if (!container) return;

  if (!jobs || jobs.length === 0) {
    container.innerHTML = `<div class="empty-state"><i class="fas fa-pause-circle"></i><p>No active jobs</p></div>`;
    return;
  }

  container.innerHTML = jobs.map(job => `
    <div class="job-item">
      <div class="job-status-indicator running"></div>
      <div class="job-info">
        <div class="job-target">${job.options?.target || 'Custom job'}</div>
        <div class="job-meta">Started: ${formatTime(job.startTime)} · ${job.outputLines} lines output</div>
      </div>
      <span class="job-type-badge">${job.type}</span>
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
        <div class="job-target">${job.options?.target || 'Custom job'}</div>
        <div class="job-meta">${formatTime(job.startTime)} · Exit: ${job.exitCode ?? '-'}</div>
      </div>
      <span class="job-type-badge">${job.type}</span>
    </div>
  `).join('');
}

async function stopJob(jobId) {
  try {
    await fetch(`/api/scan/stop/${jobId}`, { method: 'POST' });
    toast('Job stopped', 'warning');
    loadJobs();
  } catch (e) {
    toast('Failed to stop job', 'error');
  }
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
  if (e.target.classList.contains('tab')) {
    const container = e.target.closest('.panel');
    if (!container) return;
    
    container.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    e.target.classList.add('active');
    
    const tab = e.target.dataset.tab;
    const activeContainer = document.getElementById('jobs-active-list');
    const historyContainer = document.getElementById('jobs-history-list');
    
    if (activeContainer && historyContainer) {
      activeContainer.style.display = tab === 'active' ? 'flex' : 'none';
      historyContainer.style.display = tab === 'history' ? 'flex' : 'none';
    }
  }
});

// ── Results / Outputs ─────────────────────────
async function loadOutputs() {
  try {
    const outputs = await fetch('/api/outputs').then(r => r.json());
    state.outputs = outputs;
    renderFileTree(outputs);
  } catch (e) {}
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
      <div class="file-tree-dir-name" onclick="toggleDir('${dir.name}')">
        <i class="fas fa-folder"></i>
        <span title="${dir.name}">${dir.name.length > 30 ? dir.name.substring(0, 30) + '…' : dir.name}</span>
        <span class="file-size">${dir.fileCount} files</span>
      </div>
      <div class="file-tree-files" id="files-${dir.name}">
        <div class="loading-spinner"><i class="fas fa-spinner fa-spin"></i></div>
      </div>
    </div>
  `).join('');
}

async function toggleDir(dirName) {
  const dirEl = document.getElementById(`dir-${dirName}`);
  const filesEl = document.getElementById(`files-${dirName}`);
  
  if (dirEl.classList.contains('open')) {
    dirEl.classList.remove('open');
    return;
  }

  dirEl.classList.add('open');
  
  // Load files if not loaded
  if (filesEl.querySelector('.loading-spinner')) {
    try {
      const files = await fetch(`/api/outputs/${encodeURIComponent(dirName)}/files`).then(r => r.json());
      filesEl.innerHTML = files.map(file => `
        <div class="file-tree-file" onclick="viewFile('${escapeHtml(file.path)}', '${escapeHtml(file.name)}')">
          <i class="${getFileIcon(file.name)}"></i>
          <span>${file.name}</span>
          <span class="file-size">${formatSize(file.size)}</span>
        </div>
      `).join('') || '<div class="file-tree-file"><span>No files</span></div>';
    } catch (e) {
      filesEl.innerHTML = '<div class="file-tree-file"><span>Error loading</span></div>';
    }
  }
}

async function viewFile(filePath, fileName) {
  state.selectedFile = filePath;

  // Update active state
  document.querySelectorAll('.file-tree-file').forEach(f => f.classList.remove('active'));
  event?.target?.closest('.file-tree-file')?.classList.add('active');

  const viewer = document.getElementById('file-viewer');
  if (!viewer) return;

  viewer.innerHTML = `<div class="loading-spinner"><i class="fas fa-spinner fa-spin"></i> Loading...</div>`;

  try {
    const data = await fetch(`/api/file?path=${encodeURIComponent(filePath)}&lines=1000`).then(r => r.json());
    
    viewer.innerHTML = `<pre>${escapeHtml(data.content)}${data.truncated ? '\n\n... (truncated, showing first 1000 lines)' : ''}</pre>`;

    // Show download button
    const actions = document.getElementById('file-viewer-actions');
    const dlBtn = document.getElementById('download-file-btn');
    if (actions && dlBtn) {
      actions.style.display = 'flex';
      dlBtn.onclick = () => window.open(`/api/download?path=${encodeURIComponent(filePath)}`);
    }

    document.querySelector('#page-results .panel-header h3').textContent = `File: ${fileName}`;
  } catch (e) {
    viewer.innerHTML = `<div class="file-viewer-placeholder"><i class="fas fa-exclamation-triangle"></i><p>Error loading file</p></div>`;
  }
}

// ── Terminal ──────────────────────────────────
function initTerminal() {
  const input = document.getElementById('terminal-input');
  if (!input) return;

  let histIdx = -1;
  
  input.addEventListener('keypress', e => {
    if (e.key === 'Enter') execTerminalCmd();
  });

  input.addEventListener('keydown', e => {
    if (e.key === 'ArrowUp' && state.terminalHistory.length > 0) {
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

    if (data.stdout) {
      data.stdout.split('\n').forEach(line => {
        if (line.trim()) appendToTerminalHistory(line, 'stdout');
      });
    }
    if (data.stderr) {
      data.stderr.split('\n').forEach(line => {
        if (line.trim()) appendToTerminalHistory(line, 'stderr');
      });
    }
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
  
  const textClass = {
    'prompt': 'info',
    'stdout': 'stdout',
    'stderr': 'stderr',
    'success': 'success',
    'warning': 'warning'
  }[type] || 'stdout';

  line.innerHTML = `<span class="terminal-text ${textClass}">${escapeHtml(text)}</span>`;
  history.appendChild(line);
  history.scrollTop = history.scrollHeight;
}

// ── Docs Page ─────────────────────────────────
function loadDocs() {
  const container = document.getElementById('docs-content');
  if (!container) return;

  container.innerHTML = `
    <div class="docs-grid">
      <div class="docs-card">
        <h3><i class="fas fa-spider"></i> katana - Next-Gen Crawler</h3>
        <p>Advanced crawling framework with headless browser support, smart filtering, and structured output formats.</p>
        <pre>katana -u https://target.com \\
  -d 3 -c 50 -jc \\
  -fx -xhr -aff \\
  -rl 150 \\
  -o output.txt -jsonl results.jsonl</pre>
        <ul>
          <li><code>-d</code> - Crawl depth (default: 3)</li>
          <li><code>-jc</code> - Enable JS crawling</li>
          <li><code>-fx</code> - Extract from responses</li>
          <li><code>-xhr</code> - Capture XHR requests</li>
          <li><code>-aff</code> - Auto form fill</li>
        </ul>
      </div>

      <div class="docs-card">
        <h3><i class="fas fa-globe"></i> gau - Get All URLs</h3>
        <p>Passive URL collection from Wayback Machine, CommonCrawl, OTX, and URLScan archives.</p>
        <pre>echo "target.com" | gau \\
  --threads 30 \\
  --providers wayback,commoncrawl,otx,urlscan \\
  --blacklist png,jpg,gif,css,woff \\
  --o output.txt</pre>
        <ul>
          <li><code>--providers</code> - Choose data sources</li>
          <li><code>--blacklist</code> - Skip file extensions</li>
          <li><code>--threads</code> - Concurrent threads</li>
          <li><code>--subs</code> - Include subdomains</li>
        </ul>
      </div>

      <div class="docs-card">
        <h3><i class="fas fa-satellite"></i> waymore - Advanced URL Collector</h3>
        <p>Comprehensive URL collection combining multiple web archive sources with intelligent filtering.</p>
        <pre>waymore -i target.com \\
  -mode U \\
  -oU urls.txt \\
  -p 50 \\
  -lf domain-filter.txt</pre>
        <ul>
          <li><code>-mode U</code> - URL collection mode</li>
          <li><code>-mode R</code> - Response download mode</li>
          <li><code>-oU</code> - Output URL file</li>
          <li><code>-lf</code> - URL filter list</li>
        </ul>
      </div>

      <div class="docs-card">
        <h3><i class="fas fa-spider"></i> gospider - Fast Spider</h3>
        <p>Fast web spider with parallel crawling, sitemap parsing, robots.txt discovery, and JS endpoint extraction.</p>
        <pre>gospider -s https://target.com \\
  -o output/ \\
  -c 50 -d 3 \\
  --js --sitemap --robots \\
  --other-source --include-subs</pre>
        <ul>
          <li><code>-c</code> - Concurrent requests</li>
          <li><code>-d</code> - Crawl depth</li>
          <li><code>--js</code> - Parse JS files</li>
          <li><code>--sitemap</code> - Parse sitemaps</li>
        </ul>
      </div>

      <div class="docs-card">
        <h3><i class="fas fa-link"></i> xnLinkFinder - Link Extractor</h3>
        <p>Python tool to extract URLs and endpoints from HTML, JS files, and other response bodies using regex.</p>
        <pre>xnLinkFinder -i https://target.com \\
  -op output.txt \\
  -sp https://target.com \\
  -sf target.com \\
  -d 3 -p 20</pre>
        <ul>
          <li><code>-i</code> - Input URL or file</li>
          <li><code>-op</code> - Output pages file</li>
          <li><code>-sp</code> - Scope pattern</li>
          <li><code>-d</code> - Depth limit</li>
        </ul>
      </div>

      <div class="docs-card">
        <h3><i class="fas fa-search"></i> httpx - HTTP Probe</h3>
        <p>Fast HTTP toolkit for bulk URL probing with status codes, title extraction, and technology detection.</p>
        <pre>httpx -l urls.txt \\
  -o alive.txt \\
  -json results.json \\
  -title -sc -ct -server \\
  -tech-detect \\
  -threads 50 -timeout 10</pre>
        <ul>
          <li><code>-sc</code> - Show status codes</li>
          <li><code>-title</code> - Extract page titles</li>
          <li><code>-tech-detect</code> - Detect technologies</li>
          <li><code>-follow-redirects</code> - Follow redirects</li>
        </ul>
      </div>

      <div class="docs-card">
        <h3><i class="fas fa-magic"></i> Full Recon Pipeline</h3>
        <p>Complete one-liner reconnaissance pipeline combining all tools:</p>
        <pre>TARGET="https://example.com"
DOMAIN="example.com"

# Collect all URLs
katana -u $TARGET -d 3 -jc | anew urls.txt
echo $DOMAIN | gau >> urls.txt
echo $DOMAIN | waymore -mode U | anew urls.txt
gospider -s $TARGET --js | anew urls.txt

# Deduplicate
cat urls.txt | uro | sort -u > dedup.txt

# Probe alive
httpx -l dedup.txt -o alive.txt -sc -title

# Find vulnerabilities
gf xss dedup.txt > xss.txt
gf sqli dedup.txt > sqli.txt</pre>
      </div>

      <div class="docs-card">
        <h3><i class="fab fa-docker"></i> Docker Usage</h3>
        <p>Running the toolkit via Docker:</p>
        <pre># Start dashboard
docker run -p 3000:3000 \\
  -v $(pwd)/output:/workspace/output \\
  crawler-toolkit:2026 dashboard

# Run full scan
docker run -v $(pwd)/output:/workspace/output \\
  crawler-toolkit:2026 scan https://example.com

# Interactive shell
docker run -it \\
  -v $(pwd)/output:/workspace/output \\
  crawler-toolkit:2026 bash

# Docker Compose
docker compose up -d</pre>
      </div>
    </div>
  `;
}

// ── Utility Functions ─────────────────────────
function formatTime(iso) {
  if (!iso) return 'N/A';
  const d = new Date(iso);
  return d.toLocaleTimeString();
}

function formatSize(bytes) {
  if (bytes === 0) return '0B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + sizes[i];
}

function escapeHtml(text) {
  const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' };
  return String(text || '').replace(/[&<>"']/g, m => map[m]);
}

function getFileIcon(name) {
  if (name.endsWith('.txt')) return 'fas fa-file-alt';
  if (name.endsWith('.json') || name.endsWith('.jsonl')) return 'fas fa-file-code';
  if (name.endsWith('.log')) return 'fas fa-file-medical';
  if (name.endsWith('.csv')) return 'fas fa-file-csv';
  if (name.endsWith('.html')) return 'fab fa-html5';
  if (name.endsWith('.js')) return 'fab fa-js';
  return 'fas fa-file';
}

function toast(message, type = 'info') {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  const icons = { success: '✓', error: '✕', info: 'ℹ', warning: '⚠' };
  
  toast.className = `toast ${type}`;
  toast.innerHTML = `<span>${icons[type] || 'ℹ'}</span>${escapeHtml(message)}`;
  container.appendChild(toast);
  
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateX(100%)';
    toast.style.transition = 'all 0.3s';
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}

function refreshPage() {
  loadDashboard();
  if (state.currentPage === 'tools') loadTools();
  if (state.currentPage === 'results') loadOutputs();
  if (state.currentPage === 'jobs') loadJobs();
  toast('Refreshed', 'info');
}

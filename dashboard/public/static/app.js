/**
 * Web Crawler Toolkit 2026 - Frontend  v3
 * STREAMING FIX:
 *  1. Subscribe happens AFTER server confirms job, BEFORE any terminal clear
 *  2. appendOutputLine never silently drops lines (removed over-aggressive guards)
 *  3. job-started no longer clears terminal (terminal is prepared in startScan only)
 *  4. Replay lines rendered immediately, then live lines continue
 *  5. WS reconnect re-subscribes to currentScanJobId from last known line
 */

// ── State ─────────────────────────────────────────────────────
const state = {
  ws:                 null,
  wsReady:            false,
  wsReconnectTimer:   null,
  currentPage:        'dashboard',
  activeJobs:         new Map(),
  jobHistory:         [],
  tools:              [],
  outputs:            [],
  currentScanJobId:   null,
  outputLineCount:    0,
  outputAutoScroll:   true,
  maxOutputLines:     5000,
  refreshIntervals:   {},
};

// ── Tool info ─────────────────────────────────────────────────
const TOOL_INFO = {
  katana:       { icon:'⚡', color:'#6366f1', desc:'Next-gen crawling framework. Headless JS, smart filtering, structured output.',         tags:['Go','Crawling','JS Rendering'],       cmd:'katana -u <URL> -d 3 -c 50 -jc -o output.txt' },
  gau:          { icon:'🌐', color:'#22c55e', desc:'Get All URLs from Wayback, OTX, URLScan, CommonCrawl archives.',                        tags:['Go','Passive Recon','Wayback'],        cmd:'echo "domain.com" | gau --threads 30' },
  waymore:      { icon:'📡', color:'#f59e0b', desc:'Advanced URL collection combining multiple web archive sources.',                        tags:['Python','URL Collection','Passive'],   cmd:'waymore -i domain.com -mode U -oU output.txt' },
  gospider:     { icon:'🕷️', color:'#06b6d4', desc:'Fast web spider with sitemap, robots.txt, and JS endpoint extraction.',                 tags:['Go','Spidering','Robots.txt'],         cmd:'gospider -s <URL> -o output/ -c 50 -d 3 --js' },
  xnLinkFinder: { icon:'🔗', color:'#a855f7', desc:'Python link finder — discovers endpoints in HTML/JS via regex patterns.',               tags:['Python','Link Extraction','Regex'],    cmd:'xnLinkFinder -i <URL> -op output.txt -d 3' },
  httpx:        { icon:'🔍', color:'#ef4444', desc:'Fast HTTP toolkit for probing — status codes, titles, technologies.',                   tags:['Go','HTTP Probing','Tech Detection'],  cmd:'httpx -l urls.txt -o alive.txt -title -sc' },
  subfinder:    { icon:'🌿', color:'#22c55e', desc:'Passive subdomain discovery using 100+ sources — DNS, certs.',                          tags:['Go','Subdomains','Passive'],           cmd:'subfinder -d domain.com -o subs.txt' },
  nuclei:       { icon:'☢️', color:'#f59e0b', desc:'Fast YAML-template vulnerability scanner. 10 000+ community templates.',               tags:['Go','Vulnerability','Templates'],      cmd:'nuclei -u <URL> -t cves/ -o results.txt' },
  dnsx:         { icon:'🧮', color:'#06b6d4', desc:'Multi-purpose DNS toolkit — probes, bruteforce, zone transfers.',                       tags:['Go','DNS','Recon'],                    cmd:'dnsx -d domain.com -a -aaaa -cname -o dns.txt' },
  naabu:        { icon:'🔌', color:'#6366f1', desc:'Fast port scanner using SYN/CONNECT probes with service discovery.',                   tags:['Go','Port Scanner','Network'],         cmd:'naabu -host domain.com -p 80,443,8080' },
  waybackurls:  { icon:'⏮️', color:'#a855f7', desc:'Fetch all known URLs from Wayback Machine for a given domain.',                        tags:['Go','Wayback','URLs'],                 cmd:'echo "domain.com" | waybackurls > urls.txt' },
  anew:         { icon:'✨', color:'#22c55e', desc:'Append new lines, skip duplicates — essential for pipeline URL collection.',            tags:['Go','Dedup','Pipeline'],               cmd:'cat new.txt | anew all.txt' },
  gf:           { icon:'🎯', color:'#ef4444', desc:'Grep with patterns — find XSS, SQLi, SSRF, LFI patterns in URL lists.',                tags:['Go','Pattern Match','Vuln Patterns'],  cmd:'gf xss urls.txt | gf sqli' },
  uro:          { icon:'🧹', color:'#06b6d4', desc:'Intelligent URL deduplication and filtering.',                                          tags:['Python','Dedup','URL Filter'],         cmd:'cat urls.txt | uro > deduped.txt' },
  unfurl:       { icon:'🔓', color:'#f59e0b', desc:'Pull bits of URLs — extract paths, domains, params, values.',                          tags:['Go','URL Parsing','Extraction'],       cmd:'cat urls.txt | unfurl domains' },
  node:         { icon:'🟢', color:'#22c55e', desc:'Node.js runtime — powering the dashboard.',                                             tags:['Runtime','JavaScript'],               cmd:'node --version' },
  python3:      { icon:'🐍', color:'#f59e0b', desc:'Python 3 — runtime for waymore, xnLinkFinder, uro.',                                  tags:['Runtime','Python'],                   cmd:'python3 --version' },
};

// ── Init ──────────────────────────────────────────────────────
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

// ── Clock ──────────────────────────────────────────────────────
function initClock() {
  const tick = () => {
    const el = document.getElementById('clock');
    if (el) el.textContent = new Date().toUTCString().split(' ').slice(1,5).join(' ');
  };
  tick();
  setInterval(tick, 1000);
}

// ── Navigation ─────────────────────────────────────────────────
function initNavigation() {
  document.querySelectorAll('.nav-item').forEach(item => {
    item.addEventListener('click', e => { e.preventDefault(); navigateTo(item.dataset.page); });
  });
}

function navigateTo(page) {
  document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
  const nav = document.querySelector(`.nav-item[data-page="${page}"]`);
  if (nav) nav.classList.add('active');

  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const pg = document.getElementById(`page-${page}`);
  if (pg) pg.classList.add('active');

  const titles = { dashboard:'Dashboard', scan:'New Scan', jobs:'Jobs', results:'Results', tools:'Tools', terminal:'Terminal', docs:'Documentation' };
  const ttl = document.getElementById('page-title');
  if (ttl) ttl.textContent = titles[page] || page;
  state.currentPage = page;

  if (page === 'tools'   && state.tools.length === 0) loadTools();
  if (page === 'results') loadOutputs();
  if (page === 'jobs')    loadJobs();
  if (page === 'docs')    loadDocs();
}

function initSidebarToggle() {
  const btn = document.getElementById('sidebar-toggle');
  if (btn) btn.addEventListener('click', () => document.getElementById('sidebar')?.classList.toggle('collapsed'));
}

// ── WebSocket ──────────────────────────────────────────────────
function initWebSocket() {
  if (state.ws && state.ws.readyState === WebSocket.OPEN) return;
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  state.ws = new WebSocket(`${proto}//${window.location.host}`);
  state.wsReady = false;

  state.ws.onopen = () => {
    state.wsReady = true;
    setWsStatus('connected');
    clearTimeout(state.wsReconnectTimer);
    state.wsReconnectTimer = null;
    // Re-subscribe to active job from last known line on reconnect
    if (state.currentScanJobId) {
      wsSend({ type: 'subscribe', jobId: state.currentScanJobId, from: state.outputLineCount });
    }
  };

  state.ws.onmessage = ev => {
    try { handleWsMessage(JSON.parse(ev.data)); } catch (e) { console.error('[WS] parse error', e); }
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

function subscribeToJob(jobId, from = 0) {
  wsSend({ type: 'subscribe', jobId, from });
}

function setWsStatus(s) {
  const dot  = document.getElementById('ws-dot');
  const txt  = document.getElementById('ws-text');
  if (dot) dot.className  = `ws-dot ${s}`;
  if (txt) txt.textContent = s === 'connected' ? 'Connected' : 'Disconnected';
}

// ── WebSocket message handler ──────────────────────────────────
function handleWsMessage(msg) {
  switch (msg.type) {

    case 'connected':
      // server acknowledged
      break;

    case 'job-started':
      state.activeJobs.set(msg.jobId, {
        id: msg.jobId, type: msg.scanType, target: msg.target,
        status: 'running', startTime: msg.timestamp, lineCount: 0
      });
      updateJobBadge();
      // NOTE: do NOT clear terminal here — startScan() already prepared it
      // Just update the header labels and mark running
      if (state.currentScanJobId === msg.jobId) {
        setScanRunning(true);
        const lbl = document.getElementById('live-scan-label');
        if (lbl) lbl.textContent = `${msg.scanType} → ${msg.target || ''}`;
        const jid = document.getElementById('live-job-id');
        if (jid) jid.textContent = msg.jobId.substring(0, 8);
      }
      toast(`Scan started: ${msg.target || msg.jobId.substring(0,8)}`, 'info');
      if (state.currentPage === 'jobs') loadJobs();
      break;

    case 'job-output': {
      // Both replay (msg.replay=true) and live lines go through the same path
      if (state.currentScanJobId === msg.jobId) {
        appendOutputLine(msg.line, msg.stream, msg.replay === true);
        if (!msg.replay) {
          state.outputLineCount = msg.lineNum || state.outputLineCount + 1;
          updateOutputStats(state.outputLineCount);
        }
      }
      // Update live counter in jobs page
      const ctr = document.getElementById(`job-linecount-${msg.jobId}`);
      if (ctr && !msg.replay) ctr.textContent = `${msg.lineNum} lines`;
      break;
    }

    case 'job-complete':
      state.activeJobs.delete(msg.jobId);
      updateJobBadge();
      if (state.currentScanJobId === msg.jobId) finalizeOutputPanel(msg);
      toast(`Scan done · ${msg.lineCount} lines · exit ${msg.exitCode}`, msg.exitCode === 0 ? 'success' : 'warning');
      if (state.currentPage === 'jobs') loadJobs();
      loadDashboard();
      break;

    case 'job-stopped':
      state.activeJobs.delete(msg.jobId);
      updateJobBadge();
      if (state.currentScanJobId === msg.jobId) {
        appendOutputLine('⚠ Scan stopped by user.', 'warning');
        setScanRunning(false);
      }
      toast('Job stopped', 'warning');
      if (state.currentPage === 'jobs') loadJobs();
      break;

    case 'job-error':
      if (state.currentScanJobId === msg.jobId) {
        appendOutputLine(`✕ Error: ${msg.message}`, 'stderr');
        setScanRunning(false);
      }
      toast(`Error: ${msg.message}`, 'error');
      break;
  }
}

// ── Output panel helpers ────────────────────────────────────────

function initOutputControls() {
  const terminal = document.getElementById('output-terminal');
  if (terminal) {
    terminal.addEventListener('scroll', () => {
      const atBottom = terminal.scrollTop + terminal.clientHeight >= terminal.scrollHeight - 60;
      state.outputAutoScroll = atBottom;
      const btn = document.getElementById('autoscroll-btn');
      if (btn) btn.classList.toggle('active', atBottom);
    });
  }
}

function setScanRunning(running) {
  const stop = document.getElementById('stop-btn');
  const stat = document.getElementById('live-scan-status');
  if (stop) stop.disabled = !running;
  if (stat) {
    stat.textContent = running ? '● RUNNING' : '■ DONE';
    stat.className   = `live-status ${running ? 'running' : 'done'}`;
  }
}

function updateOutputStats(n) {
  state.outputLineCount = n;
  const el = document.getElementById('output-line-count');
  if (el) el.textContent = `${n} lines`;
}

function finalizeOutputPanel(data) {
  setScanRunning(false);
  const dur = document.getElementById('live-duration');
  if (dur && data.duration) {
    const s = Math.round(data.duration / 1000);
    dur.textContent = s >= 60 ? `${Math.floor(s/60)}m ${s%60}s` : `${s}s`;
  }
  const summary = `━━━ SCAN COMPLETE ━━━  exit=${data.exitCode}  lines=${data.lineCount}  ` +
                  (data.duration ? Math.round(data.duration/1000)+'s' : '');
  appendOutputLine('', 'stdout');
  appendOutputLine(summary, 'success');
  if (data.outputFiles && data.outputFiles.length > 0) {
    appendOutputLine(`📁 ${data.outputFiles.length} output file(s) written.`, 'info');
  }
}

/**
 * THE KEY FUNCTION — append one line to #output-terminal.
 *
 * Rules:
 *  - NEVER return early just because the line is empty (empty lines are valid separators)
 *  - Strip ANSI before rendering
 *  - silent=true → don't auto-scroll (used during batch replay)
 *  - After replay batch completes, caller is responsible for one final scroll
 */
function appendOutputLine(text, stream = 'stdout', silent = false) {
  const terminal = document.getElementById('output-terminal');
  if (!terminal) return;

  // Prune old DOM nodes
  while (terminal.children.length >= state.maxOutputLines) {
    terminal.removeChild(terminal.firstChild);
  }

  const clean = stripAnsi(String(text || ''));

  const div = document.createElement('div');
  div.className = `terminal-line line-${stream}`;

  const prefixMap = {
    stderr:  '<span class="lp lp-err">ERR</span>',
    info:    '<span class="lp lp-inf">INF</span>',
    success: '<span class="lp lp-ok"> OK</span>',
    warning: '<span class="lp lp-wrn">WRN</span>',
  };
  const prefix = prefixMap[stream] || '';

  const escaped = stream === 'stdout'
    ? highlightUrls(escapeHtml(clean))
    : escapeHtml(clean);

  div.innerHTML = `${prefix}<span class="ttext">${escaped}</span>`;
  terminal.appendChild(div);

  if (!silent && state.outputAutoScroll) {
    terminal.scrollTop = terminal.scrollHeight;
  }
}

function toggleAutoScroll() {
  state.outputAutoScroll = !state.outputAutoScroll;
  const btn = document.getElementById('autoscroll-btn');
  if (btn) btn.classList.toggle('active', state.outputAutoScroll);
  if (state.outputAutoScroll) scrollToBottom();
}

function scrollToBottom() {
  const t = document.getElementById('output-terminal');
  if (t) { t.scrollTop = t.scrollHeight; state.outputAutoScroll = true; }
}

function clearOutput() {
  const t = document.getElementById('output-terminal');
  if (t) { t.innerHTML = ''; state.outputLineCount = 0; updateOutputStats(0); }
}

function stopCurrentScan() {
  if (!state.currentScanJobId) return;
  fetch(`/api/scan/stop/${state.currentScanJobId}`, { method: 'POST' })
    .then(() => toast('Stop signal sent', 'warning'))
    .catch(e => toast('Stop failed: ' + e.message, 'error'));
}

// ── Scan form ──────────────────────────────────────────────────
function initScanForm() {
  document.querySelectorAll('.scan-type-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.scan-type-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    });
  });

  const depth   = document.getElementById('scan-depth');
  const threads = document.getElementById('scan-threads');
  if (depth)   depth.addEventListener('input',   () => { const v = document.getElementById('scan-depth-val');   if (v) v.textContent = depth.value; });
  if (threads) threads.addEventListener('input', () => { const v = document.getElementById('scan-threads-val'); if (v) v.textContent = threads.value; });

  const typeSelect = document.getElementById('scan-type');
  if (typeSelect) typeSelect.addEventListener('change', () => {
    const cg = document.getElementById('custom-cmd-group');
    if (cg) cg.style.display = typeSelect.value === 'custom' ? 'flex' : 'none';
  });

  const qt = document.getElementById('quick-target');
  if (qt) qt.addEventListener('keypress', e => { if (e.key === 'Enter') quickScan(); });

  const st = document.getElementById('scan-target');
  if (st) st.addEventListener('keypress', e => { if (e.key === 'Enter') startScan(); });
}

function quickScan() {
  const target = document.getElementById('quick-target')?.value?.trim();
  if (!target) { toast('Enter a target URL', 'warning'); return; }
  navigateTo('scan');
  const f = document.getElementById('scan-target');
  if (f) f.value = target;
  setTimeout(startScan, 200);
}

async function startScan() {
  const target  = document.getElementById('scan-target')?.value?.trim();
  const type    = document.getElementById('scan-type')?.value || 'full-scan';
  const depth   = document.getElementById('scan-depth')?.value || '3';
  const threads = document.getElementById('scan-threads')?.value || '50';
  const command = document.getElementById('scan-custom-cmd')?.value?.trim();

  if (!target && type !== 'custom') {
    toast('Enter a target URL or domain', 'warning');
    return;
  }

  // ── Prepare terminal BEFORE calling the API ─────────────────
  // This way the terminal is ready and we subscribe immediately
  const terminal = document.getElementById('output-terminal');
  if (terminal) {
    terminal.innerHTML   = '';
    state.outputLineCount = 0;
    state.outputAutoScroll = true;
  }
  updateOutputStats(0);

  // Show panel and scroll to it
  const panel = document.getElementById('scan-output-panel');
  if (panel) {
    panel.style.display = 'flex';
    panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  // Set IDLE status while waiting for API response
  const stat = document.getElementById('live-scan-status');
  if (stat) { stat.textContent = '◌ STARTING…'; stat.className = 'live-status starting'; }
  const lbl = document.getElementById('live-scan-label');
  if (lbl) lbl.textContent = `${type} → ${target || command || ''}`;

  const stopBtn = document.getElementById('stop-btn');
  if (stopBtn) stopBtn.disabled = true;

  appendOutputLine(`► Launching ${type} on ${target || command}…`, 'info');

  try {
    const resp = await fetch('/api/scan/start', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ type, target, depth, threads, command })
    });
    const data = await resp.json();

    if (data.error) {
      toast('Error: ' + data.error, 'error');
      setScanRunning(false);
      return;
    }

    if (data.jobId) {
      state.currentScanJobId = data.jobId;

      const jid = document.getElementById('live-job-id');
      if (jid) jid.textContent = data.jobId.substring(0, 8);

      // Subscribe immediately — server will replay any lines already buffered
      // and then continue streaming live
      subscribeToJob(data.jobId, 0);

      // Mark running (job-started WS event may arrive slightly later)
      setScanRunning(true);
      updateJobBadge();
      toast(`Job ${data.jobId.substring(0,8)} started`, 'success');
    }
  } catch (e) {
    toast('Failed to start scan: ' + e.message, 'error');
    setScanRunning(false);
  }
}

function resetScanForm() {
  const f = document.getElementById('scan-target');
  if (f) f.value = '';
  clearOutput();
  setScanRunning(false);
  const stat = document.getElementById('live-scan-status');
  if (stat) { stat.textContent = '■ IDLE'; stat.className = 'live-status done'; }
  const lbl = document.getElementById('live-scan-label');
  if (lbl) lbl.textContent = '';
}

function updateJobBadge() {
  const badge = document.getElementById('active-job-badge');
  if (badge) badge.textContent = state.activeJobs.size;
}

// ── Dashboard ──────────────────────────────────────────────────
async function loadDashboard() {
  try {
    const [sys, tools, outputs, history] = await Promise.all([
      fetch('/api/system').then(r => r.json()),
      fetch('/api/tools').then(r => r.json()),
      fetch('/api/outputs').then(r => r.json()),
      fetch('/api/jobs/history').then(r => r.json()),
    ]);
    state.tools      = tools.tools || [];
    state.jobHistory = history;
    const avail = state.tools.filter(t => t.available).length;
    setVal('stat-active-count',  sys.activeJobs   || 0);
    setVal('stat-total-count',   sys.totalJobs    || 0);
    setVal('stat-outputs-count', outputs.length   || 0);
    setVal('stat-tools-count',   `${avail}/${state.tools.length}`);
    renderRecentJobs(history.slice(0, 5));
    renderToolStatusGrid(state.tools.slice(0, 12));
  } catch (e) { console.error('Dashboard error:', e); }
}

function setVal(id, v) {
  const el = document.getElementById(id);
  if (el) el.textContent = v;
}

function renderRecentJobs(jobs) {
  const c = document.getElementById('recent-jobs-list');
  if (!c) return;
  if (!jobs || !jobs.length) {
    c.innerHTML = `<div class="empty-state"><i class="fas fa-inbox"></i><p>No jobs yet</p></div>`;
    return;
  }
  c.innerHTML = jobs.map(j => `
    <div class="job-item" onclick="viewJobOutput('${j.id}')">
      <div class="job-status-indicator ${j.status}"></div>
      <div class="job-info">
        <div class="job-target">${escapeHtml(j.options?.target || 'Unknown')}</div>
        <div class="job-meta">${formatTime(j.startTime)} · ${j.type} · ${j.lineCount||0} lines</div>
      </div>
      <span class="job-type-badge">${j.type}</span>
    </div>`).join('');
}

function renderToolStatusGrid(tools) {
  const c = document.getElementById('tool-status-grid');
  if (!c) return;
  if (!tools || !tools.length) {
    c.innerHTML = '<div class="loading-spinner"><i class="fas fa-spinner fa-spin"></i> Loading...</div>';
    return;
  }
  c.innerHTML = tools.map(t => `
    <div class="tool-card ${t.available ? 'available' : 'unavailable'}">
      <div class="tool-status-dot ${t.available ? 'ok' : 'fail'}"></div>
      <div>
        <div class="tool-card-name">${t.name}</div>
        <div class="tool-card-ver">${t.version}</div>
      </div>
    </div>`).join('');
}

// ── Jobs page ──────────────────────────────────────────────────
async function loadJobs() {
  try {
    const [active, history] = await Promise.all([
      fetch('/api/jobs/active').then(r => r.json()),
      fetch('/api/jobs/history').then(r => r.json()),
    ]);

    // Tab handling
    document.querySelectorAll('.tab').forEach(tab => {
      tab.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        const isActive = tab.dataset.tab === 'active';
        document.getElementById('jobs-active-list').style.display  = isActive ? '' : 'none';
        document.getElementById('jobs-history-list').style.display = isActive ? 'none' : '';
      });
    });

    const ac = document.getElementById('jobs-active-list');
    if (ac) {
      if (!active.length) {
        ac.innerHTML = '<div class="empty-state"><i class="fas fa-pause-circle"></i><p>No active jobs</p></div>';
      } else {
        ac.innerHTML = active.map(j => `
          <div class="job-item">
            <div class="job-status-indicator running"></div>
            <div class="job-info">
              <div class="job-target">${escapeHtml(j.options?.target || j.options?.command || 'Unknown')}</div>
              <div class="job-meta">${j.type} · pid ${j.pid} · <span id="job-linecount-${j.id}">${j.lineCount} lines</span></div>
            </div>
            <button class="btn-sm btn-danger" onclick="stopJob('${j.id}')"><i class="fas fa-stop"></i> Stop</button>
          </div>`).join('');
      }
    }

    const hc = document.getElementById('jobs-history-list');
    if (hc) {
      hc.innerHTML = history.map(j => `
        <div class="job-item" onclick="viewJobOutput('${j.id}')" style="cursor:pointer">
          <div class="job-status-indicator ${j.status}"></div>
          <div class="job-info">
            <div class="job-target">${escapeHtml(j.options?.target || j.options?.command || 'Unknown')}</div>
            <div class="job-meta">${formatTime(j.startTime)} · ${j.type} · ${j.lineCount||0} lines · exit ${j.exitCode ?? '?'}</div>
          </div>
          <span class="job-type-badge ${j.status}">${j.status}</span>
        </div>`).join('');
    }
  } catch (e) { console.error('Jobs error:', e); }
}

async function stopJob(jobId) {
  try {
    await fetch(`/api/scan/stop/${jobId}`, { method: 'POST' });
    toast('Stop signal sent', 'warning');
    setTimeout(loadJobs, 500);
  } catch (e) { toast('Stop failed: ' + e.message, 'error'); }
}

async function viewJobOutput(jobId) {
  navigateTo('scan');
  state.currentScanJobId = jobId;

  const terminal = document.getElementById('output-terminal');
  if (terminal) { terminal.innerHTML = ''; state.outputLineCount = 0; }

  const panel = document.getElementById('scan-output-panel');
  if (panel) {
    panel.style.display = 'flex';
    panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  appendOutputLine(`► Loading job output: ${jobId.substring(0,8)}…`, 'info');
  subscribeToJob(jobId, 0);

  // Also do HTTP replay in case WS is slow
  try {
    const data = await fetch(`/api/jobs/${jobId}/output`).then(r => r.json());
    if (terminal) terminal.innerHTML = '';
    state.outputLineCount = 0;
    data.lines.forEach(entry => appendOutputLine(entry.text, entry.stream, true));
    state.outputLineCount = data.lineCount || data.lines.length;
    updateOutputStats(state.outputLineCount);
    scrollToBottom();
    if (data.status === 'running') setScanRunning(true);
    else setScanRunning(false);
  } catch {}
}

// ── Tools page ─────────────────────────────────────────────────
async function loadTools() {
  try {
    const data = await fetch('/api/tools').then(r => r.json());
    state.tools = data.tools || [];
    renderToolsDetail(state.tools);
    renderToolStatusGrid(state.tools.slice(0, 12));
    setVal('stat-tools-count', `${state.tools.filter(t=>t.available).length}/${state.tools.length}`);
  } catch (e) { console.error('Tools error:', e); }
}

function renderToolsDetail(tools) {
  const c = document.getElementById('tools-detail-grid');
  if (!c) return;
  c.innerHTML = tools.map(t => {
    const info = TOOL_INFO[t.name] || {};
    return `
      <div class="tool-detail-card">
        <div class="tool-detail-header">
          <div class="tool-detail-icon" style="background:${info.color||'#6366f1'}22;color:${info.color||'#6366f1'}">${info.icon||'🔧'}</div>
          <div><div class="tool-detail-name">${t.name}</div></div>
          <span class="tool-detail-status ${t.available?'ok':'fail'}">${t.available?'● Available':'● Missing'}</span>
        </div>
        <div class="tool-detail-body">
          <p class="tool-detail-desc">${info.desc||'Security/recon tool'}</p>
          <div class="tool-detail-ver">${t.version||'version unknown'}</div>
          ${info.cmd?`<div class="tool-detail-cmd"><code>${escapeHtml(info.cmd)}</code></div>`:''}
          <div class="tool-detail-tags">${(info.tags||[]).map(tg=>`<span class="tool-tag">${tg}</span>`).join('')}</div>
        </div>
      </div>`;
  }).join('');
}

// ── Results page ────────────────────────────────────────────────
async function loadOutputs() {
  try {
    const dirs = await fetch('/api/outputs').then(r => r.json());
    state.outputs = dirs;
    renderOutputTree(dirs);
  } catch (e) { console.error('Outputs error:', e); }
}

function renderOutputTree(dirs) {
  const c = document.getElementById('output-tree');
  if (!c) return;
  if (!dirs || !dirs.length) {
    c.innerHTML = '<div class="empty-state"><i class="fas fa-folder-open"></i><p>No output files yet</p></div>';
    return;
  }
  c.innerHTML = dirs.map(d => `
    <div class="tree-dir" onclick="loadDirFiles('${escapeHtml(d.name)}', this)">
      <div class="tree-dir-header">
        <i class="fas fa-folder"></i>
        <span class="tree-dir-name">${escapeHtml(d.name)}</span>
        <span class="tree-dir-meta">${d.fileCount} files · ${formatBytes(d.totalSize)}</span>
      </div>
      <div class="tree-dir-files" id="files-${escapeHtml(d.name)}" style="display:none"></div>
    </div>`).join('');
}

async function loadDirFiles(dirName, el) {
  const container = document.getElementById(`files-${dirName}`);
  if (!container) return;
  const wasOpen = container.style.display !== 'none';
  container.style.display = wasOpen ? 'none' : 'block';
  if (wasOpen || container.children.length > 0) return;
  try {
    const files = await fetch(`/api/outputs/${encodeURIComponent(dirName)}/files`).then(r => r.json());
    container.innerHTML = files.map(f => `
      <div class="tree-file" onclick="viewFile('${escapeHtml(f.path)}', '${escapeHtml(f.name)}')">
        <i class="fas fa-file-alt"></i>
        <span>${escapeHtml(f.name)}</span>
        <span class="tree-file-size">${formatBytes(f.size)}</span>
      </div>`).join('') || '<div class="empty-state" style="font-size:12px">Empty</div>';
  } catch {}
}

async function viewFile(filePath, fileName) {
  state.selectedFile = filePath;
  const viewer = document.getElementById('file-viewer');
  const actions = document.getElementById('file-viewer-actions');
  const dlBtn   = document.getElementById('download-file-btn');
  if (!viewer) return;
  viewer.innerHTML = '<div class="loading-spinner"><i class="fas fa-spinner fa-spin"></i> Loading…</div>';
  if (actions) actions.style.display = 'flex';
  if (dlBtn) dlBtn.onclick = () => window.open(`/api/download?path=${encodeURIComponent(filePath)}`);
  try {
    const data = await fetch(`/api/file?path=${encodeURIComponent(filePath)}&lines=1000`).then(r => r.json());
    viewer.innerHTML = `
      <div class="file-viewer-info">${escapeHtml(fileName)} · ${data.totalLines} lines${data.truncated?' (truncated)':''}</div>
      <pre class="file-content">${escapeHtml(data.content)}</pre>`;
  } catch (e) { viewer.innerHTML = `<div class="empty-state">Error: ${e.message}</div>`; }
}

// ── Terminal page ───────────────────────────────────────────────
function initTerminal() {
  const input = document.getElementById('terminal-input');
  if (input) {
    input.addEventListener('keypress', e => { if (e.key === 'Enter') execTerminalCmd(); });
    input.addEventListener('keydown',  e => {
      if (e.key === 'ArrowUp') {
        if (state.terminalHistory.length) {
          state._histIdx = Math.max(0, (state._histIdx ?? state.terminalHistory.length) - 1);
          input.value = state.terminalHistory[state._histIdx] || '';
        }
      }
    });
  }
}

async function execTerminalCmd() {
  const input = document.getElementById('terminal-input');
  const cmd   = input?.value?.trim();
  if (!cmd) return;
  if (input) input.value = '';

  state.terminalHistory.push(cmd);
  state._histIdx = state.terminalHistory.length;

  const hist = document.getElementById('terminal-history');
  if (hist) {
    const cmdLine = document.createElement('div');
    cmdLine.className = 'terminal-line terminal-cmd';
    cmdLine.innerHTML = `<span class="terminal-prompt">$</span> <span class="ttext">${escapeHtml(cmd)}</span>`;
    hist.appendChild(cmdLine);
    hist.scrollTop = hist.scrollHeight;
  }

  // Use SSE for streaming terminal output
  const evtSrc = new EventSource(`/api/exec/stream?cmd=${encodeURIComponent(cmd)}`);
  evtSrc.onmessage = ev => {
    try {
      const d = JSON.parse(ev.data);
      if (!hist) return;
      if (d.type === 'exit') {
        const exitLine = document.createElement('div');
        exitLine.className = 'terminal-line info';
        exitLine.innerHTML = `<span class="ttext" style="color:var(--text-muted)">exit ${d.text}</span>`;
        hist.appendChild(exitLine);
        hist.scrollTop = hist.scrollHeight;
        evtSrc.close();
        return;
      }
      if (d.text === '') return;
      const line = document.createElement('div');
      line.className = `terminal-line ${d.type}`;
      line.innerHTML = `<span class="ttext">${highlightUrls(escapeHtml(stripAnsi(d.text)))}</span>`;
      hist.appendChild(line);
      hist.scrollTop = hist.scrollHeight;
    } catch {}
  };
  evtSrc.onerror = () => evtSrc.close();
}

// ── Docs page ───────────────────────────────────────────────────
function loadDocs() {
  const c = document.getElementById('docs-content');
  if (!c) return;
  c.innerHTML = `
    <div class="docs-card">
      <h2><i class="fas fa-book"></i> Documentation</h2>
      <p>Web Crawler Toolkit 2026 — 17 security tools orchestrated via a Node.js dashboard with real-time WebSocket streaming.</p>
      <h3>Quick Start</h3>
      <ol>
        <li>Go to <strong>New Scan</strong> and enter your target URL (e.g. <code>https://example.com</code>)</li>
        <li>Select scan type: Full Scan, Crawl Only, URL Collection, or JS Analyze</li>
        <li>Adjust depth and thread settings</li>
        <li>Click <strong>Launch Scan</strong> — output streams live below</li>
        <li>Results saved to <code>/workspace/output/</code> — browse in <strong>Results</strong> tab</li>
      </ol>
      <h3>Scan Types</h3>
      <table class="docs-table">
        <tr><th>Type</th><th>Tools Used</th><th>Best For</th></tr>
        <tr><td>Full Scan</td><td>katana, gau, gospider, waymore, xnLinkFinder, httpx, gf</td><td>Complete recon</td></tr>
        <tr><td>Crawl Only</td><td>katana, gospider, xnLinkFinder, httpx</td><td>Fast URL discovery</td></tr>
        <tr><td>URL Collection</td><td>gau, waybackurls, waymore</td><td>Passive/archive URLs</td></tr>
        <tr><td>JS Analyze</td><td>katana, gau, curl + regex</td><td>JS endpoint extraction</td></tr>
        <tr><td>Custom</td><td>any command</td><td>Direct tool access</td></tr>
      </table>
      <h3>Tool Directory</h3>
      <p>All tools installed in <code>/usr/local/bin/</code> and <code>/opt/venv/bin/</code>. Access them directly in the <strong>Terminal</strong> tab.</p>
    </div>`;
}

// ── Utility helpers ─────────────────────────────────────────────
function escapeHtml(s) {
  return String(s || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function stripAnsi(s) {
  return String(s || '')
    .replace(/\x1B\[[0-9;]*[mGKHFABCDsuJrTMPlh]/g, '')
    .replace(/\x1B\][^\x07]*\x07/g, '')
    .replace(/\x1B[()][0-9A-Z]/g, '')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ''); // strip other ctrl chars
}

function highlightUrls(html) {
  return html.replace(/(https?:\/\/[^\s&"<>]+)/g,
    '<a href="$1" target="_blank" rel="noopener" class="url-link">$1</a>');
}

function formatTime(iso) {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleTimeString(); } catch { return iso; }
}

function formatBytes(n) {
  if (!n) return '0 B';
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n/1024).toFixed(1)} KB`;
  return `${(n/1048576).toFixed(1)} MB`;
}

function refreshPage() {
  if (state.currentPage === 'dashboard') loadDashboard();
  else if (state.currentPage === 'tools')   loadTools();
  else if (state.currentPage === 'results') loadOutputs();
  else if (state.currentPage === 'jobs')    loadJobs();
}

// ── Toast ───────────────────────────────────────────────────────
function toast(msg, type = 'info') {
  const c = document.getElementById('toast-container');
  if (!c) return;
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  const icons = { info: 'fa-info-circle', success: 'fa-check-circle', warning: 'fa-exclamation-triangle', error: 'fa-times-circle' };
  t.innerHTML = `<i class="fas ${icons[type]||'fa-info-circle'}"></i> ${escapeHtml(msg)}`;
  c.appendChild(t);
  setTimeout(() => t.classList.add('show'), 10);
  setTimeout(() => { t.classList.remove('show'); setTimeout(() => t.remove(), 300); }, 4000);
}

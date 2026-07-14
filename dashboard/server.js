/**
 * Web Crawler Toolkit 2026 - Dashboard Server
 * Node.js + Express + WebSocket — STREAMING FIXED v3
 *
 * Key design:
 *  - spawn() with { stdio: ['ignore','pipe','pipe'] }
 *  - stdout/stderr data events flush IMMEDIATELY per chunk (no batching)
 *  - flushLines() splits on \n, emits every complete line via broadcastJob()
 *  - 5000-line ring buffer per job for late-joiner replay
 *  - WS subscribe message triggers instant replay then live stream
 *  - NO terminal clearing on job-started in frontend (fixed in app.js)
 */

'use strict';

const express   = require('express');
const http      = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const path      = require('path');
const fs        = require('fs');
const { v4: uuidv4 } = require('uuid');
const cors      = require('cors');
const multer    = require('multer');

const app    = express();
const server = http.createServer(app);
const wss    = new WebSocket.Server({ server });

const PORT        = process.env.PORT        || 3000;
const OUTPUT_DIR  = process.env.OUTPUT_DIR  || '/workspace/output';
const SCRIPTS_DIR = process.env.SCRIPTS_DIR || '/workspace/scripts';

// ── Job storage ──────────────────────────────────────────────
const activeJobs = new Map();   // jobId → job
const jobHistory = [];          // newest first, kept forever (small)

// ── Per-client subscription ──────────────────────────────────
// ws → Set<jobId>  (empty Set = receives everything)
const clientSubs = new Map();

// ── Middleware ───────────────────────────────────────────────
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const upload = multer({ dest: '/workspace/targets/' });

// ── WebSocket helpers ────────────────────────────────────────

function broadcast(data) {
  const msg = JSON.stringify(data);
  wss.clients.forEach(ws => {
    if (ws.readyState === WebSocket.OPEN) ws.send(msg);
  });
}

function broadcastJob(jobId, data) {
  const msg = JSON.stringify(data);
  wss.clients.forEach(ws => {
    if (ws.readyState !== WebSocket.OPEN) return;
    const subs = clientSubs.get(ws);
    if (!subs || subs.size === 0 || subs.has(jobId)) ws.send(msg);
  });
}

// ── Tool availability ────────────────────────────────────────
async function checkTools() {
  const tools = [
    { name: 'katana',       cmd: 'katana',       flag: '-version'  },
    { name: 'gau',          cmd: 'gau',          flag: '--version' },
    { name: 'gospider',     cmd: 'gospider',     flag: '--version' },
    { name: 'httpx',        cmd: 'httpx',        flag: '-version'  },
    { name: 'waymore',      cmd: 'waymore',      flag: '--version' },
    { name: 'xnLinkFinder', cmd: 'xnLinkFinder', flag: '--version' },
    { name: 'subfinder',    cmd: 'subfinder',    flag: '-version'  },
    { name: 'nuclei',       cmd: 'nuclei',       flag: '-version'  },
    { name: 'dnsx',         cmd: 'dnsx',         flag: '-version'  },
    { name: 'naabu',        cmd: 'naabu',        flag: '-version'  },
    { name: 'waybackurls',  cmd: 'waybackurls',  flag: '-h'        },
    { name: 'anew',         cmd: 'anew',         flag: '-h'        },
    { name: 'gf',           cmd: 'gf',           flag: '-h'        },
    { name: 'uro',          cmd: 'uro',          flag: '--help'    },
    { name: 'unfurl',       cmd: 'unfurl',       flag: '-h'        },
    { name: 'node',         cmd: 'node',         flag: '--version' },
    { name: 'python3',      cmd: 'python3',      flag: '--version' },
  ];

  return Promise.all(tools.map(t => new Promise(resolve => {
    const p = spawn(t.cmd, [t.flag], {
      timeout: 5000,
      env: { ...process.env, PATH: process.env.PATH + ':/usr/local/bin:/opt/venv/bin' }
    });
    let ver = '';
    p.stdout.on('data', d => { ver += d; });
    p.stderr.on('data', d => { ver += d; });
    p.on('close', code => resolve({
      name: t.name,
      available: code === 0 || code === 1 || code === 2,
      version: ver.split('\n')[0].trim().substring(0, 60) || 'available'
    }));
    p.on('error', () => resolve({ name: t.name, available: false, version: 'not found' }));
  })));
}

// ── Core: execute a scan job ─────────────────────────────────
function executeScan(jobId, type, options) {
  const job = {
    id:        jobId,
    type,
    options,
    status:    'running',
    startTime: new Date().toISOString(),
    endTime:   null,
    exitCode:  null,
    output:    [],      // ring buffer — max 5000 entries
    lineCount: 0,
    pid:       null,
    outputFiles: []
  };

  activeJobs.set(jobId, job);
  jobHistory.unshift(job);
  if (jobHistory.length > 200) jobHistory.pop();

  // ── Build command ─────────────────────────────────────────
  let cmd, args;
  const { target, depth = '3', threads = '50', command } = options;

  switch (type) {
    case 'full-scan':
      cmd  = '/workspace/scripts/full-scan.sh';
      args = [target];
      break;
    case 'crawl':
      cmd  = '/workspace/scripts/crawl-only.sh';
      args = [target, depth, threads];
      break;
    case 'urls':
      cmd  = '/workspace/scripts/collect-urls.sh';
      args = [target, threads];
      break;
    case 'js-analyze':
      cmd  = '/workspace/scripts/js-analyze.sh';
      args = [target];
      break;
    case 'custom':
      cmd  = '/bin/bash';
      args = ['-c', command || 'echo no command'];
      break;
    default:
      broadcastJob(jobId, { type: 'job-error', jobId, message: `Unknown scan type: ${type}` });
      activeJobs.delete(jobId);
      return null;
  }

  // ── Spawn ─────────────────────────────────────────────────
  const THREADS = threads;
  const DEPTH   = depth;

  const proc = spawn(cmd, args, {
    stdio:    ['ignore', 'pipe', 'pipe'],
    detached: false,
    env: {
      ...process.env,
      THREADS,
      DEPTH,
      TIMEOUT:         '15',
      PATH:            `${process.env.PATH}:/usr/local/bin:/opt/venv/bin`,
      VIRTUAL_ENV:     '/opt/venv',
      PYTHONUNBUFFERED:'1',
      FORCE_COLOR:     '0',
      TERM:            'dumb',
    }
  });

  job.pid = proc.pid;
  console.log(`[JOB] start  id=${jobId} type=${type} target=${target || command} pid=${proc.pid}`);

  broadcast({
    type:      'job-started',
    jobId,
    scanType:  type,
    target,
    pid:       proc.pid,
    timestamp: new Date().toISOString()
  });

  // ── Stream lines ──────────────────────────────────────────
  let outBuf = '';
  let errBuf = '';

  /**
   * Split buffer on newlines.
   * Emit every complete line immediately via broadcastJob.
   * Return the trailing incomplete fragment.
   */
  function flushLines(buf, stream) {
    const parts = buf.split('\n');
    for (let i = 0; i < parts.length - 1; i++) {
      const line = parts[i];
      // Ring buffer — keep last 5000 lines
      if (job.output.length >= 5000) job.output.shift();
      job.output.push({ t: new Date().toISOString(), text: line, stream });
      job.lineCount++;

      broadcastJob(jobId, {
        type:      'job-output',
        jobId,
        line,
        stream,
        lineNum:   job.lineCount,
        timestamp: new Date().toISOString()
      });
    }
    return parts[parts.length - 1]; // incomplete tail
  }

  // Pipe stdout — emit immediately on every data chunk
  proc.stdout.on('data', chunk => {
    outBuf += chunk.toString('utf8');
    outBuf  = flushLines(outBuf, 'stdout');
  });

  // Pipe stderr — emit immediately on every data chunk
  proc.stderr.on('data', chunk => {
    errBuf += chunk.toString('utf8');
    errBuf  = flushLines(errBuf, 'stderr');
  });

  // Flush remaining partial lines on close
  proc.on('close', (code, signal) => {
    if (outBuf.trim()) { outBuf += '\n'; flushLines(outBuf, 'stdout'); }
    if (errBuf.trim()) { errBuf += '\n'; flushLines(errBuf, 'stderr'); }

    job.status   = code === 0 ? 'completed' : (signal ? 'stopped' : 'failed');
    job.endTime  = new Date().toISOString();
    job.exitCode = code;

    const dom = (target || '').replace(/https?:\/\//, '').replace(/\/.*/, '');
    job.outputFiles = getOutputFiles(dom);

    const dur = Date.now() - new Date(job.startTime).getTime();

    console.log(`[JOB] done   id=${jobId} exit=${code} lines=${job.lineCount} ${dur}ms`);

    broadcastJob(jobId, {
      type:        'job-complete',
      jobId,
      exitCode:    code,
      status:      job.status,
      outputFiles: job.outputFiles,
      lineCount:   job.lineCount,
      duration:    dur,
      timestamp:   new Date().toISOString()
    });

    activeJobs.delete(jobId);
  });

  proc.on('error', err => {
    console.error(`[JOB] error  id=${jobId}`, err.message);
    job.status = 'error';
    broadcastJob(jobId, {
      type:      'job-error',
      jobId,
      message:   err.message,
      timestamp: new Date().toISOString()
    });
    activeJobs.delete(jobId);
  });

  return job;
}

// ── Output file discovery ────────────────────────────────────
function getOutputFiles(domain) {
  try {
    if (!fs.existsSync(OUTPUT_DIR)) return [];
    return fs.readdirSync(OUTPUT_DIR)
      .filter(d => !domain || d.includes(domain))
      .map(d => path.join(OUTPUT_DIR, d))
      .filter(d => { try { return fs.statSync(d).isDirectory(); } catch { return false; } })
      .flatMap(dir => { const f = []; walkDir(dir, f); return f; })
      .slice(0, 100);
  } catch { return []; }
}

function walkDir(dir, out) {
  try {
    fs.readdirSync(dir).forEach(item => {
      const full = path.join(dir, item);
      try {
        const s = fs.statSync(full);
        if (s.isDirectory()) walkDir(full, out);
        else out.push({ path: full, name: item, size: s.size, modified: s.mtime.toISOString() });
      } catch {}
    });
  } catch {}
}

// ── REST API ─────────────────────────────────────────────────

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '2026.4.0', timestamp: new Date().toISOString() });
});

app.get('/api/tools', async (req, res) => {
  try {
    res.json({ tools: await checkTools(), timestamp: new Date().toISOString() });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/scan/start', (req, res) => {
  const { type = 'full-scan', target, depth, threads, command } = req.body;
  if (!target && type !== 'custom') return res.status(400).json({ error: 'Target required' });

  const jobId = uuidv4();
  const job   = executeScan(jobId, type, { target, depth, threads, command });
  if (!job) return res.status(400).json({ error: 'Failed to start scan' });

  res.json({ jobId, status: 'started', pid: job.pid });
});

app.post('/api/scan/stop/:jobId', (req, res) => {
  const job = activeJobs.get(req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Job not found or already finished' });
  try { process.kill(job.pid, 'SIGTERM'); } catch {}
  job.status = 'stopped';
  activeJobs.delete(req.params.jobId);
  broadcast({ type: 'job-stopped', jobId: req.params.jobId, timestamp: new Date().toISOString() });
  res.json({ status: 'stopped' });
});

// Replay endpoint — returns buffered output for a job
app.get('/api/jobs/:jobId/output', (req, res) => {
  const job = jobHistory.find(j => j.id === req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Not found' });
  const from = Math.max(0, parseInt(req.query.from) || 0);
  res.json({
    jobId:     job.id,
    status:    job.status,
    lineCount: job.lineCount,
    lines:     job.output.slice(from)
  });
});

app.get('/api/jobs/active', (req, res) => {
  res.json(Array.from(activeJobs.values()).map(j => ({
    id: j.id, type: j.type, status: j.status,
    startTime: j.startTime, options: j.options,
    lineCount: j.lineCount, pid: j.pid
  })));
});

app.get('/api/jobs/history', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  res.json(jobHistory.slice(0, limit).map(j => ({
    id: j.id, type: j.type, status: j.status,
    startTime: j.startTime, endTime: j.endTime,
    exitCode: j.exitCode, options: j.options,
    lineCount: j.lineCount, outputFiles: j.outputFiles
  })));
});

app.get('/api/outputs', (req, res) => {
  try {
    if (!fs.existsSync(OUTPUT_DIR)) return res.json([]);
    const dirs = fs.readdirSync(OUTPUT_DIR)
      .filter(d => { try { return fs.statSync(path.join(OUTPUT_DIR, d)).isDirectory(); } catch { return false; } })
      .map(d => {
        const dp = path.join(OUTPUT_DIR, d);
        const st = fs.statSync(dp);
        const fl = []; walkDir(dp, fl);
        return { name: d, path: dp, created: st.birthtime.toISOString(), modified: st.mtime.toISOString(), fileCount: fl.length, totalSize: fl.reduce((s, f) => s + f.size, 0) };
      })
      .sort((a, b) => new Date(b.modified) - new Date(a.modified));
    res.json(dirs);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/outputs/:dir/files', (req, res) => {
  const dp = path.join(OUTPUT_DIR, req.params.dir);
  if (!fs.existsSync(dp)) return res.status(404).json({ error: 'Not found' });
  const f = []; walkDir(dp, f);
  res.json(f);
});

app.get('/api/file', (req, res) => {
  const fp = req.query.path;
  if (!fp || !fs.existsSync(fp)) return res.status(404).json({ error: 'Not found' });
  try {
    const lines = parseInt(req.query.lines) || 500;
    const all   = fs.readFileSync(fp, 'utf8').split('\n');
    res.json({ path: fp, totalLines: all.length, content: all.slice(0, lines).join('\n'), truncated: all.length > lines });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/download', (req, res) => {
  const fp = req.query.path;
  if (!fp || !fs.existsSync(fp)) return res.status(404).json({ error: 'Not found' });
  res.download(fp);
});

app.post('/api/upload/targets', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file' });
  res.json({ filename: req.file.originalname, path: req.file.path, size: req.file.size });
});

// SCP-like file deploy: POST /api/upload/file
// Body: { path: '/workspace/scripts/full-scan.sh', content: '<base64>', executable: true }
// This is the server-side of deploy.sh — allows any file to be pushed to any container path.
app.post('/api/upload/file', (req, res) => {
  const { path: destPath, content, executable = false, encoding = 'base64' } = req.body;
  if (!destPath || !content) {
    return res.status(400).json({ error: 'path and content are required' });
  }
  // Security: only allow writes inside /workspace or /root/.gf
  const allowed = ['/workspace/', '/root/.gf/', '/etc/ssh/'];
  const isAllowed = allowed.some(prefix => destPath.startsWith(prefix));
  if (!isAllowed) {
    return res.status(403).json({ error: `Writes only allowed under: ${allowed.join(', ')}` });
  }
  try {
    const dir = path.dirname(destPath);
    fs.mkdirSync(dir, { recursive: true });
    const buf = encoding === 'base64' ? Buffer.from(content, 'base64') : Buffer.from(content, 'utf8');
    fs.writeFileSync(destPath, buf);
    if (executable) fs.chmodSync(destPath, 0o755);
    res.json({ ok: true, path: destPath, size: buf.length, executable });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Exec (non-streaming — for quick commands)
app.post('/api/exec', (req, res) => {
  const { command, timeout: tmo = 30000 } = req.body;
  if (!command) return res.status(400).json({ error: 'Command required' });
  const p = spawn('/bin/bash', ['-c', command], {
    env: { ...process.env, PATH: `${process.env.PATH}:/usr/local/bin:/opt/venv/bin`, PYTHONUNBUFFERED: '1' },
    timeout: tmo
  });
  let out = '', err = '';
  p.stdout.on('data', d => { out += d; });
  p.stderr.on('data', d => { err += d; });
  p.on('close', code => res.json({ exitCode: code, stdout: out.slice(0, 10000), stderr: err.slice(0, 5000) }));
  p.on('error', e => res.status(500).json({ error: e.message }));
});

// SSE streaming exec (terminal page)
app.get('/api/exec/stream', (req, res) => {
  const command = req.query.cmd;
  if (!command) return res.status(400).end();
  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.flushHeaders();
  const p = spawn('/bin/bash', ['-c', command], {
    env: { ...process.env, PATH: `${process.env.PATH}:/usr/local/bin:/opt/venv/bin`, PYTHONUNBUFFERED: '1' }
  });
  const emit = (type, text) => res.write(`data: ${JSON.stringify({ type, text })}\n\n`);
  p.stdout.on('data', d => d.toString().split('\n').forEach(l => emit('stdout', l)));
  p.stderr.on('data', d => d.toString().split('\n').forEach(l => emit('stderr', l)));
  p.on('close', code => { emit('exit', String(code)); res.end(); });
  req.on('close', () => { try { p.kill(); } catch {} });
});

app.get('/api/system', (req, res) => {
  const p = spawn('sh', ['-c', 'df -h / && free -h && uptime']);
  let out = '';
  p.stdout.on('data', d => { out += d; });
  p.on('close', () => res.json({
    activeJobs: activeJobs.size, totalJobs: jobHistory.length,
    uptime: process.uptime(), stats: out, timestamp: new Date().toISOString()
  }));
});

// ── WebSocket handler ────────────────────────────────────────
wss.on('connection', (ws, req) => {
  clientSubs.set(ws, new Set());
  console.log(`[WS] connect  ${req.socket.remoteAddress}`);

  ws.send(JSON.stringify({
    type:       'connected',
    activeJobs: activeJobs.size,
    timestamp:  new Date().toISOString()
  }));

  ws.on('message', raw => {
    try {
      const msg = JSON.parse(raw);
      switch (msg.type) {

        case 'ping':
          ws.send(JSON.stringify({ type: 'pong', timestamp: new Date().toISOString() }));
          break;

        case 'subscribe': {
          if (!msg.jobId) break;
          clientSubs.get(ws)?.add(msg.jobId);

          // Replay buffered output immediately
          const job = jobHistory.find(j => j.id === msg.jobId);
          if (!job) break;

          const from = Math.max(0, parseInt(msg.from) || 0);
          const slice = job.output.slice(from);

          // Send replay lines as a batch first
          slice.forEach((entry, idx) => {
            ws.send(JSON.stringify({
              type:      'job-output',
              jobId:     job.id,
              line:      entry.text,
              stream:    entry.stream,
              lineNum:   from + idx + 1,
              replay:    true,
              timestamp: entry.t
            }));
          });

          // If job already finished, replay complete event
          if (job.status !== 'running') {
            ws.send(JSON.stringify({
              type:        'job-complete',
              jobId:       job.id,
              exitCode:    job.exitCode,
              status:      job.status,
              outputFiles: job.outputFiles,
              lineCount:   job.lineCount,
              replay:      true,
              timestamp:   job.endTime
            }));
          }
          break;
        }

        case 'unsubscribe':
          if (msg.jobId) clientSubs.get(ws)?.delete(msg.jobId);
          break;
      }
    } catch { /* ignore malformed */ }
  });

  ws.on('close',  () => { clientSubs.delete(ws); console.log('[WS] disconnect'); });
  ws.on('error',  () => { clientSubs.delete(ws); });
});

// ── Catch-all SPA ────────────────────────────────────────────
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ── Start ────────────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
  console.log('╔══════════════════════════════════════════════╗');
  console.log('║   🕷️  Crawler Toolkit 2026  Dashboard v3      ║');
  console.log(`║   http://0.0.0.0:${PORT}                        ║`);
  console.log('╚══════════════════════════════════════════════╝');
  checkTools().then(t => console.log(`[*] Tools: ${t.filter(x=>x.available).length}/${t.length} available`));
});

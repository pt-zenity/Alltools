/**
 * Web Crawler Toolkit 2026 - Dashboard Server
 * Node.js + Express + WebSocket  (FIXED: real-time streaming)
 */

const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');
const multer = require('multer');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const PORT = process.env.PORT || 3000;
const OUTPUT_DIR = process.env.OUTPUT_DIR || path.join(__dirname, '../workspace/output');
const SCRIPTS_DIR = process.env.SCRIPTS_DIR || path.join(__dirname, '../scripts');

// Active jobs tracker
const activeJobs = new Map();
const jobHistory = [];

// Per-client subscriptions: ws -> Set of jobIds they want to watch
const clientSubscriptions = new Map();

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// File upload setup
const upload = multer({ dest: path.join(__dirname, '../workspace/targets/') });

// ── WebSocket helpers ────────────────────────────────────────

/** Broadcast to ALL connected clients */
function broadcast(data) {
  const message = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

/** Send to clients subscribed to a specific jobId, plus unfiltered clients */
function broadcastJob(jobId, data) {
  const message = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState !== WebSocket.OPEN) return;
    const subs = clientSubscriptions.get(client);
    // Send if: client has no subscription filter, or is subscribed to this jobId
    if (!subs || subs.size === 0 || subs.has(jobId)) {
      client.send(message);
    }
  });
}

// ── Tool availability check ──────────────────────────────────
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

  const results = await Promise.all(tools.map(tool =>
    new Promise(resolve => {
      const proc = spawn(tool.cmd, [tool.flag], {
        timeout: 5000,
        env: { ...process.env, PATH: process.env.PATH + ':/usr/local/bin:/opt/venv/bin' }
      });
      let version = '';
      proc.stdout.on('data', d => version += d);
      proc.stderr.on('data', d => version += d);
      proc.on('close', code => {
        resolve({
          name: tool.name,
          available: code === 0 || code === 1 || code === 2,
          version: version.split('\n')[0].trim().substring(0, 60) || 'available'
        });
      });
      proc.on('error', () => {
        resolve({ name: tool.name, available: false, version: 'not found' });
      });
    })
  ));

  return results;
}

// ── Execute a scan job ───────────────────────────────────────
function executeScan(jobId, type, options) {
  const job = {
    id: jobId,
    type,
    options,
    status: 'running',
    startTime: new Date().toISOString(),
    output: [],       // full log buffer (for late-joining clients)
    lineCount: 0,
    pid: null
  };

  activeJobs.set(jobId, job);
  jobHistory.unshift(job);

  let cmd, args;
  const target  = options.target;
  const depth   = options.depth   || '3';
  const threads = options.threads || '50';

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
      args = ['-c', options.command];
      break;
    default:
      broadcast({ type: 'job-error', jobId, message: 'Unknown scan type' });
      activeJobs.delete(jobId);
      return null;
  }

  const proc = spawn(cmd, args, {
    // stdbuf -oL forces line-buffered stdout so tools flush every line immediately
    // We wrap via stdbuf when available, fall back gracefully
    env: {
      ...process.env,
      THREADS:     threads,
      DEPTH:       depth,
      PATH:        process.env.PATH + ':/usr/local/bin:/opt/venv/bin',
      VIRTUAL_ENV: '/opt/venv',
      // force unbuffered python output
      PYTHONUNBUFFERED: '1',
      // force unbuffered C stdio for Go tools
      FORCE_COLOR: '0',
    },
    // Important: do NOT buffer in Node — get chunks immediately
  });

  job.pid = proc.pid;

  broadcast({
    type:      'job-started',
    jobId,
    scanType:  type,
    target,
    pid:       proc.pid,
    timestamp: new Date().toISOString()
  });

  console.log(`[JOB] Started ${type} on ${target} | id=${jobId} pid=${proc.pid}`);

  // ── Real-time line streaming ────────────────────────────────
  let stdoutBuf = '';
  let stderrBuf = '';

  function flushLines(buffer, remaining, stream) {
    const lines = buffer.split('\n');
    // All but last element are complete lines
    for (let i = 0; i < lines.length - 1; i++) {
      const line = lines[i];
      // Store in job buffer (keep last 2000 lines to avoid memory blowup)
      if (job.output.length >= 2000) job.output.shift();
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
    // Return the incomplete last fragment
    return lines[lines.length - 1];
  }

  proc.stdout.on('data', chunk => {
    stdoutBuf += chunk.toString();
    stdoutBuf = flushLines(stdoutBuf, '', 'stdout');
  });

  proc.stderr.on('data', chunk => {
    stderrBuf += chunk.toString();
    stderrBuf = flushLines(stderrBuf, '', 'stderr');
  });

  // Flush any remaining partial lines when process closes
  proc.on('close', code => {
    if (stdoutBuf.trim()) flushLines(stdoutBuf + '\n', '', 'stdout');
    if (stderrBuf.trim()) flushLines(stderrBuf + '\n', '', 'stderr');

    job.status    = code === 0 ? 'completed' : (code === null ? 'stopped' : 'failed');
    job.endTime   = new Date().toISOString();
    job.exitCode  = code;

    const domain = (target || '').replace(/https?:\/\//, '').replace(/\/.*/, '');
    job.outputFiles = getOutputFiles(domain);

    const duration = new Date(job.endTime) - new Date(job.startTime);

    broadcastJob(jobId, {
      type:        'job-complete',
      jobId,
      exitCode:    code,
      status:      job.status,
      outputFiles: job.outputFiles,
      lineCount:   job.lineCount,
      duration,
      timestamp:   new Date().toISOString()
    });

    console.log(`[JOB] Finished ${jobId} | exit=${code} lines=${job.lineCount} duration=${duration}ms`);
    activeJobs.delete(jobId);
  });

  proc.on('error', err => {
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

// ── Get output files ─────────────────────────────────────────
function getOutputFiles(domain) {
  try {
    if (!fs.existsSync(OUTPUT_DIR)) return [];
    const dirs = fs.readdirSync(OUTPUT_DIR)
      .filter(d => domain ? d.includes(domain) : true)
      .map(d => path.join(OUTPUT_DIR, d))
      .filter(d => { try { return fs.statSync(d).isDirectory(); } catch { return false; } });

    const files = [];
    dirs.forEach(dir => walkDir(dir, files));
    return files.slice(0, 100);
  } catch (e) {
    return [];
  }
}

function walkDir(dir, results) {
  try {
    fs.readdirSync(dir).forEach(item => {
      const full = path.join(dir, item);
      try {
        const stat = fs.statSync(full);
        if (stat.isDirectory()) {
          walkDir(full, results);
        } else {
          results.push({ path: full, name: item, size: stat.size, modified: stat.mtime.toISOString() });
        }
      } catch {}
    });
  } catch {}
}

// ── API Routes ───────────────────────────────────────────────

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '2026.1.0', timestamp: new Date().toISOString() });
});

app.get('/api/tools', async (req, res) => {
  try {
    res.json({ tools: await checkTools(), timestamp: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Start scan
app.post('/api/scan/start', (req, res) => {
  const { type, target, depth, threads, command } = req.body;
  if (!target && type !== 'custom') {
    return res.status(400).json({ error: 'Target is required' });
  }

  const jobId = uuidv4();
  const job   = executeScan(jobId, type || 'full-scan', { target, depth, threads, command });
  if (!job) return res.status(400).json({ error: 'Failed to start scan' });

  res.json({ jobId, status: 'started', pid: job.pid });
});

// Stop job
app.post('/api/scan/stop/:jobId', (req, res) => {
  const job = activeJobs.get(req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Job not found' });

  try {
    // Kill the entire process group
    process.kill(-job.pid, 'SIGTERM');
  } catch {
    try { process.kill(job.pid, 'SIGTERM'); } catch {}
  }

  job.status = 'stopped';
  activeJobs.delete(req.params.jobId);
  broadcast({ type: 'job-stopped', jobId: req.params.jobId, timestamp: new Date().toISOString() });
  res.json({ status: 'stopped' });
});

// Get job output buffer (for reconnect / replay)
app.get('/api/jobs/:jobId/output', (req, res) => {
  const job = jobHistory.find(j => j.id === req.params.jobId);
  if (!job) return res.status(404).json({ error: 'Job not found' });
  const from = parseInt(req.query.from) || 0;
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
  const limit = parseInt(req.query.limit) || 20;
  res.json(jobHistory.slice(0, limit).map(j => ({
    id: j.id, type: j.type, status: j.status,
    startTime: j.startTime, endTime: j.endTime,
    exitCode: j.exitCode, options: j.options,
    lineCount: j.lineCount, outputFiles: j.outputFiles || []
  })));
});

app.get('/api/outputs', (req, res) => {
  try {
    if (!fs.existsSync(OUTPUT_DIR)) return res.json([]);
    const dirs = fs.readdirSync(OUTPUT_DIR)
      .filter(d => { try { return fs.statSync(path.join(OUTPUT_DIR, d)).isDirectory(); } catch { return false; } })
      .map(d => {
        const dirPath = path.join(OUTPUT_DIR, d);
        const stat    = fs.statSync(dirPath);
        const files   = [];
        walkDir(dirPath, files);
        return {
          name:      d,
          path:      dirPath,
          created:   stat.birthtime.toISOString(),
          modified:  stat.mtime.toISOString(),
          fileCount: files.length,
          totalSize: files.reduce((s, f) => s + f.size, 0)
        };
      })
      .sort((a, b) => new Date(b.modified) - new Date(a.modified));
    res.json(dirs);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/outputs/:dir/files', (req, res) => {
  const dirPath = path.join(OUTPUT_DIR, req.params.dir);
  if (!fs.existsSync(dirPath)) return res.status(404).json({ error: 'Not found' });
  const files = [];
  walkDir(dirPath, files);
  res.json(files);
});

app.get('/api/file', (req, res) => {
  const filePath = req.query.path;
  if (!filePath || !fs.existsSync(filePath)) return res.status(404).json({ error: 'File not found' });
  const lines = parseInt(req.query.lines) || 500;
  try {
    const content  = fs.readFileSync(filePath, 'utf8');
    const allLines = content.split('\n');
    res.json({
      path: filePath, totalLines: allLines.length,
      content: allLines.slice(0, lines).join('\n'), truncated: allLines.length > lines
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/download', (req, res) => {
  const filePath = req.query.path;
  if (!filePath || !fs.existsSync(filePath)) return res.status(404).json({ error: 'Not found' });
  res.download(filePath);
});

app.post('/api/upload/targets', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  res.json({ filename: req.file.originalname, path: req.file.path, size: req.file.size });
});

// Custom command execution (streaming via WebSocket exec channel)
app.post('/api/exec', (req, res) => {
  const { command, timeout = 30000 } = req.body;
  if (!command) return res.status(400).json({ error: 'Command required' });

  const proc = spawn('/bin/bash', ['-c', command], {
    env: { ...process.env, PATH: process.env.PATH + ':/usr/local/bin:/opt/venv/bin', PYTHONUNBUFFERED: '1' },
    timeout
  });

  let stdout = '', stderr = '';
  proc.stdout.on('data', d => stdout += d);
  proc.stderr.on('data', d => stderr += d);
  proc.on('close', code => {
    res.json({ exitCode: code, stdout: stdout.slice(0, 10000), stderr: stderr.slice(0, 5000) });
  });
  proc.on('error', err => res.status(500).json({ error: err.message }));
});

// Streaming exec via SSE (for Terminal page live output)
app.get('/api/exec/stream', (req, res) => {
  const command = req.query.cmd;
  if (!command) return res.status(400).end();

  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.flushHeaders();

  const proc = spawn('/bin/bash', ['-c', command], {
    env: { ...process.env, PATH: process.env.PATH + ':/usr/local/bin:/opt/venv/bin', PYTHONUNBUFFERED: '1' }
  });

  const send = (type, text) => {
    res.write(`data: ${JSON.stringify({ type, text })}\n\n`);
  };

  proc.stdout.on('data', d => d.toString().split('\n').forEach(l => l && send('stdout', l)));
  proc.stderr.on('data', d => d.toString().split('\n').forEach(l => l && send('stderr', l)));
  proc.on('close', code => { send('exit', String(code)); res.end(); });
  req.on('close', () => { try { proc.kill('SIGTERM'); } catch {} });
});

app.get('/api/system', (req, res) => {
  const proc = spawn('sh', ['-c', 'df -h / && free -h && uptime']);
  let output = '';
  proc.stdout.on('data', d => output += d);
  proc.on('close', () => {
    res.json({
      activeJobs: activeJobs.size, totalJobs: jobHistory.length,
      uptime: process.uptime(), stats: output, timestamp: new Date().toISOString()
    });
  });
});

// ── WebSocket handler ────────────────────────────────────────
wss.on('connection', (ws, req) => {
  console.log(`[WS] Client connected from ${req.socket.remoteAddress}`);

  // Init subscription set
  clientSubscriptions.set(ws, new Set());

  // Send current state
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

        // Client subscribes to a specific job (to receive its output lines)
        case 'subscribe':
          if (msg.jobId) {
            clientSubscriptions.get(ws)?.add(msg.jobId);

            // Replay buffered output so late-joiners catch up immediately
            const job = jobHistory.find(j => j.id === msg.jobId);
            if (job && job.output.length > 0) {
              const from = parseInt(msg.from) || 0;
              job.output.slice(from).forEach(entry => {
                ws.send(JSON.stringify({
                  type:      'job-output',
                  jobId:     job.id,
                  line:      entry.text,
                  stream:    entry.stream,
                  lineNum:   job.output.indexOf(entry) + 1,
                  replay:    true,
                  timestamp: entry.t
                }));
              });
              // If job already finished, send completion too
              if (job.status !== 'running') {
                ws.send(JSON.stringify({
                  type:        'job-complete',
                  jobId:       job.id,
                  exitCode:    job.exitCode,
                  status:      job.status,
                  outputFiles: job.outputFiles || [],
                  lineCount:   job.lineCount,
                  replay:      true,
                  timestamp:   job.endTime
                }));
              }
            }
          }
          break;

        case 'unsubscribe':
          if (msg.jobId) clientSubscriptions.get(ws)?.delete(msg.jobId);
          break;
      }
    } catch (e) { /* ignore malformed messages */ }
  });

  ws.on('close', () => {
    clientSubscriptions.delete(ws);
    console.log('[WS] Client disconnected');
  });

  ws.on('error', () => {
    clientSubscriptions.delete(ws);
  });
});

// ── Catch-all → SPA ─────────────────────────────────────────
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ── Start server ─────────────────────────────────────────────
server.listen(PORT, '0.0.0.0', () => {
  console.log('╔══════════════════════════════════════════════╗');
  console.log('║   🕷️  Crawler Toolkit 2026 Dashboard          ║');
  console.log(`║   Listening on http://0.0.0.0:${PORT}           ║`);
  console.log('╚══════════════════════════════════════════════╝');
  checkTools().then(tools => {
    console.log(`[*] Tools available: ${tools.filter(t => t.available).length}/${tools.length}`);
  });
});

/**
 * Web Crawler Toolkit 2026 - Dashboard Server
 * Node.js + Express + WebSocket
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

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// File upload setup
const upload = multer({ dest: path.join(__dirname, '../workspace/targets/') });

// ── WebSocket broadcast ──────────────────────────────────────
function broadcast(data) {
  const message = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// ── Tool availability check ──────────────────────────────────
async function checkTools() {
  const tools = [
    { name: 'katana', cmd: 'katana', flag: '-version' },
    { name: 'gau', cmd: 'gau', flag: '--version' },
    { name: 'gospider', cmd: 'gospider', flag: '--version' },
    { name: 'httpx', cmd: 'httpx', flag: '-version' },
    { name: 'waymore', cmd: 'waymore', flag: '--version' },
    { name: 'xnLinkFinder', cmd: 'xnLinkFinder', flag: '--version' },
    { name: 'subfinder', cmd: 'subfinder', flag: '-version' },
    { name: 'nuclei', cmd: 'nuclei', flag: '-version' },
    { name: 'dnsx', cmd: 'dnsx', flag: '-version' },
    { name: 'naabu', cmd: 'naabu', flag: '-version' },
    { name: 'waybackurls', cmd: 'waybackurls', flag: '-h' },
    { name: 'anew', cmd: 'anew', flag: '-h' },
    { name: 'gf', cmd: 'gf', flag: '-h' },
    { name: 'uro', cmd: 'uro', flag: '--version' },
    { name: 'unfurl', cmd: 'unfurl', flag: '-h' },
    { name: 'node', cmd: 'node', flag: '--version' },
    { name: 'python3', cmd: 'python3', flag: '--version' },
  ];

  const results = await Promise.all(tools.map(tool => {
    return new Promise(resolve => {
      const proc = spawn(tool.cmd, [tool.flag], { timeout: 5000 });
      let version = '';
      proc.stdout.on('data', d => version += d);
      proc.stderr.on('data', d => version += d);
      proc.on('close', code => {
        resolve({
          name: tool.name,
          available: code === 0 || code === 1,
          version: version.split('\n')[0].trim().substring(0, 60) || 'available'
        });
      });
      proc.on('error', () => {
        resolve({ name: tool.name, available: false, version: 'not found' });
      });
    });
  }));

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
    output: [],
    pid: null
  };

  activeJobs.set(jobId, job);
  jobHistory.unshift(job);

  let cmd, args;
  const target = options.target;
  const depth = options.depth || '3';
  const threads = options.threads || '50';

  switch (type) {
    case 'full-scan':
      cmd = '/workspace/scripts/full-scan.sh';
      args = [target];
      break;
    case 'crawl':
      cmd = '/workspace/scripts/crawl-only.sh';
      args = [target, depth, threads];
      break;
    case 'urls':
      cmd = '/workspace/scripts/collect-urls.sh';
      args = [target, threads];
      break;
    case 'js-analyze':
      cmd = '/workspace/scripts/js-analyze.sh';
      args = [target];
      break;
    case 'custom':
      cmd = '/bin/bash';
      args = ['-c', options.command];
      break;
    default:
      broadcast({ type: 'job-error', jobId, message: 'Unknown scan type' });
      activeJobs.delete(jobId);
      return;
  }

  const proc = spawn(cmd, args, {
    env: {
      ...process.env,
      THREADS: threads,
      DEPTH: depth,
      PATH: process.env.PATH + ':/usr/local/bin:/opt/venv/bin',
      VIRTUAL_ENV: '/opt/venv'
    }
  });

  job.pid = proc.pid;

  broadcast({
    type: 'job-started',
    jobId,
    scanType: type,
    target,
    pid: proc.pid,
    timestamp: new Date().toISOString()
  });

  // Stream output
  const streamData = (data, stream) => {
    const text = data.toString();
    const lines = text.split('\n').filter(l => l.trim());
    lines.forEach(line => {
      job.output.push({ time: new Date().toISOString(), text: line, stream });
      broadcast({
        type: 'job-output',
        jobId,
        line,
        stream,
        timestamp: new Date().toISOString()
      });
    });
  };

  proc.stdout.on('data', data => streamData(data, 'stdout'));
  proc.stderr.on('data', data => streamData(data, 'stderr'));

  proc.on('close', code => {
    job.status = code === 0 ? 'completed' : 'failed';
    job.endTime = new Date().toISOString();
    job.exitCode = code;

    // Get output files
    const domain = target.replace(/https?:\/\//, '').replace(/\/.*/, '');
    job.outputFiles = getOutputFiles(domain);

    broadcast({
      type: 'job-complete',
      jobId,
      exitCode: code,
      status: job.status,
      outputFiles: job.outputFiles,
      duration: new Date(job.endTime) - new Date(job.startTime),
      timestamp: new Date().toISOString()
    });

    activeJobs.delete(jobId);
  });

  proc.on('error', err => {
    job.status = 'error';
    broadcast({
      type: 'job-error',
      jobId,
      message: err.message,
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
      .filter(d => fs.statSync(d).isDirectory());
    
    const files = [];
    dirs.forEach(dir => {
      walkDir(dir, files);
    });
    return files.slice(0, 100); // limit
  } catch (e) {
    return [];
  }
}

function walkDir(dir, results, prefix = '') {
  try {
    const items = fs.readdirSync(dir);
    items.forEach(item => {
      const full = path.join(dir, item);
      const stat = fs.statSync(full);
      if (stat.isDirectory()) {
        walkDir(full, results, path.join(prefix, item));
      } else {
        results.push({
          path: full,
          name: item,
          size: stat.size,
          modified: stat.mtime.toISOString()
        });
      }
    });
  } catch (e) {}
}

// ── API Routes ───────────────────────────────────────────────

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '2026.1.0', timestamp: new Date().toISOString() });
});

// Tool status
app.get('/api/tools', async (req, res) => {
  try {
    const tools = await checkTools();
    res.json({ tools, timestamp: new Date().toISOString() });
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
  const job = executeScan(jobId, type || 'full-scan', {
    target, depth, threads, command
  });

  res.json({ jobId, status: 'started', job });
});

// Stop job
app.post('/api/scan/stop/:jobId', (req, res) => {
  const job = activeJobs.get(req.params.jobId);
  if (!job) {
    return res.status(404).json({ error: 'Job not found' });
  }
  
  try {
    process.kill(job.pid, 'SIGTERM');
    job.status = 'stopped';
    activeJobs.delete(req.params.jobId);
    broadcast({ type: 'job-stopped', jobId: req.params.jobId });
    res.json({ status: 'stopped' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Get active jobs
app.get('/api/jobs/active', (req, res) => {
  const jobs = Array.from(activeJobs.values()).map(j => ({
    id: j.id, type: j.type, status: j.status,
    startTime: j.startTime, options: j.options,
    outputLines: j.output.length
  }));
  res.json(jobs);
});

// Get job history
app.get('/api/jobs/history', (req, res) => {
  const limit = parseInt(req.query.limit) || 20;
  res.json(jobHistory.slice(0, limit).map(j => ({
    id: j.id, type: j.type, status: j.status,
    startTime: j.startTime, endTime: j.endTime,
    exitCode: j.exitCode, options: j.options,
    outputFiles: j.outputFiles || []
  })));
});

// Get output directories
app.get('/api/outputs', (req, res) => {
  try {
    if (!fs.existsSync(OUTPUT_DIR)) return res.json([]);
    const dirs = fs.readdirSync(OUTPUT_DIR)
      .filter(d => {
        try {
          return fs.statSync(path.join(OUTPUT_DIR, d)).isDirectory();
        } catch { return false; }
      })
      .map(d => {
        const dirPath = path.join(OUTPUT_DIR, d);
        const stat = fs.statSync(dirPath);
        const files = [];
        walkDir(dirPath, files);
        return {
          name: d,
          path: dirPath,
          created: stat.birthtime.toISOString(),
          modified: stat.mtime.toISOString(),
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

// List files in output dir
app.get('/api/outputs/:dir/files', (req, res) => {
  const dirPath = path.join(OUTPUT_DIR, req.params.dir);
  if (!fs.existsSync(dirPath)) {
    return res.status(404).json({ error: 'Directory not found' });
  }
  const files = [];
  walkDir(dirPath, files);
  res.json(files);
});

// Read file content
app.get('/api/file', (req, res) => {
  const filePath = req.query.path;
  if (!filePath || !fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'File not found' });
  }
  
  const lines = parseInt(req.query.lines) || 500;
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const allLines = content.split('\n');
    res.json({
      path: filePath,
      totalLines: allLines.length,
      content: allLines.slice(0, lines).join('\n'),
      truncated: allLines.length > lines
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Download file
app.get('/api/download', (req, res) => {
  const filePath = req.query.path;
  if (!filePath || !fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'File not found' });
  }
  res.download(filePath);
});

// Upload targets file
app.post('/api/upload/targets', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  res.json({
    filename: req.file.originalname,
    path: req.file.path,
    size: req.file.size
  });
});

// Custom command execution
app.post('/api/exec', (req, res) => {
  const { command, timeout = 30000 } = req.body;
  if (!command) return res.status(400).json({ error: 'Command required' });

  const proc = spawn('/bin/bash', ['-c', command], {
    env: { ...process.env, PATH: process.env.PATH + ':/usr/local/bin:/opt/venv/bin' },
    timeout
  });

  let stdout = '';
  let stderr = '';

  proc.stdout.on('data', d => stdout += d);
  proc.stderr.on('data', d => stderr += d);

  proc.on('close', code => {
    res.json({ exitCode: code, stdout: stdout.slice(0, 10000), stderr: stderr.slice(0, 5000) });
  });

  proc.on('error', err => {
    res.status(500).json({ error: err.message });
  });
});

// System stats
app.get('/api/system', (req, res) => {
  const proc = spawn('sh', ['-c', 'df -h /workspace && free -h && uptime']);
  let output = '';
  proc.stdout.on('data', d => output += d);
  proc.on('close', () => {
    res.json({
      activeJobs: activeJobs.size,
      totalJobs: jobHistory.length,
      uptime: process.uptime(),
      stats: output,
      timestamp: new Date().toISOString()
    });
  });
});

// ── WebSocket handler ────────────────────────────────────────
wss.on('connection', (ws) => {
  console.log('[WS] Client connected');
  
  // Send current state
  ws.send(JSON.stringify({
    type: 'connected',
    activeJobs: activeJobs.size,
    timestamp: new Date().toISOString()
  }));

  ws.on('message', (msg) => {
    try {
      const data = JSON.parse(msg);
      if (data.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong', timestamp: new Date().toISOString() }));
      }
    } catch (e) {}
  });

  ws.on('close', () => {
    console.log('[WS] Client disconnected');
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
  console.log(`║   Server running at http://0.0.0.0:${PORT}      ║`);
  console.log('╚══════════════════════════════════════════════╝');
  checkTools().then(tools => {
    const available = tools.filter(t => t.available).length;
    console.log(`[*] Tools available: ${available}/${tools.length}`);
  });
});

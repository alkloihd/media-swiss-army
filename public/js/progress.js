/**
 * progress.js - WebSocket client for real-time compression progress
 */

import { appState, showNotification, updateCompressButton } from './app.js';
import { updateJobStatus, renderFiles, formatBytes } from './filemanager.js';
import { updateStitchProgress } from './stitch.js';

// ─── Full-Screen Progress Overlay ────────────────────────────────

function showProgressOverlay() {
  if (document.getElementById('progress-overlay')) return;

  const overlay = document.createElement('div');
  overlay.id = 'progress-overlay';
  Object.assign(overlay.style, {
    position: 'fixed',
    top: '0',
    left: '0',
    right: '0',
    bottom: '0',
    zIndex: '90',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    background: '#0a0a1a',
    transition: 'opacity 0.3s',
  });

  const container = document.createElement('div');
  Object.assign(container.style, {
    width: '100%',
    maxWidth: '500px',
    padding: '0 24px',
  });

  // Title
  const title = document.createElement('h2');
  title.id = 'progress-title';
  title.textContent = 'Compressing...';
  title.style.cssText =
    'font-size:24px;font-weight:800;color:var(--text-primary,#e0e0e0);text-align:center;margin-bottom:8px';
  container.appendChild(title);

  // Subtitle (file count)
  const subtitle = document.createElement('p');
  subtitle.id = 'progress-subtitle';
  subtitle.style.cssText =
    'font-size:13px;color:var(--text-muted,#666);text-align:center;margin-bottom:32px';
  container.appendChild(subtitle);

  // Per-file progress list
  const fileList = document.createElement('div');
  fileList.id = 'progress-file-list';
  fileList.style.cssText = 'display:flex;flex-direction:column;gap:16px';
  container.appendChild(fileList);

  overlay.appendChild(container);
  document.body.appendChild(overlay);
  updateProgressOverlay();
}

function updateProgressOverlay() {
  const overlay = document.getElementById('progress-overlay');
  if (!overlay) return;

  const fileList = document.getElementById('progress-file-list');
  const subtitle = document.getElementById('progress-subtitle');
  const title = document.getElementById('progress-title');
  if (!fileList) return;

  const activeFiles = appState.files.filter(
    (f) => f.status === 'compressing' || f.status === 'queued' || f.status === 'done',
  );
  const doneCount = activeFiles.filter((f) => f.status === 'done').length;
  const totalCount = activeFiles.length;

  if (subtitle) {
    subtitle.textContent = doneCount + ' of ' + totalCount + ' files complete';
  }

  fileList.textContent = '';

  for (const file of activeFiles) {
    const job = file.jobId ? appState.activeJobs[file.jobId] : null;
    const pct = file.status === 'done' ? 100 : job ? Math.round(job.progress || 0) : 0;
    const isDone = file.status === 'done';
    const isQueued = file.status === 'queued';

    const row = document.createElement('div');
    Object.assign(row.style, {
      background: 'var(--card-bg, #0f0f23)',
      border:
        '1px solid ' + (isDone ? 'var(--accent-green, #22c55e)' : 'var(--card-border, #1a1a35)'),
      borderRadius: '14px',
      padding: '16px 20px',
      transition: 'border-color 0.3s',
    });
    if (isDone) {
      row.style.boxShadow = '0 0 20px rgba(34,197,94,0.1)';
    }

    // File name + status
    const header = document.createElement('div');
    header.style.cssText =
      'display:flex;justify-content:space-between;align-items:center;margin-bottom:10px';

    const name = document.createElement('span');
    name.textContent = file.name;
    name.style.cssText =
      'font-size:13px;font-weight:600;color:var(--text-primary,#e0e0e0);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:280px';
    header.appendChild(name);

    const status = document.createElement('span');
    if (isDone) {
      status.textContent = '\u2713 Done';
      status.style.cssText = 'font-size:12px;font-weight:700;color:var(--accent-green,#22c55e)';
    } else if (isQueued) {
      status.textContent = 'Queued';
      status.style.cssText = 'font-size:12px;color:var(--text-muted,#666)';
    } else {
      status.textContent = pct + '%';
      status.style.cssText = 'font-size:14px;font-weight:800;color:var(--accent-cyan,#06b6d4)';
    }
    header.appendChild(status);
    row.appendChild(header);

    // Progress bar
    const barTrack = document.createElement('div');
    Object.assign(barTrack.style, {
      height: '10px',
      background: 'var(--progress-track, #1a1a35)',
      borderRadius: '99px',
      overflow: 'hidden',
    });

    const barFill = document.createElement('div');
    Object.assign(barFill.style, {
      width: pct + '%',
      height: '100%',
      borderRadius: '99px',
      transition: 'width 0.5s ease',
      background: isDone
        ? 'var(--accent-green, #22c55e)'
        : isQueued
          ? 'linear-gradient(90deg, #eab308, #fde047, #eab308)'
          : 'linear-gradient(90deg, var(--accent-cyan, #06b6d4), var(--accent-green, #22c55e))',
      boxShadow: isDone ? '0 0 12px rgba(34,197,94,0.4)' : '0 0 8px rgba(6,182,212,0.3)',
    });
    if (isQueued) {
      barFill.style.width = '100%';
      barFill.style.backgroundSize = '200% 100%';
      barFill.style.animation = 'shimmer 2s ease-in-out infinite';
    }
    barTrack.appendChild(barFill);
    row.appendChild(barTrack);

    // Speed / ETA row
    if (!isDone && !isQueued && job) {
      const stats = document.createElement('div');
      stats.style.cssText =
        'display:flex;justify-content:space-between;margin-top:6px;font-size:11px;color:var(--text-muted,#666)';
      const speed = document.createElement('span');
      speed.textContent = job.speed ? job.speed + 'x speed' : '';
      speed.style.color = 'var(--accent-green, #22c55e)';
      const eta = document.createElement('span');
      const parts = [];
      if (job.eta) parts.push('ETA: ' + job.eta + 's');
      if (job.fps) parts.push(job.fps + ' fps');
      eta.textContent = parts.join(' \u00b7 ');
      stats.appendChild(speed);
      stats.appendChild(eta);
      row.appendChild(stats);
    }

    // Done: show size comparison
    if (isDone && file.outputSize && file.size) {
      const comp = document.createElement('div');
      comp.style.cssText =
        'display:flex;justify-content:space-between;margin-top:8px;font-size:11px';
      const before = document.createElement('span');
      before.textContent = formatBytes(file.size) + ' \u2192 ' + formatBytes(file.outputSize);
      before.style.color = 'var(--text-muted, #666)';
      const saved = document.createElement('span');
      const pctSaved = Math.round((1 - file.outputSize / file.size) * 100);
      saved.textContent = pctSaved + '% smaller';
      saved.style.cssText = 'font-weight:700;color:var(--accent-green,#22c55e)';
      comp.appendChild(before);
      comp.appendChild(saved);
      row.appendChild(comp);
    }

    fileList.appendChild(row);
  }
}

function hideProgressOverlay() {
  const overlay = document.getElementById('progress-overlay');
  if (overlay) {
    overlay.style.opacity = '0';
    setTimeout(() => overlay.remove(), 300);
  }
}

function showCompletionBanner() {
  const old = document.getElementById('completion-banner');
  if (old) old.remove();

  const doneFiles = appState.files.filter((f) => f.status === 'done');
  const totalOrig = doneFiles.reduce((s, f) => s + (f.size || 0), 0);
  const totalComp = doneFiles.reduce((s, f) => s + (f.outputSize || 0), 0);
  const savedPct = totalOrig > 0 ? Math.round((1 - totalComp / totalOrig) * 100) : 0;

  const banner = document.createElement('div');
  banner.id = 'completion-banner';
  Object.assign(banner.style, {
    position: 'fixed',
    top: '0',
    left: '0',
    right: '0',
    bottom: '0',
    zIndex: '100',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: 'rgba(0,0,0,0.7)',
    backdropFilter: 'blur(8px)',
  });

  const card = document.createElement('div');
  Object.assign(card.style, {
    background: 'var(--card-bg, #0f0f23)',
    border: '1px solid var(--accent-green, #22c55e)',
    borderRadius: '20px',
    padding: '40px 50px',
    textAlign: 'center',
    maxWidth: '480px',
    boxShadow: '0 0 60px rgba(34,197,94,0.3)',
  });

  const check = document.createElement('div');
  check.textContent = '\u2713';
  check.style.cssText = 'font-size:48px;margin-bottom:12px;color:var(--accent-green,#22c55e)';
  card.appendChild(check);

  const title = document.createElement('h2');
  title.textContent = 'Compression Complete!';
  title.style.cssText =
    'font-size:24px;font-weight:800;color:var(--accent-green,#22c55e);margin-bottom:8px';
  card.appendChild(title);

  const sub = document.createElement('p');
  sub.textContent =
    doneFiles.length + ' file' + (doneFiles.length !== 1 ? 's' : '') + ' compressed';
  sub.style.cssText = 'font-size:14px;color:var(--text-secondary,#888);margin-bottom:20px';
  card.appendChild(sub);

  const stats = document.createElement('div');
  stats.style.cssText =
    'display:flex;gap:16px;justify-content:center;margin-bottom:24px;padding:16px;background:rgba(34,197,94,0.08);border-radius:12px';
  const makeStatBlock = (label, value, color) => {
    const d = document.createElement('div');
    d.style.textAlign = 'center';
    const l = document.createElement('div');
    l.textContent = label;
    l.style.cssText =
      'font-size:11px;color:var(--text-muted,#666);text-transform:uppercase;letter-spacing:1px';
    const v = document.createElement('div');
    v.textContent = value;
    v.style.cssText = 'font-size:20px;font-weight:700;color:' + color;
    d.appendChild(l);
    d.appendChild(v);
    return d;
  };
  stats.appendChild(makeStatBlock('Before', formatBytes(totalOrig), 'var(--text-primary,#e0e0e0)'));
  const arrow = document.createElement('div');
  arrow.textContent = '\u2192';
  arrow.style.cssText =
    'display:flex;align-items:center;font-size:20px;color:var(--accent-green,#22c55e)';
  stats.appendChild(arrow);
  stats.appendChild(makeStatBlock('After', formatBytes(totalComp), 'var(--accent-green,#22c55e)'));
  stats.appendChild(makeStatBlock('Saved', savedPct + '%', 'var(--accent-green,#22c55e)'));
  card.appendChild(stats);

  const loc = document.createElement('p');
  loc.textContent = 'Saved to: ~/Movies/Video Compressor Output/';
  loc.style.cssText = 'font-size:12px;color:var(--text-muted,#666);margin-bottom:20px';
  card.appendChild(loc);

  const btn = document.createElement('button');
  btn.textContent = 'Got it';
  btn.style.cssText =
    'padding:12px 32px;border-radius:99px;border:none;background:var(--accent-green,#22c55e);color:#000;font-weight:700;font-size:14px;cursor:pointer';
  btn.addEventListener('click', () => banner.remove());
  card.appendChild(btn);

  banner.appendChild(card);
  banner.addEventListener('click', (e) => {
    if (e.target === banner) banner.remove();
  });
  document.body.appendChild(banner);
}

let ws = null;
let reconnectTimer = null;
let reconnectDelay = 1000;
const MAX_RECONNECT_DELAY = 30000;

function getWSUrl() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${window.location.host}`;
}

function handleMessage(data) {
  switch (data.type) {
    case 'progress': {
      const job = appState.activeJobs[data.jobId];
      if (job) {
        job.progress = data.percent || 0;
        job.speed = data.speed || null;
        job.eta = data.eta || null;
        job.fps = data.fps || null;
        job.status = 'compressing';

        const file = appState.files.find((f) => f.jobId === data.jobId);
        if (file) {
          file.status = 'compressing';
        }

        updateJobStatus(data.jobId, {
          type: 'progress',
          percent: job.progress,
          speed: job.speed,
          eta: job.eta,
          fps: job.fps,
        });

        // Update the full-screen progress overlay
        updateProgressOverlay();
      }
      // Forward to stitch progress handler
      updateStitchProgress(data.jobId, data);
      break;
    }

    case 'complete': {
      const job = appState.activeJobs[data.jobId];
      if (job) {
        job.status = 'done';
        job.progress = 100;

        const file = appState.files.find((f) => f.jobId === data.jobId);
        if (file) {
          file.status = 'done';
          file.outputPath = data.outputPath;
          file.outputSize = data.outputSize;
        }

        updateJobStatus(data.jobId, {
          type: 'complete',
          outputPath: data.outputPath,
          outputSize: data.outputSize,
          duration: data.duration,
        });

        delete appState.activeJobs[data.jobId];

        const fileName = file ? file.name : 'File';
        showNotification(`${fileName} compressed successfully!`, 'success');
        updateCompressButton();
        renderFiles();

        // Update overlay
        updateProgressOverlay();

        // Check if ALL jobs are done — transition to completion banner
        if (Object.keys(appState.activeJobs).length === 0) {
          hideProgressOverlay();
          setTimeout(() => showCompletionBanner(), 350);
        }
      }
      // Forward to stitch progress handler
      updateStitchProgress(data.jobId, data);
      break;
    }

    case 'error': {
      const job = appState.activeJobs[data.jobId];
      if (job) {
        job.status = 'error';

        const file = appState.files.find((f) => f.jobId === data.jobId);
        if (file) {
          file.status = 'error';
          file.error = data.error || 'Compression failed';
        }

        updateJobStatus(data.jobId, {
          type: 'error',
          error: data.error || 'Compression failed',
        });

        delete appState.activeJobs[data.jobId];

        const fileName = file ? file.name : 'File';
        showNotification(`${fileName} failed: ${data.error || 'Unknown error'}`, 'error');
        updateCompressButton();
        renderFiles();
      }
      // Forward to stitch progress handler
      updateStitchProgress(data.jobId, data);
      break;
    }

    case 'queued': {
      const file = appState.files.find((f) => f.jobId === data.jobId);
      if (file) {
        file.status = 'queued';
      }

      const job = appState.activeJobs[data.jobId];
      if (job) {
        job.status = 'queued';
      }

      updateJobStatus(data.jobId, {
        type: 'queued',
        position: data.position,
      });
      renderFiles();
      break;
    }

    case 'metaclean-complete':
    case 'metaclean-error':
      // Handled inline by metaclean.js via fetch response
      break;

    default:
      break;
  }
}

async function reconcileMissedJobs() {
  if (Object.keys(appState.activeJobs).length === 0) return;

  try {
    const res = await fetch('/api/jobs');
    const { jobs } = await res.json();
    const serverJobs = new Map(jobs.map((j) => [j.id, j]));

    for (const jobId of Object.keys(appState.activeJobs)) {
      const server = serverJobs.get(jobId);
      if (!server) continue;

      if (server.status === 'complete') {
        handleMessage({
          type: 'complete',
          jobId,
          outputPath: server.outputPath,
          outputSize: server.compressedSize,
        });
      } else if (server.status === 'error') {
        handleMessage({
          type: 'error',
          jobId,
          error: 'Compression failed',
        });
      }
    }
  } catch {
    // Will retry on next reconnect
  }
}

function connect() {
  const url = getWSUrl();

  try {
    ws = new WebSocket(url);
  } catch (err) {
    scheduleReconnect();
    return;
  }

  ws.onopen = () => {
    appState.wsConnected = true;
    reconnectDelay = 1000;

    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }

    reconcileMissedJobs();
  };

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      handleMessage(data);
    } catch {
      // Ignore non-JSON messages
    }
  };

  ws.onclose = () => {
    appState.wsConnected = false;
    ws = null;
    scheduleReconnect();
  };

  ws.onerror = () => {
    appState.wsConnected = false;
    if (ws) {
      try {
        ws.close();
      } catch {
        /* ignore */
      }
    }
  };
}

function scheduleReconnect() {
  if (reconnectTimer) return;

  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
    // Exponential backoff
    reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY);
  }, reconnectDelay);
}

export { showProgressOverlay };

export function initProgress() {
  connect();
}

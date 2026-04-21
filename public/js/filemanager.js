/**
 * filemanager.js - File card rendering and job status updates
 */

import { appState, selectFile, removeFile } from './app.js';

// ─── Helpers ─────────────────────────────────────────────────────
export function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  const val = bytes / Math.pow(1024, i);
  return `${val.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

export function formatDuration(seconds) {
  if (!seconds || seconds < 0) return '0:00';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) {
    return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }
  return `${m}:${String(s).padStart(2, '0')}`;
}

// ─── Status Badge HTML ───────────────────────────────────────────
function statusBadgeHTML(status) {
  const map = {
    uploading: '<span class="status-badge status-uploading">Uploading</span>',
    pending: '<span class="status-badge status-pending">Ready</span>',
    queued: '<span class="status-badge status-queued">Queued</span>',
    compressing: '<span class="status-badge status-compressing">Compressing</span>',
    done: '<span class="status-badge status-done">Done</span>',
    error: '<span class="status-badge status-error">Error</span>',
  };
  return map[status] || map.pending;
}

// ─── Thumbnail HTML ──────────────────────────────────────────────
function thumbnailHTML(file) {
  if (file.serverPath) {
    const thumbUrl = `/api/thumbnail?path=${encodeURIComponent(file.serverPath)}&t=${Date.now()}`;
    return `<img class="file-card-thumb" src="${thumbUrl}" alt="" loading="lazy" onerror="this.parentElement.innerHTML='<div class=\\'file-card-thumb-placeholder\\'><svg fill=\\'none\\' stroke=\\'currentColor\\' viewBox=\\'0 0 24 24\\' stroke-width=\\'1.5\\'><path stroke-linecap=\\'round\\' stroke-linejoin=\\'round\\' d=\\'M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9A2.25 2.25 0 0013.5 5.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z\\'/></svg></div>'" />`;
  }

  return `<div class="file-card-thumb-placeholder">
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="1.5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9A2.25 2.25 0 0013.5 5.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z" />
    </svg>
  </div>`;
}

// ─── Metadata HTML ───────────────────────────────────────────────
function metaHTML(file) {
  if (!file.probeData) return '';

  const probe = file.probeData;
  const parts = [];

  if (probe.width && probe.height) {
    parts.push(`${probe.width}x${probe.height}`);
  }
  if (probe.codec) {
    parts.push(probe.codec.toUpperCase());
  }
  if (probe.duration) {
    parts.push(formatDuration(probe.duration));
  }

  if (parts.length === 0) return '';
  return `<span class="file-card-meta">${parts.join(' &middot; ')}</span>`;
}

// ─── Resolution Options ─────────────────────────────────────────
const RESOLUTION_PRESETS = [
  { label: 'Original', value: 'original', height: 0 },
  { label: '1080p', value: '1080p', height: 1080 },
  { label: '720p', value: '720p', height: 720 },
  { label: '480p', value: '480p', height: 480 },
  { label: '360p', value: '360p', height: 360 },
];

function resolutionSelectHTML(file) {
  // Only show for pending or uploading status
  if (!file.probeData || !['pending', 'uploading'].includes(file.status)) return '';

  const sourceHeight = file.probeData.height || 0;
  if (sourceHeight <= 0) return '';

  // Initialize scale property if not set
  if (!file.scale) file.scale = 'original';

  // Build options: always include "Original", then only presets smaller than source
  const options = RESOLUTION_PRESETS.filter(
    (preset) => preset.value === 'original' || preset.height < sourceHeight,
  );

  // If only "Original" is available, don't show dropdown
  if (options.length <= 1) return '';

  const optionTags = options
    .map((opt) => {
      const selected = file.scale === opt.value ? ' selected' : '';
      return `<option value="${opt.value}"${selected}>${opt.label}</option>`;
    })
    .join('');

  return `
    <div class="file-card-resolution" style="margin-top: 4px; display: flex; align-items: center; gap: 6px;">
      <span style="font-size: 11px; color: var(--text-muted);">Resolution:</span>
      <select
        class="resolution-select"
        data-file-id="${file.id}"
        style="
          background: var(--input-bg);
          border: 2px solid var(--input-border);
          color: var(--input-text);
          padding: 2px 8px;
          border-radius: 4px;
          font-size: 12px;
          cursor: pointer;
          outline: none;
          appearance: auto;
          -webkit-appearance: auto;
        "
      >${optionTags}</select>
    </div>
  `;
}

// ─── Build File Card ─────────────────────────────────────────────
function buildFileCard(file) {
  const isSelected = appState.selectedFileId === file.id;
  const isDone = file.status === 'done';
  const isError = file.status === 'error';

  let cardClasses = 'file-card';
  if (isSelected) cardClasses += ' selected';
  if (isDone) cardClasses += ' file-card-done';
  if (isError) cardClasses += ' file-card-error-state';

  let progressHTML = '';
  if (file.status === 'compressing' && file.jobId) {
    const job = appState.activeJobs[file.jobId];
    const pct = job ? Math.round(job.progress) : 0;
    const speedText = job?.speed || '';
    const etaText = job?.eta ? `ETA: ${job.eta}` : '';
    const fpsText = job?.fps ? `${job.fps} fps` : '';
    const statsRight = [etaText, fpsText].filter(Boolean).join(' \u00b7 ');
    progressHTML = `
      <div class="file-card-progress" id="progress-${file.jobId}">
        <div class="progress-bar" style="height: 8px; background: var(--progress-track); border-radius: 4px; overflow: hidden; position: relative;">
          <div class="progress-bar-fill" style="width: ${pct}%; height: 100%; border-radius: 4px; transition: width 0.4s ease;"></div>
          <span class="progress-pct-label" style="
            position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
            font-size: 7px; font-weight: 700; color: var(--text-primary); text-shadow: 0 1px 2px rgba(0,0,0,0.6);
            pointer-events: none; line-height: 1;
          ">${pct}%</span>
        </div>
        <div class="progress-stats" style="display: flex; justify-content: space-between; margin-top: 4px; font-size: 11px;">
          <span class="progress-speed" style="color: var(--progress-speed); font-weight: 500;">${speedText || '--'}</span>
          <span class="progress-eta" style="color: var(--progress-eta);">${pct}%${statsRight ? ' \u00b7 ' + statsRight : ''}</span>
        </div>
      </div>
    `;
  } else if (file.status === 'queued') {
    progressHTML = `
      <div class="file-card-progress" id="progress-queued-${file.id}">
        <div class="progress-bar" style="height: 8px; background: var(--progress-track); border-radius: 4px; overflow: hidden; position: relative;">
          <div class="progress-bar-fill" style="width: 0%; height: 100%; border-radius: 4px; background: linear-gradient(90deg, #eab308, #fde047, #eab308); background-size: 200% 100%; animation: shimmer 2s ease-in-out infinite;"></div>
          <span class="progress-pct-label" style="
            position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
            font-size: 7px; font-weight: 700; color: var(--status-queued-text); text-shadow: 0 1px 2px rgba(0,0,0,0.6);
            pointer-events: none; line-height: 1;
          ">Queued</span>
        </div>
        <div class="progress-stats" style="display: flex; justify-content: center; margin-top: 4px; font-size: 11px;">
          <span style="color: var(--status-queued-text);">Waiting to start...</span>
        </div>
      </div>
    `;
  }

  let sizeComparisonHTML = '';
  if (isDone && file.outputSize && file.size) {
    const originalSize = file.size;
    const compressedSize = file.outputSize;
    const reduction = originalSize > 0 ? ((1 - compressedSize / originalSize) * 100).toFixed(1) : 0;
    sizeComparisonHTML = `
      <div class="file-card-size-comparison">
        <span class="size-original">${formatBytes(originalSize)}</span>
        <span class="size-arrow">&rarr;</span>
        <span class="size-compressed">${formatBytes(compressedSize)}</span>
        <span class="size-reduction">-${reduction}%</span>
      </div>
    `;
  }

  let downloadHTML = '';
  if (isDone && file.outputPath) {
    downloadHTML = `
      <a href="/api/download?path=${encodeURIComponent(file.outputPath)}"
         class="file-card-download"
         style="display: inline-flex; align-items: center; gap: 4px; margin-top: 6px; padding: 4px 10px; font-size: 11px; font-weight: 600; color: var(--accent-primary); background: var(--accent-bg-10); border: 2px solid var(--accent-border-25); border-radius: 4px; text-decoration: none; font-family: 'SF Mono', 'Fira Code', 'JetBrains Mono', monospace; text-transform: uppercase; letter-spacing: 0.05em;"
         onclick="event.stopPropagation();"
         title="Download compressed file">
        <svg style="width:12px;height:12px;" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
        </svg>
        Download
      </a>
    `;
  }

  let errorHTML = '';
  if (isError && file.error) {
    errorHTML = `<div class="file-card-error">${file.error}</div>`;
  }

  return `
    <div class="${cardClasses}" data-file-id="${file.id}">
      <div class="file-card-thumbnail">
        ${thumbnailHTML(file)}
      </div>
      <div class="file-card-info">
        <div class="file-card-header">
          <span class="file-card-name" title="${file.name}">${file.name}</span>
          <div class="file-card-actions">
            ${statusBadgeHTML(file.status)}
            <button class="file-card-remove" data-remove-id="${file.id}" title="Remove">&times;</button>
          </div>
        </div>
        <div class="file-card-details">
          <span class="file-card-size">${file.size > 0 ? formatBytes(file.size) : ''}</span>
          ${metaHTML(file)}
        </div>
        ${resolutionSelectHTML(file)}
        ${progressHTML}
        ${sizeComparisonHTML}
        ${downloadHTML}
        ${errorHTML}
      </div>
    </div>
  `;
}

// ─── Render All Files ────────────────────────────────────────────
export function renderFiles() {
  const container = document.getElementById('file-cards-container');
  const header = document.getElementById('file-queue-header');
  const empty = document.getElementById('file-queue-empty');
  const countEl = document.getElementById('file-count');

  if (!container) return;

  const files = appState.files;

  // Toggle visibility
  if (files.length > 0) {
    if (header) header.classList.remove('hidden');
    if (empty) empty.classList.add('hidden');
    if (countEl) countEl.textContent = `(${files.length})`;
  } else {
    if (header) header.classList.add('hidden');
    if (empty) empty.classList.remove('hidden');
    if (countEl) countEl.textContent = '(0)';
  }

  // Build cards HTML
  container.innerHTML = files.map((f) => buildFileCard(f)).join('');

  // Wire click handlers
  container.querySelectorAll('.file-card').forEach((card) => {
    const fileId = card.dataset.fileId;

    card.addEventListener('click', (e) => {
      // Don't select if clicking remove button
      if (e.target.closest('.file-card-remove')) return;
      selectFile(fileId);
    });
  });

  container.querySelectorAll('.file-card-remove').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const id = btn.dataset.removeId;
      if (id) removeFile(id);
    });
  });

  // Wire resolution dropdown change handlers
  container.querySelectorAll('.resolution-select').forEach((select) => {
    select.addEventListener('click', (e) => {
      e.stopPropagation(); // Prevent card selection when interacting with dropdown
    });
    select.addEventListener('change', (e) => {
      e.stopPropagation();
      const fileId = select.dataset.fileId;
      const file = appState.files.find((f) => f.id === fileId);
      if (file) {
        file.scale = select.value;
      }
    });
  });

  // Update compress button state
  updateCompressBtnState();
}

// ─── Update Job Status ───────────────────────────────────────────
export function updateJobStatus(jobId, data) {
  switch (data.type) {
    case 'progress': {
      const progressEl = document.getElementById(`progress-${jobId}`);
      if (progressEl) {
        const fill = progressEl.querySelector('.progress-bar-fill');
        const speedEl = progressEl.querySelector('.progress-speed');
        const etaEl = progressEl.querySelector('.progress-eta');
        const pctLabel = progressEl.querySelector('.progress-pct-label');
        const pct = Math.round(data.percent);

        if (fill) fill.style.width = `${pct}%`;
        if (pctLabel) pctLabel.textContent = `${pct}%`;
        if (speedEl) speedEl.textContent = data.speed || '--';
        if (etaEl) {
          const parts = [`${pct}%`];
          if (data.eta) parts.push(`ETA: ${data.eta}`);
          if (data.fps) parts.push(`${data.fps} fps`);
          etaEl.textContent = parts.join(' \u00b7 ');
        }
      } else {
        // Re-render to create progress UI
        renderFiles();
      }
      break;
    }

    case 'complete': {
      const file = appState.files.find((f) => f.jobId === jobId);
      if (file) {
        file.status = 'done';
        file.outputPath = data.outputPath;
        file.outputSize = data.outputSize;
      }
      renderFiles();
      break;
    }

    case 'error': {
      const file = appState.files.find((f) => f.jobId === jobId);
      if (file) {
        file.status = 'error';
        file.error = data.error;
      }
      renderFiles();
      break;
    }

    case 'queued': {
      // Already handled in progress.js, just re-render
      renderFiles();
      break;
    }

    default:
      break;
  }
}

// ─── Compress Button State ───────────────────────────────────────
function updateCompressBtnState() {
  const compressBtn = document.getElementById('compress-btn');
  if (!compressBtn) return;

  const pendingCount = appState.files.filter((f) => f.status === 'pending').length;
  const compressingCount = appState.files.filter(
    (f) => f.status === 'compressing' || f.status === 'queued',
  ).length;

  if (compressingCount > 0) {
    compressBtn.disabled = true;
    compressBtn.innerHTML = `
      <svg class="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg>
      Compressing (${compressingCount})...
    `;
  } else if (pendingCount > 0) {
    compressBtn.disabled = false;
    compressBtn.innerHTML = `
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 4.5h14.25M3 9h9.75M3 13.5h9.75m4.5-4.5v12m0 0l-3.75-3.75M17.25 21l3.75-3.75" /></svg>
      Compress All (${pendingCount})
    `;
  } else {
    compressBtn.disabled = true;
    compressBtn.innerHTML = `
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 4.5h14.25M3 9h9.75M3 13.5h9.75m4.5-4.5v12m0 0l-3.75-3.75M17.25 21l3.75-3.75" /></svg>
      Compress All
    `;
  }
}

// ─── Init ────────────────────────────────────────────────────────
export function initFileManager() {
  renderFiles();
}

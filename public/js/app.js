/**
 * app.js - Main orchestration module for Video Compressor
 *
 * Note: This module uses innerHTML in showNotification for rendering trusted,
 * application-controlled SVG icons. No user-generated content is injected.
 */

import { initTabs } from './tabs.js';
import { initDragDrop } from './dragdrop.js';
import { initPlayer, loadVideo, destroyPlayer } from './player.js';
import { initTrim, setDuration, getTrimSettings, resetTrim } from './trim.js';
import { initCrop, setVideoSize, getCropSettings } from './crop.js';
import {
  initCompression,
  getCompressionSettings,
  updateResolutionOptions,
  updateEstimation,
} from './compression.js';
import { initProgress, showProgressOverlay } from './progress.js';
import { initFileManager, renderFiles, formatBytes, formatDuration } from './filemanager.js';
import { initMetaClean } from './metaclean.js';
import { initStitch } from './stitch.js';

// ─── Application State ───────────────────────────────────────────
export const appState = {
  files: [], // Array of { id, name, size, path, serverPath, probeData, status, jobId, uploadProgress }
  selectedFileId: null,
  activeJobs: {}, // { jobId: { fileId, progress, speed, eta, status } }
  hwInfo: null,
  wsConnected: false,
};

// ─── Add Files to Queue ──────────────────────────────────────────
export async function addFilesToQueue(fileList) {
  const files = Array.from(fileList);
  if (files.length === 0) return;

  for (const file of files) {
    const id = `file-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const entry = {
      id,
      name: file.name,
      size: file.size,
      path: null,
      serverPath: null,
      probeData: null,
      status: 'uploading',
      jobId: null,
      uploadProgress: 0,
    };
    appState.files.push(entry);
    renderFiles();

    try {
      // Upload via FormData
      const formData = new FormData();
      formData.append('file', file);

      const uploadRes = await fetch('/api/upload', {
        method: 'POST',
        body: formData,
      });

      if (!uploadRes.ok) {
        const err = await uploadRes.json().catch(() => ({ error: 'Upload failed' }));
        throw new Error(err.error || 'Upload failed');
      }

      const uploadData = await uploadRes.json();
      const uploaded = uploadData.files[0];
      entry.serverPath = uploaded.path;
      entry.path = uploaded.name || file.name;

      // Probe the uploaded file
      const probeRes = await fetch(`/api/probe?path=${encodeURIComponent(entry.serverPath)}`);

      if (probeRes.ok) {
        entry.probeData = await probeRes.json();
      }

      entry.status = 'pending';
      entry.uploadProgress = 100;
    } catch (err) {
      entry.status = 'error';
      entry.error = err.message;
      showNotification(`Failed to add ${file.name}: ${err.message}`, 'error');
    }

    renderFiles();
  }

  // Auto-select first file if none selected
  if (!appState.selectedFileId && appState.files.length > 0) {
    const first = appState.files.find((f) => f.status !== 'error');
    if (first) selectFile(first.id);
  }

  updateCompressButton();
}

// ─── Add File by Path ────────────────────────────────────────────
export async function addFileByPath(filePath) {
  const trimmedPath = filePath.trim();
  if (!trimmedPath) return;

  const id = `file-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const name = trimmedPath.split('/').pop() || trimmedPath.split('\\').pop() || trimmedPath;

  const entry = {
    id,
    name,
    size: 0,
    path: trimmedPath,
    serverPath: trimmedPath,
    probeData: null,
    status: 'uploading',
    jobId: null,
    uploadProgress: 0,
  };
  appState.files.push(entry);
  renderFiles();

  try {
    const probeRes = await fetch(`/api/probe?path=${encodeURIComponent(trimmedPath)}`);

    if (!probeRes.ok) {
      const err = await probeRes.json().catch(() => ({ error: 'Probe failed' }));
      throw new Error(err.error || 'Could not probe file');
    }

    const probeData = await probeRes.json();
    entry.probeData = probeData;
    entry.size = probeData.size || 0;
    entry.status = 'pending';
    entry.uploadProgress = 100;
  } catch (err) {
    entry.status = 'error';
    entry.error = err.message;
    showNotification(`Failed to add path: ${err.message}`, 'error');
  }

  renderFiles();

  if (!appState.selectedFileId) {
    const first = appState.files.find((f) => f.status !== 'error');
    if (first) selectFile(first.id);
  }

  updateCompressButton();
}

// ─── Select File ─────────────────────────────────────────────────
export function selectFile(fileId) {
  appState.selectedFileId = fileId;
  const file = appState.files.find((f) => f.id === fileId);
  renderFiles();

  if (!file) return;

  // Load preview
  if (file.serverPath) {
    const previewUrl = `/api/stream?path=${encodeURIComponent(file.serverPath)}`;
    loadVideo(previewUrl);
  }

  // Update info panel
  if (file.probeData) {
    const probe = file.probeData;

    const previewSection = document.getElementById('preview-section');
    const videoInfo = document.getElementById('video-info');
    previewSection.classList.remove('hidden');
    videoInfo.classList.remove('hidden');

    document.getElementById('info-duration').textContent = probe.duration
      ? formatDuration(probe.duration)
      : '--:--';
    document.getElementById('info-resolution').textContent =
      probe.width && probe.height ? `${probe.width}x${probe.height}` : '----';
    document.getElementById('info-codec').textContent = probe.codec?.toUpperCase() || '----';
    document.getElementById('info-size').textContent = probe.size
      ? formatBytes(probe.size)
      : '----';

    // Set trim duration
    if (probe.duration) {
      setDuration(probe.duration);
    }

    // Set crop reference size
    if (probe.width && probe.height) {
      setVideoSize(probe.width, probe.height);
    }
  }

  // Update resolution dropdown and estimation for the newly selected file
  updateResolutionOptions();
  updateEstimation();
}

// ─── Remove File ─────────────────────────────────────────────────
export function removeFile(fileId) {
  const idx = appState.files.findIndex((f) => f.id === fileId);
  if (idx === -1) return;

  appState.files.splice(idx, 1);

  if (appState.selectedFileId === fileId) {
    appState.selectedFileId = null;
    if (appState.files.length > 0) {
      selectFile(appState.files[0].id);
    } else {
      document.getElementById('preview-section').classList.add('hidden');
      destroyPlayer();
      resetTrim();
    }
  }

  renderFiles();
  updateCompressButton();
}

// ─── Clear All Files ─────────────────────────────────────────────
export function clearAllFiles() {
  appState.files = [];
  appState.selectedFileId = null;
  document.getElementById('preview-section').classList.add('hidden');
  destroyPlayer();
  resetTrim();
  renderFiles();
  updateCompressButton();
}

// ─── Compress All ────────────────────────────────────────────────
export async function compressAll() {
  const pendingFiles = appState.files.filter((f) => f.status === 'pending');
  if (pendingFiles.length === 0) {
    showNotification('No files ready for compression', 'warning');
    return;
  }

  const settings = getCompressionSettings();
  const trimSettings = getTrimSettings();
  const cropSettings = getCropSettings();

  const compressBtn = document.getElementById('compress-btn');
  compressBtn.disabled = true;

  // Set all files to queued first
  for (const file of pendingFiles) {
    file.status = 'queued';
  }
  renderFiles();

  // Now show overlay (files are queued so they'll appear)
  showProgressOverlay();

  for (const file of pendingFiles) {
    try {
      const body = {
        files: [{ path: file.serverPath, name: file.name }],
        preset: settings.preset,
        codec: settings.codec,
        format: settings.format,
        scale: file.scale || settings.scale,
        audioBitrate: settings.audioBitrate,
        audioCodec: settings.audioCodec,
        fps: settings.fps,
        twoPass: settings.twoPass,
        preserveMetadata: settings.preserveMetadata,
        fastStart: settings.fastStart,
      };

      // Pass custom preset parameters when applicable
      if (settings.crf !== undefined) body.crf = settings.crf;
      if (settings.speed !== undefined) body.speed = settings.speed;

      if (trimSettings) {
        body.trim = trimSettings;
      }
      if (cropSettings) {
        body.crop = cropSettings;
      }

      const res = await fetch('/api/compress', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: 'Compression request failed' }));
        throw new Error(err.error || 'Compression request failed');
      }

      const data = await res.json();
      const job = data.jobs[0];
      file.jobId = job.id;
      file.status = 'compressing';
      appState.activeJobs[job.id] = {
        fileId: file.id,
        progress: 0,
        speed: null,
        eta: null,
        status: 'compressing',
      };

      renderFiles();
      document.getElementById('jobs-section').classList.remove('hidden');
    } catch (err) {
      file.status = 'error';
      file.error = err.message;
      showNotification(`Compression failed for ${file.name}: ${err.message}`, 'error');
      renderFiles();
    }
  }
}

// ─── Update Compress Button ──────────────────────────────────────
export function updateCompressButton() {
  const compressBtn = document.getElementById('compress-btn');
  const pendingCount = appState.files.filter((f) => f.status === 'pending').length;
  compressBtn.disabled = pendingCount === 0;

  if (pendingCount > 0) {
    // Clear text nodes, keep SVG
    Array.from(compressBtn.childNodes).forEach((node) => {
      if (node.nodeType === 3) node.remove(); // TEXT_NODE = 3
    });
    compressBtn.appendChild(document.createTextNode(` Compress All (${pendingCount})`));
  }
}

// ─── Show Notification ───────────────────────────────────────────
export function showNotification(message, type = 'info', duration = 4000) {
  const container = document.getElementById('notifications');
  const el = document.createElement('div');
  el.className = `notification notification-${type}`;

  // Create icon element using DOM methods
  const iconSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  iconSvg.setAttribute('class', 'w-4 h-4 flex-shrink-0');
  iconSvg.setAttribute('fill', 'none');
  iconSvg.setAttribute('stroke', 'currentColor');
  iconSvg.setAttribute('viewBox', '0 0 24 24');
  iconSvg.setAttribute('stroke-width', '2');

  const iconPath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  iconPath.setAttribute('stroke-linecap', 'round');
  iconPath.setAttribute('stroke-linejoin', 'round');

  const pathData = {
    info: 'M11.25 11.25l.041-.02a.75.75 0 011.063.852l-.708 2.836a.75.75 0 001.063.853l.041-.021M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9-3.75h.008v.008H12V8.25z',
    warning:
      'M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z',
    error: 'M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z',
    success: 'M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
  };

  iconPath.setAttribute('d', pathData[type] || pathData.info);
  iconSvg.appendChild(iconPath);
  el.appendChild(iconSvg);

  const textSpan = document.createElement('span');
  textSpan.textContent = message;
  el.appendChild(textSpan);

  container.appendChild(el);

  setTimeout(() => {
    el.classList.add('notification-fade');
    setTimeout(() => el.remove(), 400);
  }, duration);
}

// ─── Initialization ──────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', async () => {
  // Detect hardware capabilities
  try {
    const hwRes = await fetch('/api/hwaccel');
    if (hwRes.ok) {
      appState.hwInfo = await hwRes.json();
    }
  } catch {
    appState.hwInfo = null;
  }

  // Initialize tab navigation
  initTabs();

  // Initialize all modules
  initDragDrop();
  initPlayer();
  initTrim();
  initCrop();
  initCompression(appState.hwInfo);
  initProgress();
  initFileManager();
  initMetaClean();
  initStitch();

  // Wire clear-all button
  const clearBtn = document.getElementById('clear-queue-btn');
  if (clearBtn) {
    clearBtn.addEventListener('click', clearAllFiles);
  }

  // Wire compress button
  const compressBtn = document.getElementById('compress-btn');
  if (compressBtn) {
    compressBtn.addEventListener('click', compressAll);
  }
});

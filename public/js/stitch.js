/**
 * stitch.js - Visual timeline UI for video stitching
 *
 * Renders clips as proportional blocks on a horizontal timeline with:
 * - Thumbnail strip backgrounds
 * - Drag-to-reorder (SortableJS)
 * - Trim handles (interact.js resizable)
 * - Time ruler with tick marks
 *
 * Note: innerHTML usage is for application-controlled content only (status
 * messages, formatBytes output, download links with encoded paths). No
 * user-generated content is injected unsanitized.
 */
/* global interact */

import { showNotification } from './app.js';
import { formatBytes, formatDuration } from './filemanager.js';
import { loadVideo } from './player.js';
import { loadInteract } from './timeline-deps.js';

// ─── State ──────────────────────────────────────────────────────
let clips = [];
let stitchCompress = false;
let stitchPreset = 'balanced';
let stitchCodec = 'h265';
let stitchFormat = 'mp4';
let sortableInstance = null;
let interactReady = false;

const PX_PER_SECOND = 10; // pixels per second of duration
const MIN_CLIP_PX = 80; // minimum clip width
const TRIM_HANDLE_W = 6; // trim handle width in px
const MIN_TRIMMED_PX = 40; // minimum width after trimming
const THUMB_COUNT = 5; // thumbnails per clip
const THUMB_WIDTH = 80; // thumbnail request width

// ─── Styles (injected once) ─────────────────────────────────────
function injectTimelineStyles() {
  if (document.getElementById('stitch-timeline-styles')) return;
  const style = document.createElement('style');
  style.id = 'stitch-timeline-styles';
  style.textContent = `
    .stitch-timeline-wrap {
      background: var(--card-bg, #1a1a1a);
      border: 2px solid var(--card-border, #333);
      border-radius: 14px;
      padding: 16px;
      overflow: hidden;
    }

    /* Time Ruler */
    .stitch-ruler {
      position: relative;
      height: 24px;
      margin-bottom: 8px;
      border-bottom: 1px solid var(--border, #444);
      font-family: 'SF Mono', 'Fira Code', monospace;
      font-size: 10px;
      color: var(--text-muted, #888);
      user-select: none;
      overflow: hidden;
    }
    .stitch-ruler-tick {
      position: absolute;
      top: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .stitch-ruler-tick::after {
      content: '';
      display: block;
      width: 1px;
      height: 8px;
      background: var(--border, #444);
      margin-top: 2px;
    }

    /* Timeline Track */
    .stitch-track {
      display: flex;
      align-items: stretch;
      min-height: 72px;
      overflow-x: auto;
      overflow-y: hidden;
      padding-bottom: 4px;
      scrollbar-width: thin;
      scrollbar-color: var(--accent, #00e676) transparent;
    }
    .stitch-track::-webkit-scrollbar { height: 6px; }
    .stitch-track::-webkit-scrollbar-track { background: transparent; }
    .stitch-track::-webkit-scrollbar-thumb {
      background: var(--accent, #00e676);
      border-radius: 3px;
    }

    /* Clip Block */
    .stitch-clip {
      position: relative;
      flex-shrink: 0;
      height: 72px;
      border-radius: 8px;
      overflow: hidden;
      cursor: grab;
      border: 2px solid var(--card-border, #333);
      background: var(--bg-secondary, #222);
      transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
      box-sizing: border-box;
      touch-action: none;
    }
    .stitch-clip:hover {
      border-color: var(--accent, #00e676);
    }
    .stitch-clip.sortable-chosen {
      transform: scale(1.04);
      box-shadow: 0 4px 20px rgba(0,0,0,0.4);
      z-index: 10;
      cursor: grabbing;
    }
    .stitch-clip.sortable-ghost {
      opacity: 0.3;
    }

    /* Thumbnail strip */
    .stitch-clip-thumbs {
      display: flex;
      position: absolute;
      inset: 0;
      z-index: 0;
    }
    .stitch-clip-thumbs img {
      height: 100%;
      flex: 1;
      object-fit: cover;
      opacity: 0;
      transition: opacity 0.3s ease;
    }
    .stitch-clip-thumbs img.loaded { opacity: 1; }
    .stitch-clip-thumb-placeholder {
      flex: 1;
      height: 100%;
      background: linear-gradient(135deg, var(--bg-secondary, #222) 0%, var(--card-bg, #1a1a1a) 100%);
    }

    /* Trimmed overlay (faded region) */
    .stitch-trim-overlay-left,
    .stitch-trim-overlay-right {
      position: absolute;
      top: 0;
      bottom: 0;
      background: rgba(0,0,0,0.55);
      z-index: 2;
      pointer-events: none;
    }
    .stitch-trim-overlay-left { left: 0; }
    .stitch-trim-overlay-right { right: 0; }

    /* Info overlay */
    .stitch-clip-info {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      padding: 4px 8px;
      background: linear-gradient(transparent, rgba(0,0,0,0.75));
      z-index: 3;
      display: flex;
      justify-content: space-between;
      align-items: flex-end;
      pointer-events: none;
    }
    .stitch-clip-name {
      font-size: 11px;
      font-weight: 600;
      color: #fff;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      max-width: 70%;
      font-family: 'SF Mono', monospace;
    }
    .stitch-clip-dur {
      font-size: 10px;
      color: rgba(255,255,255,0.7);
      font-family: 'SF Mono', monospace;
    }

    /* Trim handles */
    .stitch-handle {
      position: absolute;
      top: 0;
      bottom: 0;
      width: ${TRIM_HANDLE_W}px;
      z-index: 5;
      cursor: ew-resize;
      transition: background 0.15s ease, box-shadow 0.15s ease;
    }
    .stitch-handle-left {
      left: 0;
      border-radius: 8px 0 0 8px;
      background: var(--accent, #00e676);
      opacity: 0.5;
    }
    .stitch-handle-right {
      right: 0;
      border-radius: 0 8px 8px 0;
      background: var(--accent, #00e676);
      opacity: 0.5;
    }
    .stitch-handle:hover, .stitch-handle.active {
      opacity: 1;
      box-shadow: 0 0 8px var(--accent, #00e676);
    }

    /* Trim tooltip */
    .stitch-trim-tip {
      position: absolute;
      top: -22px;
      padding: 2px 6px;
      font-size: 10px;
      font-family: 'SF Mono', monospace;
      background: var(--card-bg, #1a1a1a);
      border: 1px solid var(--accent, #00e676);
      border-radius: 4px;
      color: var(--accent, #00e676);
      white-space: nowrap;
      z-index: 10;
      pointer-events: none;
      display: none;
    }
    .stitch-handle:hover .stitch-trim-tip,
    .stitch-handle.active .stitch-trim-tip {
      display: block;
    }
    .stitch-handle-left .stitch-trim-tip { left: 0; }
    .stitch-handle-right .stitch-trim-tip { right: 0; }

    /* Stitch point divider */
    .stitch-divider {
      flex-shrink: 0;
      width: 3px;
      align-self: stretch;
      background: var(--accent-cyan, var(--accent, #00bcd4));
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .stitch-divider-diamond {
      width: 10px;
      height: 10px;
      background: var(--accent-cyan, var(--accent, #00bcd4));
      transform: rotate(45deg);
      border: 1px solid var(--card-bg, #1a1a1a);
      position: absolute;
      z-index: 2;
    }

    /* Total duration badge */
    .stitch-total {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-top: 8px;
      font-size: 11px;
      font-family: 'SF Mono', monospace;
      color: var(--text-muted, #888);
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .stitch-total-dur {
      color: var(--accent, #00e676);
      font-weight: 700;
    }

    /* Remove button on clip */
    .stitch-clip-remove {
      position: absolute;
      top: 4px;
      right: 4px;
      width: 18px;
      height: 18px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: rgba(0,0,0,0.6);
      border: 1px solid rgba(255,255,255,0.2);
      border-radius: 4px;
      color: #fff;
      font-size: 12px;
      cursor: pointer;
      z-index: 6;
      opacity: 0;
      transition: opacity 0.15s;
      pointer-events: auto;
    }
    .stitch-clip:hover .stitch-clip-remove { opacity: 1; }
    .stitch-clip-remove:hover {
      background: var(--status-error-bg, #ff1744);
      border-color: var(--status-error-border, #ff1744);
    }
  `;
  document.head.appendChild(style);
}

// ─── Helpers ────────────────────────────────────────────────────
function clipDuration(clip) {
  return clip.file?.probeData?.duration || clip.duration || 0;
}

function effectiveDuration(clip) {
  const d = clipDuration(clip);
  return Math.max(0, d - clip.trimStart - clip.trimEnd);
}

function fullClipWidth(clip) {
  return Math.max(MIN_CLIP_PX, clipDuration(clip) * PX_PER_SECOND);
}

function totalDuration() {
  return clips.reduce((sum, c) => sum + effectiveDuration(c), 0);
}

function formatSec(s) {
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const sec = (s % 60).toFixed(0);
  return `${m}:${sec.padStart(2, '0')}`;
}

// ─── Thumbnail Loading ──────────────────────────────────────────
function loadThumbnails(clip) {
  const dur = clipDuration(clip);
  if (!dur || !clip.file?.serverPath) return;

  clip.thumbnails = [];
  const times = [0.1, 0.3, 0.5, 0.7, 0.9].map((f) => (dur * f).toFixed(2));

  for (const t of times) {
    const url = `/api/thumbnail?path=${encodeURIComponent(clip.file.serverPath)}&time=${t}&width=${THUMB_WIDTH}`;
    clip.thumbnails.push(url);
  }
}

// ─── Render Time Ruler ──────────────────────────────────────────
function renderRuler(container) {
  const total = totalDuration();
  const totalPx =
    clips.reduce((sum, c) => sum + fullClipWidth(c), 0) + Math.max(0, clips.length - 1) * 3;
  container.textContent = '';
  container.style.width = `${totalPx}px`;
  container.style.minWidth = '100%';

  if (total <= 0) return;

  const interval = total > 300 ? 60 : total > 60 ? 10 : 5;
  for (let t = 0; t <= total; t += interval) {
    const pct = total > 0 ? t / total : 0;
    const px = pct * totalPx;
    const tick = document.createElement('div');
    tick.className = 'stitch-ruler-tick';
    tick.style.left = `${px}px`;
    tick.textContent = formatSec(t);
    container.appendChild(tick);
  }

  // End marker
  if (total % interval !== 0) {
    const tick = document.createElement('div');
    tick.className = 'stitch-ruler-tick';
    tick.style.left = `${totalPx}px`;
    tick.textContent = formatSec(total);
    container.appendChild(tick);
  }
}

// ─── Render Single Clip ─────────────────────────────────────────
function createClipEl(clip) {
  const dur = clipDuration(clip);
  const w = fullClipWidth(clip);

  const el = document.createElement('div');
  el.className = 'stitch-clip';
  el.dataset.clipId = clip.id;
  el.style.width = `${w}px`;

  // Thumbnails
  const thumbsDiv = document.createElement('div');
  thumbsDiv.className = 'stitch-clip-thumbs';

  if (clip.thumbnails && clip.thumbnails.length > 0) {
    for (const url of clip.thumbnails) {
      const img = document.createElement('img');
      img.src = url;
      img.loading = 'lazy';
      img.onload = () => img.classList.add('loaded');
      img.onerror = () => {
        const ph = document.createElement('div');
        ph.className = 'stitch-clip-thumb-placeholder';
        img.replaceWith(ph);
      };
      thumbsDiv.appendChild(img);
    }
  } else {
    for (let i = 0; i < THUMB_COUNT; i++) {
      const ph = document.createElement('div');
      ph.className = 'stitch-clip-thumb-placeholder';
      thumbsDiv.appendChild(ph);
    }
  }
  el.appendChild(thumbsDiv);

  // Trim overlays
  if (clip.trimStart > 0 && dur > 0) {
    const overlay = document.createElement('div');
    overlay.className = 'stitch-trim-overlay-left';
    overlay.style.width = `${(clip.trimStart / dur) * 100}%`;
    el.appendChild(overlay);
  }
  if (clip.trimEnd > 0 && dur > 0) {
    const overlay = document.createElement('div');
    overlay.className = 'stitch-trim-overlay-right';
    overlay.style.width = `${(clip.trimEnd / dur) * 100}%`;
    el.appendChild(overlay);
  }

  // Info overlay
  const info = document.createElement('div');
  info.className = 'stitch-clip-info';
  const nameSpan = document.createElement('span');
  nameSpan.className = 'stitch-clip-name';
  nameSpan.textContent = clip.file?.name || 'Clip';
  const durSpan = document.createElement('span');
  durSpan.className = 'stitch-clip-dur';
  durSpan.textContent = formatSec(effectiveDuration(clip));
  info.appendChild(nameSpan);
  info.appendChild(durSpan);
  el.appendChild(info);

  // Trim handles
  const leftHandle = document.createElement('div');
  leftHandle.className = 'stitch-handle stitch-handle-left';
  leftHandle.dataset.side = 'left';
  const leftTip = document.createElement('div');
  leftTip.className = 'stitch-trim-tip';
  leftTip.textContent = clip.trimStart > 0 ? `Trim: ${clip.trimStart.toFixed(1)}s` : 'Trim';
  leftHandle.appendChild(leftTip);
  el.appendChild(leftHandle);

  const rightHandle = document.createElement('div');
  rightHandle.className = 'stitch-handle stitch-handle-right';
  rightHandle.dataset.side = 'right';
  const rightTip = document.createElement('div');
  rightTip.className = 'stitch-trim-tip';
  rightTip.textContent = clip.trimEnd > 0 ? `Trim: ${clip.trimEnd.toFixed(1)}s` : 'Trim';
  rightHandle.appendChild(rightTip);
  el.appendChild(rightHandle);

  // Remove button
  const removeBtn = document.createElement('div');
  removeBtn.className = 'stitch-clip-remove';
  removeBtn.textContent = '\u00d7';
  removeBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    removeClip(clip.id);
  });
  el.appendChild(removeBtn);

  // Double-click to preview
  el.addEventListener('dblclick', () => {
    if (clip.file?.serverPath) {
      const previewSection = document.getElementById('preview-section');
      if (previewSection) previewSection.classList.remove('hidden');
      loadVideo(`/api/stream?path=${encodeURIComponent(clip.file.serverPath)}`);
    }
  });

  return el;
}

// ─── Render Full Timeline ───────────────────────────────────────
function renderTimeline() {
  const container = document.getElementById('stitch-clips');
  const emptyMsg = document.getElementById('stitch-empty');
  if (!container) return;

  // Destroy stale sortable
  if (sortableInstance) {
    sortableInstance.destroy();
    sortableInstance = null;
  }

  if (clips.length === 0) {
    container.textContent = '';
    container.className = 'space-y-2';
    if (emptyMsg) emptyMsg.style.display = '';
    return;
  }

  if (emptyMsg) emptyMsg.style.display = 'none';

  // Build timeline wrapper
  container.className = '';
  container.textContent = '';

  const wrap = document.createElement('div');
  wrap.className = 'stitch-timeline-wrap';

  // Ruler
  const ruler = document.createElement('div');
  ruler.className = 'stitch-ruler';
  wrap.appendChild(ruler);

  // Track
  const track = document.createElement('div');
  track.className = 'stitch-track';
  track.id = 'stitch-track';

  for (let i = 0; i < clips.length; i++) {
    if (i > 0) {
      const divider = document.createElement('div');
      divider.className = 'stitch-divider';
      const diamond = document.createElement('div');
      diamond.className = 'stitch-divider-diamond';
      divider.appendChild(diamond);
      track.appendChild(divider);
    }
    track.appendChild(createClipEl(clips[i]));
  }

  wrap.appendChild(track);

  // Total duration bar
  const totalBar = document.createElement('div');
  totalBar.className = 'stitch-total';

  const countSpan = document.createElement('span');
  countSpan.textContent = `${clips.length} clip${clips.length !== 1 ? 's' : ''}`;
  totalBar.appendChild(countSpan);

  const durSpan = document.createElement('span');
  durSpan.className = 'stitch-total-dur';
  durSpan.textContent = formatSec(totalDuration());
  totalBar.appendChild(durSpan);

  wrap.appendChild(totalBar);

  container.appendChild(wrap);

  renderRuler(ruler);
  initSortable(track);
  initTrimHandles(track);
  updateStitchButton();
}

// ─── SortableJS ─────────────────────────────────────────────────
function initSortable(track) {
  if (typeof Sortable === 'undefined') return;

  sortableInstance = new Sortable(track, {
    animation: 200,
    ghostClass: 'sortable-ghost',
    chosenClass: 'sortable-chosen',
    draggable: '.stitch-clip',
    filter: '.stitch-handle, .stitch-clip-remove',
    preventOnFilter: false,
    onEnd: () => {
      // Recompute order from DOM (SortableJS already moved DOM nodes)
      const clipEls = track.querySelectorAll('.stitch-clip');
      const newOrder = [];
      clipEls.forEach((el) => {
        const c = clips.find((cl) => cl.id === el.dataset.clipId);
        if (c) newOrder.push(c);
      });
      clips = newOrder;
      renderTimeline();
    },
  });
}

// ─── interact.js Trim Handles ───────────────────────────────────
function initTrimHandles(track) {
  if (!interactReady || typeof interact === 'undefined') return;

  track.querySelectorAll('.stitch-clip').forEach((clipEl) => {
    const clipId = clipEl.dataset.clipId;
    const clip = clips.find((c) => c.id === clipId);
    if (!clip) return;

    const dur = clipDuration(clip);
    const w = fullClipWidth(clip);
    if (dur <= 0) return;

    const pxPerSec = w / dur;

    const leftHandle = clipEl.querySelector('.stitch-handle-left');
    const rightHandle = clipEl.querySelector('.stitch-handle-right');

    interact(leftHandle).draggable({
      axis: 'x',
      listeners: {
        start() {
          leftHandle.classList.add('active');
        },
        move(event) {
          const deltaSec = event.dx / pxPerSec;
          clip.trimStart = Math.max(
            0,
            Math.min(clip.trimStart + deltaSec, dur - clip.trimEnd - MIN_TRIMMED_PX / pxPerSec),
          );
          updateClipTrimVisuals(clipEl, clip);
        },
        end() {
          leftHandle.classList.remove('active');
          renderTimeline();
        },
      },
    });

    interact(rightHandle).draggable({
      axis: 'x',
      listeners: {
        start() {
          rightHandle.classList.add('active');
        },
        move(event) {
          const deltaSec = -event.dx / pxPerSec;
          clip.trimEnd = Math.max(
            0,
            Math.min(clip.trimEnd + deltaSec, dur - clip.trimStart - MIN_TRIMMED_PX / pxPerSec),
          );
          updateClipTrimVisuals(clipEl, clip);
        },
        end() {
          rightHandle.classList.remove('active');
          renderTimeline();
        },
      },
    });
  });
}

function updateClipTrimVisuals(el, clip) {
  const dur = clipDuration(clip);
  if (dur <= 0) return;

  // Update overlays
  let leftOverlay = el.querySelector('.stitch-trim-overlay-left');
  let rightOverlay = el.querySelector('.stitch-trim-overlay-right');

  if (clip.trimStart > 0) {
    if (!leftOverlay) {
      leftOverlay = document.createElement('div');
      leftOverlay.className = 'stitch-trim-overlay-left';
      el.appendChild(leftOverlay);
    }
    leftOverlay.style.width = `${(clip.trimStart / dur) * 100}%`;
  } else if (leftOverlay) {
    leftOverlay.remove();
  }

  if (clip.trimEnd > 0) {
    if (!rightOverlay) {
      rightOverlay = document.createElement('div');
      rightOverlay.className = 'stitch-trim-overlay-right';
      el.appendChild(rightOverlay);
    }
    rightOverlay.style.width = `${(clip.trimEnd / dur) * 100}%`;
  } else if (rightOverlay) {
    rightOverlay.remove();
  }

  // Update tooltips
  const leftTip = el.querySelector('.stitch-handle-left .stitch-trim-tip');
  const rightTip = el.querySelector('.stitch-handle-right .stitch-trim-tip');
  if (leftTip)
    leftTip.textContent = clip.trimStart > 0 ? `Trim: ${clip.trimStart.toFixed(1)}s` : 'Trim';
  if (rightTip)
    rightTip.textContent = clip.trimEnd > 0 ? `Trim: ${clip.trimEnd.toFixed(1)}s` : 'Trim';

  // Update duration display
  const durSpan = el.querySelector('.stitch-clip-dur');
  if (durSpan) durSpan.textContent = formatSec(effectiveDuration(clip));
}

// ─── Clip Management ────────────────────────────────────────────
function addStitchFiles(fileList) {
  const files = Array.from(fileList);
  for (const file of files) {
    const id = `clip-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    clips.push({
      id,
      file: { name: file.name, size: file.size, rawFile: file, serverPath: null, probeData: null },
      duration: 0,
      trimStart: 0,
      trimEnd: 0,
      order: clips.length,
      thumbnails: [],
      status: 'pending',
    });
  }
  renderTimeline();
  updateStitchButton();
}

async function uploadClip(clip) {
  const formData = new FormData();
  formData.append('file', clip.file.rawFile);

  try {
    clip.status = 'uploading';
    renderTimeline();

    const res = await fetch('/api/upload', { method: 'POST', body: formData });
    if (!res.ok) throw new Error('Upload failed');

    const data = await res.json();
    clip.file.serverPath = data.files[0].path;

    // Probe
    const probeRes = await fetch(`/api/probe?path=${encodeURIComponent(clip.file.serverPath)}`);
    if (probeRes.ok) {
      clip.file.probeData = await probeRes.json();
      clip.duration = clip.file.probeData.duration || 0;
    }

    clip.status = 'ready';
    loadThumbnails(clip);
  } catch (err) {
    clip.status = 'error';
    clip.error = err.message;
  }
  renderTimeline();
  updateStitchButton();
}

function removeClip(id) {
  clips = clips.filter((c) => c.id !== id);
  renderTimeline();
  updateStitchButton();
}

// ─── Stitch Action ──────────────────────────────────────────────
async function doStitch() {
  const readyClips = clips.filter((c) => c.status === 'ready');
  if (readyClips.length < 2) {
    showNotification('Need at least 2 clips to stitch', 'warning');
    return;
  }

  const stitchBtn = document.getElementById('stitch-btn');
  if (stitchBtn) {
    stitchBtn.disabled = true;
    const txtNode = Array.from(stitchBtn.childNodes).find((n) => n.nodeType === 3);
    if (txtNode) txtNode.textContent = ' Stitching...';
  }

  const progressArea = document.getElementById('stitch-progress');
  if (progressArea) {
    progressArea.style.display = '';
    progressArea.textContent = '';
    const progWrap = document.createElement('div');
    progWrap.style.cssText =
      'padding: 16px; background: var(--card-bg); border: 2px solid var(--card-border); border-radius: 4px;';
    const progRow = document.createElement('div');
    progRow.style.cssText = 'display: flex; justify-content: space-between; align-items: center;';
    const progLabel = document.createElement('span');
    progLabel.style.cssText =
      "font-size: 13px; font-weight: 600; color: var(--text-primary); font-family: 'SF Mono', monospace; text-transform: uppercase;";
    progLabel.textContent = `Stitching ${readyClips.length} clips...`;
    const progBadge = document.createElement('span');
    progBadge.className = 'status-badge status-compressing';
    progBadge.textContent = 'Processing';
    progRow.appendChild(progLabel);
    progRow.appendChild(progBadge);
    progWrap.appendChild(progRow);
    progressArea.appendChild(progWrap);
  }

  try {
    const body = {
      clips: readyClips.map((c) => {
        const trimObj =
          c.trimStart > 0 || c.trimEnd > 0
            ? {
                start: c.trimStart > 0 ? c.trimStart : undefined,
                end: c.trimEnd > 0 ? clipDuration(c) - c.trimEnd : undefined,
              }
            : undefined;
        return {
          path: c.file.serverPath,
          name: c.file.name,
          trim: trimObj,
        };
      }),
      compress: stitchCompress,
      preset: stitchPreset,
      codec: stitchCodec,
      format: stitchFormat,
    };

    const res = await fetch('/api/stitch', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: 'Stitch failed' }));
      throw new Error(err.error);
    }

    const data = await res.json();
    renderStitchResult(progressArea, data);
    showNotification(`Stitch complete! (${data.method})`, 'success');
  } catch (err) {
    showNotification(`Stitch failed: ${err.message}`, 'error');
    renderStitchError(progressArea, err.message);
  }

  if (stitchBtn) {
    stitchBtn.disabled = false;
    const txtNode = Array.from(stitchBtn.childNodes).find((n) => n.nodeType === 3);
    if (txtNode) txtNode.textContent = ' Stitch Clips';
  }
}

// ─── Result / Error Renderers (DOM-based) ───────────────────────
function renderStitchResult(container, data) {
  if (!container) return;
  container.textContent = '';

  const wrap = document.createElement('div');
  wrap.style.cssText =
    'padding: 16px; background: var(--status-done-bg); border: 2px solid var(--status-done-border); border-radius: 4px;';

  const row = document.createElement('div');
  row.style.cssText = 'display: flex; justify-content: space-between; align-items: center;';

  const label = document.createElement('span');
  label.style.cssText =
    "font-size: 13px; font-weight: 600; color: var(--status-done-text); font-family: 'SF Mono', monospace; text-transform: uppercase;";
  label.textContent = `Stitch Complete (${data.method})`;

  const badge = document.createElement('span');
  badge.className = 'status-badge status-done';
  badge.textContent = 'Done';

  row.appendChild(label);
  row.appendChild(badge);
  wrap.appendChild(row);

  const sizeInfo = document.createElement('div');
  sizeInfo.style.cssText = 'margin-top: 8px; font-size: 12px; color: var(--text-muted);';
  sizeInfo.textContent = `Output: ${formatBytes(data.outputSize || 0)}`;
  wrap.appendChild(sizeInfo);

  if (data.outputPath) {
    const dlLink = document.createElement('a');
    dlLink.href = `/api/download?path=${encodeURIComponent(data.outputPath)}`;
    dlLink.style.cssText =
      "display: inline-flex; align-items: center; gap: 4px; margin-top: 8px; padding: 6px 14px; font-size: 12px; font-weight: 700; color: var(--accent); background: var(--accent-bg-10); border: 2px solid var(--accent-border-25); border-radius: 4px; text-decoration: none; font-family: 'SF Mono', monospace; text-transform: uppercase; letter-spacing: 0.05em;";
    dlLink.textContent = 'Download';
    wrap.appendChild(dlLink);
  }

  container.appendChild(wrap);
}

function renderStitchError(container, message) {
  if (!container) return;
  container.textContent = '';

  const wrap = document.createElement('div');
  wrap.style.cssText =
    'padding: 16px; background: var(--status-error-bg); border: 2px solid var(--status-error-border); border-radius: 4px;';

  const label = document.createElement('span');
  label.style.cssText = 'font-size: 13px; font-weight: 600; color: var(--status-error-text);';
  label.textContent = `Stitch Failed: ${message}`;
  wrap.appendChild(label);

  container.appendChild(wrap);
}

// ─── Progress Updates ───────────────────────────────────────────
export function updateStitchProgress(jobId, data) {
  const progressArea = document.getElementById('stitch-progress');
  if (!progressArea || progressArea.dataset.jobId !== jobId) return;

  if (data.type === 'progress') {
    const fill = document.getElementById('stitch-progress-fill');
    const stats = document.getElementById('stitch-progress-stats');
    if (fill) fill.style.width = `${Math.round(data.percent)}%`;
    if (stats) {
      stats.textContent = '';
      const speedSpan = document.createElement('span');
      speedSpan.style.color = 'var(--progress-speed)';
      speedSpan.textContent = data.speed || '--';
      const etaSpan = document.createElement('span');
      etaSpan.style.color = 'var(--progress-eta)';
      etaSpan.textContent = `${Math.round(data.percent)}%${data.eta ? ' | ETA: ' + data.eta : ''}`;
      stats.appendChild(speedSpan);
      stats.appendChild(etaSpan);
    }
  } else if (data.type === 'complete') {
    renderStitchResult(progressArea, data);
    showNotification('Stitch complete!', 'success');
    resetStitchBtn();
  } else if (data.type === 'error') {
    renderStitchError(progressArea, data.error);
    showNotification(`Stitch failed: ${data.error}`, 'error');
    resetStitchBtn();
  }
}

function resetStitchBtn() {
  const stitchBtn = document.getElementById('stitch-btn');
  if (stitchBtn) {
    stitchBtn.disabled = false;
    const txtNode = Array.from(stitchBtn.childNodes).find((n) => n.nodeType === 3);
    if (txtNode) txtNode.textContent = ' Stitch Clips';
  }
}

// ─── Button State ───────────────────────────────────────────────
function updateStitchButton() {
  const btn = document.getElementById('stitch-btn');
  if (!btn) return;
  const readyCount = clips.filter((c) => c.status === 'ready').length;
  btn.disabled = readyCount < 2;
}

// ─── Init ───────────────────────────────────────────────────────
export function initStitch() {
  injectTimelineStyles();

  // Load interact.js async
  loadInteract()
    .then(() => {
      interactReady = true;
      const track = document.getElementById('stitch-track');
      if (track) initTrimHandles(track);
    })
    .catch((err) => {
      console.warn('interact.js not loaded, trim handles disabled:', err.message);
    });

  // Wire drop zone
  const dropZone = document.getElementById('stitch-drop');
  const fileInput = document.getElementById('stitch-file-input');

  if (dropZone && fileInput) {
    let dragCounter = 0;

    dropZone.addEventListener('dragenter', (e) => {
      e.preventDefault();
      e.stopPropagation();
      dragCounter++;
      dropZone.classList.add('drag-over');
    });
    dropZone.addEventListener('dragover', (e) => {
      e.preventDefault();
      e.stopPropagation();
    });
    dropZone.addEventListener('dragleave', (e) => {
      e.preventDefault();
      e.stopPropagation();
      dragCounter--;
      if (dragCounter <= 0) {
        dragCounter = 0;
        dropZone.classList.remove('drag-over');
      }
    });
    dropZone.addEventListener('drop', async (e) => {
      e.preventDefault();
      e.stopPropagation();
      dragCounter = 0;
      dropZone.classList.remove('drag-over');
      const files = e.dataTransfer?.files;
      if (files && files.length > 0) {
        addStitchFiles(files);
        for (const entry of clips.filter((c) => c.status === 'pending')) {
          await uploadClip(entry);
        }
      }
    });

    dropZone.addEventListener('click', (e) => {
      if (!e.target.closest('button') && !e.target.closest('a')) fileInput.click();
    });

    fileInput.addEventListener('change', async () => {
      if (fileInput.files.length > 0) {
        addStitchFiles(fileInput.files);
        for (const entry of clips.filter((c) => c.status === 'pending')) {
          await uploadClip(entry);
        }
        fileInput.value = '';
      }
    });
  }

  // Wire compress toggle
  const compressToggle = document.getElementById('stitch-compress-toggle');
  const compressOptions = document.getElementById('stitch-compress-options');
  if (compressToggle && compressOptions) {
    compressToggle.addEventListener('change', () => {
      stitchCompress = compressToggle.checked;
      compressOptions.style.display = stitchCompress ? '' : 'none';
    });
  }

  // Wire preset/codec/format selectors
  document.querySelectorAll('[data-stitch-preset]').forEach((btn) => {
    btn.addEventListener('click', () => {
      document
        .querySelectorAll('[data-stitch-preset]')
        .forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      stitchPreset = btn.dataset.stitchPreset;
    });
  });

  document.querySelectorAll('[data-stitch-codec]').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('[data-stitch-codec]').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      stitchCodec = btn.dataset.stitchCodec;
    });
  });

  document.querySelectorAll('[data-stitch-format]').forEach((btn) => {
    btn.addEventListener('click', () => {
      document
        .querySelectorAll('[data-stitch-format]')
        .forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      stitchFormat = btn.dataset.stitchFormat;
    });
  });

  // Wire stitch button
  const stitchBtn = document.getElementById('stitch-btn');
  if (stitchBtn) stitchBtn.addEventListener('click', doStitch);

  renderTimeline();
}

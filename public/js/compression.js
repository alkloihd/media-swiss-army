/**
 * compression.js - Compression settings panel with matrix integration
 * Dynamically generates all UI into #matrix-container and #compression-controls
 */

import { appState } from './app.js';
import { formatBytes } from './filemanager.js';
import {
  initMatrix,
  getMatrixSelection,
  updateMatrixEstimates,
  onMatrixChange,
  setMatrixSelection,
} from './matrix.js';

let currentPreset = 'balanced';
let currentCodec = 'h265';
let currentFormat = 'mp4';
let currentScale = '1080p';
let currentCrf = 28;
let currentSpeed = 'medium';
let currentEncoder = 'hw';
let currentAudioBitrate = 192;
let currentAudioCodec = 'aac';
let currentFps = 'original';
let twoPass = false;
let preserveMetadata = true;
let fastStart = true;
let currentMode = 'matrix'; // 'matrix' or 'target'
let hwInfo = null;

// Row index -> preset name
const ROW_TO_PRESET = ['lossless', 'maximum', 'high', 'balanced', 'compact', 'tiny'];
// Preset name -> CRF approximation for estimation
const PRESET_CRF = { lossless: 0, maximum: 16, high: 22, balanced: 28, compact: 34, tiny: 42 };

// Col index -> scale value
const COL_TO_SCALE = ['2160p', '1440p', '1440p', '1080p', '720p', '480p'];

const CODEC_FORMAT_MAP = {
  h264: ['mp4', 'mov', 'mkv'],
  h265: ['mp4', 'mov', 'mkv'],
  av1: ['mkv', 'mp4'],
  prores: ['mov'],
};

const CODEC_DEFAULT_FORMAT = {
  h264: 'mp4',
  h265: 'mp4',
  av1: 'mkv',
  prores: 'mov',
};

const SCALE_HEIGHTS = {
  '2160p': 2160,
  '1440p': 1440,
  '1080p': 1080,
  '720p': 720,
  '480p': 480,
};

// ─── Estimation ──────────────────────────────────────────────────

const HW_BITRATES = {
  h264_videotoolbox: {
    lossless: 30000,
    maximum: 20000,
    high: 12000,
    balanced: 8000,
    compact: 4000,
    tiny: 2000,
  },
  hevc_videotoolbox: {
    lossless: 20000,
    maximum: 12000,
    high: 8000,
    balanced: 6000,
    compact: 3000,
    tiny: 1500,
  },
  prores_videotoolbox: {
    lossless: 150000,
    maximum: 100000,
    high: 80000,
    balanced: 60000,
    compact: 30000,
    tiny: 15000,
  },
};

const SW_RATIOS = {
  libx264: { lossless: 1.0, maximum: 0.9, high: 0.7, balanced: 0.6, compact: 0.35, tiny: 0.15 },
  libx265: { lossless: 0.9, maximum: 0.8, high: 0.6, balanced: 0.5, compact: 0.25, tiny: 0.12 },
  libsvtav1: { lossless: 0.8, maximum: 0.7, high: 0.5, balanced: 0.4, compact: 0.2, tiny: 0.1 },
  prores_ks: { lossless: 3.0, maximum: 2.0, high: 1.5, balanced: 1.2, compact: 0.8, tiny: 0.5 },
};

function isHWAvailable(codec) {
  if (!hwInfo) return false;
  if (codec === 'h264') return !!hwInfo.h264_videotoolbox;
  if (codec === 'h265') return !!hwInfo.hevc_videotoolbox;
  if (codec === 'prores') return !!hwInfo.prores_videotoolbox;
  return false;
}

function getEncoderName(codec) {
  const useHW = currentEncoder === 'hw' && isHWAvailable(codec);
  switch (codec) {
    case 'h264':
      return useHW ? 'h264_videotoolbox' : 'libx264';
    case 'h265':
      return useHW ? 'hevc_videotoolbox' : 'libx265';
    case 'prores':
      return useHW ? 'prores_videotoolbox' : 'prores_ks';
    case 'av1':
      return 'libsvtav1';
    default:
      return 'libx264';
  }
}

function getSelectedFile() {
  if (!appState.selectedFileId) return null;
  return appState.files.find((f) => f.id === appState.selectedFileId) || null;
}

function computeScaledDimensions(origWidth, origHeight, scale) {
  if (scale === 'original' || !SCALE_HEIGHTS[scale]) {
    return { width: origWidth, height: origHeight };
  }
  const targetHeight = SCALE_HEIGHTS[scale];
  if (targetHeight >= origHeight) return { width: origWidth, height: origHeight };
  const ratio = targetHeight / origHeight;
  let newWidth = Math.round(origWidth * ratio);
  if (newWidth % 2 !== 0) newWidth += 1;
  return { width: newWidth, height: targetHeight };
}

// ─── UI Generation ───────────────────────────────────────────────

function buildMatrixContainer() {
  const container = document.getElementById('matrix-container');
  if (!container) return;

  container.innerHTML = `
    <div class="glass-card p-5 space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-semibold themed-heading uppercase tracking-wider">Quality & Resolution</h3>
        <div id="mode-toggle" class="flex rounded-lg overflow-hidden" style="border: 1px solid var(--card-border, rgba(255,255,255,0.1));">
          <button class="mode-btn active" data-mode="matrix" style="padding: 4px 12px; font-size: 12px; transition: all 0.2s;">Visual Matrix</button>
          <button class="mode-btn" data-mode="target" style="padding: 4px 12px; font-size: 12px; transition: all 0.2s;">Target Size</button>
        </div>
      </div>

      <!-- Matrix Mode -->
      <div id="matrix-mode" class="space-y-3">
        <div id="matrix-grid"></div>
        <div id="matrix-selection-label" class="text-center text-xs" style="color: var(--text-muted, #888);"></div>
      </div>

      <!-- Target Size Mode -->
      <div id="target-mode" class="space-y-4" style="display: none;">
        <div>
          <label class="block text-xs mb-2" style="color: var(--text-muted, #888);">Target File Size (MB)</label>
          <input type="number" id="target-size-input" value="100" min="1" max="50000"
            class="themed-input w-full rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500/50" />
        </div>
        <div class="flex flex-wrap gap-2">
          <button class="preset-btn" data-target="50">50 MB</button>
          <button class="preset-btn active" data-target="100">100 MB</button>
          <button class="preset-btn" data-target="250">250 MB</button>
          <button class="preset-btn" data-target="500">500 MB</button>
          <button class="preset-btn" data-target="1024">1 GB</button>
        </div>
        <div id="target-solutions" class="space-y-2"></div>
      </div>
    </div>
  `;

  // Wire mode toggle
  container.querySelectorAll('.mode-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      container.querySelectorAll('.mode-btn').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      currentMode = btn.dataset.mode;
      document.getElementById('matrix-mode').style.display = currentMode === 'matrix' ? '' : 'none';
      document.getElementById('target-mode').style.display = currentMode === 'target' ? '' : 'none';
    });
  });

  // Wire target size presets
  container.querySelectorAll('[data-target]').forEach((btn) => {
    btn.addEventListener('click', () => {
      container.querySelectorAll('[data-target]').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const input = document.getElementById('target-size-input');
      input.value = btn.dataset.target;
      updateTargetSolutions();
    });
  });

  const targetInput = document.getElementById('target-size-input');
  if (targetInput) {
    targetInput.addEventListener('input', updateTargetSolutions);
  }

  // Init matrix SVG
  initMatrix('matrix-grid');

  // Wire matrix changes
  onMatrixChange((sel) => {
    currentPreset = ROW_TO_PRESET[sel.row] || 'balanced';
    currentScale = COL_TO_SCALE[sel.col] || '1080p';
    currentCrf = sel.qualityCrf;
    updateSelectionLabel(sel);
    updateSummaryPanel();
  });

  // Set initial label
  const initialSel = getMatrixSelection();
  updateSelectionLabel(initialSel);
}

function updateSelectionLabel(sel) {
  const label = document.getElementById('matrix-selection-label');
  if (!label) return;
  const file = getSelectedFile();
  let sizeStr = '';
  if (sel.estimatedBytes) {
    sizeStr = ` — ~${formatBytes(sel.estimatedBytes)}`;
  }
  label.textContent = `${sel.quality} quality at ${sel.resolution}${sizeStr}`;
}

function updateTargetSolutions() {
  const container = document.getElementById('target-solutions');
  if (!container) return;
  const input = document.getElementById('target-size-input');
  const targetMB = parseFloat(input?.value) || 100;
  const targetBytes = targetMB * 1024 * 1024;

  const file = getSelectedFile();
  if (!file || !file.probeData) {
    container.innerHTML =
      '<p class="text-xs" style="color: var(--text-muted);">Add a file to see solutions.</p>';
    return;
  }

  const probe = file.probeData;
  const duration = probe.duration || 0;
  if (duration <= 0) {
    container.innerHTML =
      '<p class="text-xs" style="color: var(--text-muted);">Cannot calculate — unknown duration.</p>';
    return;
  }

  const targetBitrate = (targetBytes * 8) / duration / 1000; // kbps
  container.innerHTML = `
    <div class="glass-card p-3 space-y-1" style="border: 1px solid var(--card-border, rgba(255,255,255,0.1));">
      <div class="text-xs font-medium" style="color: var(--text-secondary, #ccc);">Required bitrate: ${Math.round(targetBitrate)} kbps</div>
      <div class="text-xs" style="color: var(--text-muted, #888);">
        ${targetBitrate > 8000 ? 'H.264 Balanced or higher recommended' : targetBitrate > 3000 ? 'H.265 Balanced recommended' : 'H.265 Compact or AV1 recommended'}
      </div>
    </div>
  `;
}

function buildCompressionControls() {
  const container = document.getElementById('compression-controls');
  if (!container) return;

  const h264HW = isHWAvailable('h264');
  const h265HW = isHWAvailable('h265');
  const anyHW = h264HW || h265HW || isHWAvailable('prores');

  container.innerHTML = `
    <!-- Codec -->
    <div class="glass-card p-5 space-y-3">
      <h3 class="text-sm font-semibold themed-heading uppercase tracking-wider">Codec</h3>
      <div id="codec-selector" class="flex flex-wrap gap-2">
        <button class="preset-btn" data-codec="h264">H.264${h264HW ? ' <span class="hw-indicator" title="Hardware accelerated"></span>' : ''}</button>
        <button class="preset-btn active" data-codec="h265">H.265${h265HW ? ' <span class="hw-indicator" title="Hardware accelerated"></span>' : ''}</button>
        <button class="preset-btn" data-codec="av1">AV1</button>
      </div>

      <!-- Encoder Toggle -->
      ${
        anyHW
          ? `
      <div class="flex items-center gap-2 mt-2">
        <span class="text-xs" style="color: var(--text-muted, #888);">Encoder:</span>
        <div id="encoder-toggle" class="flex rounded-lg overflow-hidden" style="border: 1px solid var(--card-border, rgba(255,255,255,0.1));">
          <button class="preset-btn active" data-encoder="hw" style="padding: 3px 10px; font-size: 11px;">Hardware</button>
          <button class="preset-btn" data-encoder="sw" style="padding: 3px 10px; font-size: 11px;">Software</button>
        </div>
      </div>
      `
          : ''
      }
    </div>

    <!-- Audio (collapsible) -->
    <div class="glass-card p-5 space-y-3">
      <button id="audio-toggle-header" class="w-full flex items-center justify-between text-sm font-semibold themed-heading uppercase tracking-wider cursor-pointer">
        Audio
        <svg class="w-4 h-4 transition-transform" id="audio-chevron" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5"/>
        </svg>
      </button>
      <div id="audio-body" style="display: none;" class="space-y-3">
        <div>
          <label class="flex items-center justify-between text-xs mb-1">
            <span style="color: var(--text-muted, #888);">Bitrate</span>
            <span id="audio-bitrate-label" style="color: var(--text-secondary, #ccc);">192 kbps</span>
          </label>
          <input type="range" id="audio-bitrate-slider" min="128" max="320" step="32" value="192" class="w-full" style="accent-color: var(--accent-green, #22c55e);" />
        </div>
        <div>
          <span class="text-xs" style="color: var(--text-muted, #888);">Audio Codec</span>
          <div id="audio-codec-selector" class="flex flex-wrap gap-2 mt-1">
            <button class="preset-btn active" data-acodec="aac">AAC</button>
            <button class="preset-btn" data-acodec="opus">Opus</button>
            <button class="preset-btn" data-acodec="copy">Copy</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Summary Panel -->
    <div class="glass-card p-5 space-y-3" id="summary-panel">
      <h3 class="text-sm font-semibold themed-heading uppercase tracking-wider">Summary</h3>
      <div id="est-size" class="text-lg font-bold" style="color: var(--accent-green, #22c55e);">—</div>
      <div id="est-bar-wrap" class="w-full rounded-full overflow-hidden" style="height: 6px; background: var(--bg-secondary, #1a1a35);">
        <div id="est-bar" class="h-full rounded-full transition-all duration-500" style="width: 50%; background: var(--accent-green, #22c55e);"></div>
      </div>
      <div id="est-specs" class="text-xs" style="color: var(--text-muted, #888);">Select a file to see estimates</div>
    </div>

    <!-- Advanced (collapsible) -->
    <div class="glass-card p-5 space-y-3">
      <button id="advanced-toggle-header" class="w-full flex items-center justify-between text-sm font-semibold themed-heading uppercase tracking-wider cursor-pointer">
        Advanced
        <svg class="w-4 h-4 transition-transform" id="advanced-chevron" fill="none" stroke="currentColor" viewBox="0 0 24 24" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5"/>
        </svg>
      </button>
      <div id="advanced-body" style="display: none;" class="space-y-3">
        <!-- Format -->
        <div>
          <span class="text-xs" style="color: var(--text-muted, #888);">Format</span>
          <div id="format-selector" class="flex flex-wrap gap-2 mt-1">
            <button class="preset-btn active" data-format="mp4">MP4</button>
            <button class="preset-btn" data-format="mov">MOV</button>
            <button class="preset-btn" data-format="mkv">MKV</button>
          </div>
        </div>
        <!-- FPS -->
        <div>
          <span class="text-xs" style="color: var(--text-muted, #888);">FPS</span>
          <div id="fps-selector" class="flex flex-wrap gap-2 mt-1">
            <button class="preset-btn active" data-fps="original">Original</button>
            <button class="preset-btn" data-fps="60">60</button>
            <button class="preset-btn" data-fps="30">30</button>
            <button class="preset-btn" data-fps="24">24</button>
          </div>
        </div>
        <!-- Toggles -->
        <div class="space-y-2">
          <label class="flex items-center justify-between cursor-pointer">
            <span class="text-xs" style="color: var(--text-muted, #888);">2-Pass Encoding</span>
            <input type="checkbox" id="toggle-twopass" style="accent-color: var(--accent-green, #22c55e);" />
          </label>
          <label class="flex items-center justify-between cursor-pointer">
            <span class="text-xs" style="color: var(--text-muted, #888);">Preserve Metadata</span>
            <input type="checkbox" id="toggle-metadata" checked style="accent-color: var(--accent-green, #22c55e);" />
          </label>
          <label class="flex items-center justify-between cursor-pointer">
            <span class="text-xs" style="color: var(--text-muted, #888);">Fast Start (MP4)</span>
            <input type="checkbox" id="toggle-faststart" checked style="accent-color: var(--accent-green, #22c55e);" />
          </label>
        </div>
      </div>
    </div>
  `;

  wireControls();
}

function wireControls() {
  // Codec selector
  wireButtonGroup('codec-selector', 'codec', (value) => {
    currentCodec = value;
    updateFormatButtons();
    syncMatrixEstimates();
    updateSummaryPanel();
  });

  // Encoder toggle
  const encoderToggle = document.getElementById('encoder-toggle');
  if (encoderToggle) {
    encoderToggle.querySelectorAll('.preset-btn').forEach((btn) => {
      btn.addEventListener('click', () => {
        encoderToggle.querySelectorAll('.preset-btn').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        currentEncoder = btn.dataset.encoder;
        syncMatrixEstimates();
        updateSummaryPanel();
      });
    });
  }

  // Audio collapsible
  const audioHeader = document.getElementById('audio-toggle-header');
  const audioBody = document.getElementById('audio-body');
  const audioChevron = document.getElementById('audio-chevron');
  if (audioHeader && audioBody) {
    audioHeader.addEventListener('click', () => {
      const open = audioBody.style.display !== 'none';
      audioBody.style.display = open ? 'none' : '';
      audioChevron.style.transform = open ? '' : 'rotate(180deg)';
    });
  }

  // Audio bitrate slider
  const slider = document.getElementById('audio-bitrate-slider');
  const sliderLabel = document.getElementById('audio-bitrate-label');
  if (slider) {
    slider.addEventListener('input', () => {
      currentAudioBitrate = parseInt(slider.value, 10);
      if (sliderLabel) sliderLabel.textContent = `${currentAudioBitrate} kbps`;
    });
  }

  // Audio codec
  wireButtonGroup('audio-codec-selector', 'acodec', (value) => {
    currentAudioCodec = value;
  });

  // Advanced collapsible
  const advHeader = document.getElementById('advanced-toggle-header');
  const advBody = document.getElementById('advanced-body');
  const advChevron = document.getElementById('advanced-chevron');
  if (advHeader && advBody) {
    advHeader.addEventListener('click', () => {
      const open = advBody.style.display !== 'none';
      advBody.style.display = open ? 'none' : '';
      advChevron.style.transform = open ? '' : 'rotate(180deg)';
    });
  }

  // Format selector
  wireButtonGroup('format-selector', 'format', (value) => {
    currentFormat = value;
    updateSummaryPanel();
  });

  // FPS selector
  wireButtonGroup('fps-selector', 'fps', (value) => {
    currentFps = value;
  });

  // Toggles
  const tp = document.getElementById('toggle-twopass');
  if (tp)
    tp.addEventListener('change', () => {
      twoPass = tp.checked;
    });
  const tm = document.getElementById('toggle-metadata');
  if (tm)
    tm.addEventListener('change', () => {
      preserveMetadata = tm.checked;
    });
  const tf = document.getElementById('toggle-faststart');
  if (tf)
    tf.addEventListener('change', () => {
      fastStart = tf.checked;
    });
}

function wireButtonGroup(containerId, dataAttr, onSelect) {
  const container = document.getElementById(containerId);
  if (!container) return;
  const buttons = container.querySelectorAll('.preset-btn');
  buttons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const value = btn.dataset[dataAttr];
      if (!value || btn.classList.contains('disabled')) return;
      buttons.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      onSelect(value);
    });
  });
}

function updateFormatButtons() {
  const container = document.getElementById('format-selector');
  if (!container) return;
  const allowedFormats = CODEC_FORMAT_MAP[currentCodec] || ['mp4'];
  const buttons = container.querySelectorAll('.preset-btn');
  buttons.forEach((btn) => {
    const fmt = btn.dataset.format;
    if (!fmt) return;
    if (allowedFormats.includes(fmt)) {
      btn.classList.remove('disabled');
    } else {
      btn.classList.add('disabled');
      btn.classList.remove('active');
    }
  });
  if (!allowedFormats.includes(currentFormat)) {
    currentFormat = CODEC_DEFAULT_FORMAT[currentCodec] || allowedFormats[0];
    buttons.forEach((btn) => {
      if (btn.dataset.format === currentFormat) btn.classList.add('active');
    });
  }
}

function syncMatrixEstimates() {
  const file = getSelectedFile();
  const source = file?.probeData ? { size: file.probeData.size || file.size || 0 } : null;
  updateMatrixEstimates(currentCodec, currentEncoder, source);
}

function updateSummaryPanel() {
  const estSize = document.getElementById('est-size');
  const estBar = document.getElementById('est-bar');
  const estSpecs = document.getElementById('est-specs');
  if (!estSize) return;

  const file = getSelectedFile();
  if (!file || !file.probeData) {
    estSize.textContent = '—';
    if (estBar) estBar.style.width = '50%';
    if (estSpecs) estSpecs.textContent = 'Select a file to see estimates';
    return;
  }

  const probe = file.probeData;
  const originalSize = probe.size || file.size || 0;
  const duration = probe.duration || 0;
  if (!originalSize || !duration) {
    estSize.textContent = '—';
    return;
  }

  const encoder = getEncoderName(currentCodec);
  let estimatedSize = 0;

  if (HW_BITRATES[encoder] && HW_BITRATES[encoder][currentPreset]) {
    const bitrate = HW_BITRATES[encoder][currentPreset];
    estimatedSize = ((bitrate * 1000) / 8) * duration;
  } else if (SW_RATIOS[encoder] && SW_RATIOS[encoder][currentPreset] !== undefined) {
    estimatedSize = originalSize * SW_RATIOS[encoder][currentPreset];
  } else {
    // Fallback: CRF-based interpolation
    let ratio;
    if (currentCrf <= 18) ratio = 1.5 - (currentCrf / 18) * 0.7;
    else if (currentCrf <= 28) ratio = 0.8 - ((currentCrf - 18) / 10) * 0.5;
    else ratio = Math.max(0.03, 0.3 - ((currentCrf - 28) / 23) * 0.25);
    if (currentCodec === 'h265') ratio *= 0.7;
    else if (currentCodec === 'av1') ratio *= 0.55;
    estimatedSize = originalSize * ratio;
  }

  // Adjust for resolution scaling
  const origW = probe.width || 0;
  const origH = probe.height || 0;
  if (currentScale !== 'original' && origW > 0 && origH > 0) {
    const scaled = computeScaledDimensions(origW, origH, currentScale);
    const pixelRatio = (scaled.width * scaled.height) / (origW * origH);
    estimatedSize *= pixelRatio;
  }

  const pctChange = ((estimatedSize - originalSize) / originalSize) * 100;
  const pctOfOriginal = Math.max(
    1,
    Math.min(150, Math.round((estimatedSize / originalSize) * 100)),
  );

  estSize.textContent = `~${formatBytes(Math.round(estimatedSize))}`;
  estSize.style.color =
    pctChange <= -20
      ? 'var(--accent-green, #22c55e)'
      : pctChange <= 0
        ? 'var(--accent-yellow, #eab308)'
        : 'var(--accent-orange, #f97316)';

  if (estBar) {
    estBar.style.width = `${pctOfOriginal}%`;
    estBar.style.background =
      pctChange <= -20
        ? 'var(--accent-green, #22c55e)'
        : pctChange <= 0
          ? 'var(--accent-yellow, #eab308)'
          : 'var(--accent-orange, #f97316)';
  }

  const sign = pctChange <= 0 ? '' : '+';
  const codecNames = { h264: 'H.264', h265: 'H.265', av1: 'AV1', prores: 'ProRes' };
  let specsLine = `${sign}${Math.round(pctChange)}% vs original (${formatBytes(originalSize)}) — ${codecNames[currentCodec] || currentCodec} ${currentFormat.toUpperCase()} ${currentScale}`;

  if (currentCodec === 'av1') specsLine += ' — AV1 is slow (~0.5x)';
  else if (origH >= 2160 && currentScale !== '720p' && currentScale !== '480p') {
    specsLine +=
      currentEncoder === 'hw' && isHWAvailable(currentCodec)
        ? ' — 4K HW (~3-5x)'
        : ' — 4K SW (~0.5-1x)';
  }

  if (estSpecs) estSpecs.textContent = specsLine;
}

// ─── HW Badge ────────────────────────────────────────────────────

function updateHWBadge() {
  const badge = document.getElementById('hw-badge');
  const badgeText = document.getElementById('hw-badge-text');
  if (!badge || !badgeText) return;

  if (!hwInfo) {
    badgeText.textContent = 'Hardware detection unavailable';
    badge.classList.add('hw-unavailable');
    badge.classList.remove('hw-available');
    return;
  }

  const hasVT = hwInfo.h264_videotoolbox || hwInfo.hevc_videotoolbox || hwInfo.prores_videotoolbox;
  if (hasVT) {
    badgeText.textContent = 'HW Accel: VideoToolbox';
    badge.classList.add('hw-available');
    badge.classList.remove('hw-unavailable');
  } else {
    badgeText.textContent = 'Software encoding only';
    badge.classList.add('hw-unavailable');
    badge.classList.remove('hw-available');
  }
}

// ─── Init & Exports ──────────────────────────────────────────────

export function initCompression(hwData) {
  hwInfo = hwData;
  buildMatrixContainer();
  buildCompressionControls();
  updateHWBadge();
  updateFormatButtons();
  syncMatrixEstimates();
  updateSummaryPanel();
}

export function getCompressionSettings() {
  return {
    preset: currentPreset,
    codec: currentCodec,
    format: currentFormat,
    scale: currentScale,
    crf: currentCrf,
    speed: currentSpeed,
    audioBitrate: currentAudioBitrate,
    audioCodec: currentAudioCodec,
    fps: currentFps,
    twoPass,
    preserveMetadata,
    fastStart,
  };
}

export function updateResolutionOptions() {
  // Matrix handles resolution; sync estimates when file changes
  syncMatrixEstimates();
  updateSummaryPanel();
  updateTargetSolutions();
}

export function updateEstimation() {
  syncMatrixEstimates();
  updateSummaryPanel();
}

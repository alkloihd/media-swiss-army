/**
 * matrix.js - Interactive 2D compression matrix (Resolution x Quality)
 * SVG-based 6x6 grid with drag, touch, animations
 */
/* global requestAnimationFrame */

const COLS = [
  { label: '4K', px: 2160, value: '2160p' },
  { label: '2K', px: 1440, value: '1440p' },
  { label: '1440p', px: 1440, value: '1440p' },
  { label: '1080p', px: 1080, value: '1080p' },
  { label: '720p', px: 720, value: '720p' },
  { label: '480p', px: 480, value: '480p' },
];

const ROWS = [
  { label: 'Lossless', pct: 100, crf: 0 },
  { label: 'Maximum', pct: 80, crf: 16 },
  { label: 'High', pct: 55, crf: 22 },
  { label: 'Balanced', pct: 35, crf: 28 },
  { label: 'Compact', pct: 20, crf: 34 },
  { label: 'Tiny', pct: 8, crf: 42 },
];

const COLOR_STOPS = [
  [34, 197, 94], // green
  [132, 204, 22], // lime
  [234, 179, 8], // yellow
  [249, 115, 22], // orange
  [236, 72, 153], // pink
  [168, 85, 247], // purple
];

const CELL = 56;
const COLS_COUNT = 6;
const ROWS_COUNT = 6;
const PAD_LEFT = 72;
const PAD_BOTTOM = 32;
const SVG_W = PAD_LEFT + COLS_COUNT * CELL;
const SVG_H = ROWS_COUNT * CELL + PAD_BOTTOM;

let selectedCol = 3; // 1080p
let selectedRow = 3; // Balanced
let currentCodec = 'h265';
let currentEncoder = 'hw';
let sourceData = null;
let changeCallbacks = [];
let animFrame = null;
let breathPhase = 0;
let svgEl = null;
let cellGroups = [];
let crosshairH = null;
let crosshairV = null;
let selRing = null;
let glowCircle = null;
let particles = [];
let particleSvgGroup = null;
let isDragging = false;

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function colorAt(t) {
  t = Math.max(0, Math.min(1, t));
  const idx = t * (COLOR_STOPS.length - 1);
  const i = Math.floor(idx);
  const f = idx - i;
  const c0 = COLOR_STOPS[Math.min(i, COLOR_STOPS.length - 1)];
  const c1 = COLOR_STOPS[Math.min(i + 1, COLOR_STOPS.length - 1)];
  return [
    Math.round(lerp(c0[0], c1[0], f)),
    Math.round(lerp(c0[1], c1[1], f)),
    Math.round(lerp(c0[2], c1[2], f)),
  ];
}

function estimatePct(col, row) {
  const codecMul = currentCodec === 'av1' ? 0.6 : currentCodec === 'h264' ? 1.3 : 1.0;
  const encMul = currentEncoder === 'sw' ? 0.75 : 1.0;
  const resFactor = Math.pow(COLS[col].px / COLS[0].px, 2);
  return Math.max(2, Math.round(resFactor * (ROWS[row].pct / 100) * codecMul * encMul * 100));
}

function cellColor(col, row) {
  const t = (col / (COLS_COUNT - 1) + row / (ROWS_COUNT - 1)) / 2;
  return colorAt(t);
}

function dist(c1, r1, c2, r2) {
  return Math.max(Math.abs(c1 - c2), Math.abs(r1 - r2));
}

function cellAlpha(col, row, phase) {
  const d = dist(col, row, selectedCol, selectedRow);
  if (d === 0) return 0.55;
  if (d === 1) return 0.2;
  // breathing
  const breath = 0.04 + 0.02 * Math.sin(phase + col * 0.5 + row * 0.3);
  return 0.06 + breath;
}

function ns(tag) {
  return document.createElementNS('http://www.w3.org/2000/svg', tag);
}

function cellCenter(col, row) {
  return {
    x: PAD_LEFT + col * CELL + CELL / 2,
    y: row * CELL + CELL / 2,
  };
}

function buildSVG(container) {
  svgEl = ns('svg');
  svgEl.setAttribute('width', SVG_W);
  svgEl.setAttribute('height', SVG_H);
  svgEl.setAttribute('viewBox', `0 0 ${SVG_W} ${SVG_H}`);
  svgEl.style.display = 'block';
  svgEl.style.margin = '0 auto';
  svgEl.style.cursor = 'pointer';
  svgEl.style.userSelect = 'none';
  svgEl.style.touchAction = 'none';

  // Defs for glow filter
  const defs = ns('defs');
  const filter = ns('filter');
  filter.setAttribute('id', 'matrix-glow');
  filter.setAttribute('x', '-50%');
  filter.setAttribute('y', '-50%');
  filter.setAttribute('width', '200%');
  filter.setAttribute('height', '200%');
  const blur = ns('feGaussianBlur');
  blur.setAttribute('stdDeviation', '4');
  blur.setAttribute('result', 'blur');
  const merge = ns('feMerge');
  const m1 = ns('feMergeNode');
  m1.setAttribute('in', 'blur');
  const m2 = ns('feMergeNode');
  m2.setAttribute('in', 'SourceGraphic');
  merge.appendChild(m1);
  merge.appendChild(m2);
  filter.appendChild(blur);
  filter.appendChild(merge);
  defs.appendChild(filter);
  svgEl.appendChild(defs);

  // Crosshairs
  crosshairH = ns('line');
  crosshairH.setAttribute('stroke', 'rgba(255,255,255,0.08)');
  crosshairH.setAttribute('stroke-width', '1');
  svgEl.appendChild(crosshairH);

  crosshairV = ns('line');
  crosshairV.setAttribute('stroke', 'rgba(255,255,255,0.08)');
  crosshairV.setAttribute('stroke-width', '1');
  svgEl.appendChild(crosshairV);

  // Cells
  cellGroups = [];
  for (let row = 0; row < ROWS_COUNT; row++) {
    cellGroups[row] = [];
    for (let col = 0; col < COLS_COUNT; col++) {
      const g = ns('g');
      const rect = ns('rect');
      const cx = PAD_LEFT + col * CELL;
      const cy = row * CELL;
      rect.setAttribute('x', cx + 2);
      rect.setAttribute('y', cy + 2);
      rect.setAttribute('width', CELL - 4);
      rect.setAttribute('height', CELL - 4);
      rect.setAttribute('rx', '6');
      g.appendChild(rect);

      const text = ns('text');
      text.setAttribute('x', cx + CELL / 2);
      text.setAttribute('y', cy + CELL / 2 + 4);
      text.setAttribute('text-anchor', 'middle');
      text.setAttribute('font-size', '11');
      text.setAttribute('font-family', 'system-ui, sans-serif');
      text.setAttribute('font-weight', '600');
      g.appendChild(text);

      svgEl.appendChild(g);
      cellGroups[row][col] = { g, rect, text };
    }
  }

  // Glow behind selection
  glowCircle = ns('circle');
  glowCircle.setAttribute('r', '20');
  glowCircle.setAttribute('filter', 'url(#matrix-glow)');
  svgEl.appendChild(glowCircle);

  // Selection ring
  selRing = ns('circle');
  selRing.setAttribute('r', '24');
  selRing.setAttribute('fill', 'none');
  selRing.setAttribute('stroke-width', '2');
  svgEl.appendChild(selRing);

  // Particle group
  particleSvgGroup = ns('g');
  svgEl.appendChild(particleSvgGroup);

  // Y-axis labels
  for (let row = 0; row < ROWS_COUNT; row++) {
    const label = ns('text');
    label.setAttribute('x', PAD_LEFT - 8);
    label.setAttribute('y', row * CELL + CELL / 2 + 4);
    label.setAttribute('text-anchor', 'end');
    label.setAttribute('font-size', '10');
    label.setAttribute('font-family', 'system-ui, sans-serif');
    label.setAttribute('class', `matrix-ylabel matrix-ylabel-${row}`);
    label.textContent = ROWS[row].label;
    svgEl.appendChild(label);
  }

  // X-axis labels
  for (let col = 0; col < COLS_COUNT; col++) {
    const label = ns('text');
    label.setAttribute('x', PAD_LEFT + col * CELL + CELL / 2);
    label.setAttribute('y', ROWS_COUNT * CELL + 18);
    label.setAttribute('text-anchor', 'middle');
    label.setAttribute('font-size', '10');
    label.setAttribute('font-family', 'system-ui, sans-serif');
    label.setAttribute('class', `matrix-xlabel matrix-xlabel-${col}`);
    label.textContent = COLS[col].label;
    svgEl.appendChild(label);
  }

  // Events
  svgEl.addEventListener('pointerdown', onPointerDown);
  svgEl.addEventListener('pointermove', onPointerMove);
  svgEl.addEventListener('pointerup', onPointerUp);
  svgEl.addEventListener('pointerleave', onPointerUp);

  container.appendChild(svgEl);
  renderCells();
  startBreathing();
}

function hitTest(e) {
  const rect = svgEl.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const y = e.clientY - rect.top;
  const scaleX = SVG_W / rect.width;
  const scaleY = SVG_H / rect.height;
  const svgX = x * scaleX - PAD_LEFT;
  const svgY = y * scaleY;
  const col = Math.floor(svgX / CELL);
  const row = Math.floor(svgY / CELL);
  if (col >= 0 && col < COLS_COUNT && row >= 0 && row < ROWS_COUNT) {
    return { col, row };
  }
  return null;
}

function onPointerDown(e) {
  isDragging = true;
  svgEl.setPointerCapture(e.pointerId);
  const hit = hitTest(e);
  if (hit) selectCell(hit.col, hit.row);
}

function onPointerMove(e) {
  if (!isDragging) return;
  const hit = hitTest(e);
  if (hit && (hit.col !== selectedCol || hit.row !== selectedRow)) {
    selectCell(hit.col, hit.row);
  }
}

function onPointerUp(e) {
  isDragging = false;
  try {
    svgEl.releasePointerCapture(e.pointerId);
  } catch {}
}

function selectCell(col, row) {
  selectedCol = col;
  selectedRow = row;
  spawnParticles(col, row);
  renderCells();
  notifyChange();
}

function notifyChange() {
  const sel = getMatrixSelection();
  for (const cb of changeCallbacks) {
    try {
      cb(sel);
    } catch {}
  }
}

function renderCells() {
  for (let row = 0; row < ROWS_COUNT; row++) {
    for (let col = 0; col < COLS_COUNT; col++) {
      const { rect, text } = cellGroups[row][col];
      const [r, g, b] = cellColor(col, row);
      const a = cellAlpha(col, row, breathPhase);
      const isSelected = col === selectedCol && row === selectedRow;

      rect.setAttribute('fill', `rgba(${r},${g},${b},${a})`);
      rect.setAttribute('stroke', isSelected ? `rgb(${r},${g},${b})` : 'transparent');
      rect.setAttribute('stroke-width', isSelected ? '2' : '0');

      const pct = estimatePct(col, row);
      let label;
      if (sourceData && sourceData.size) {
        const mb = ((sourceData.size * pct) / 100 / 1024 / 1024).toFixed(0);
        label = `${mb}M`;
      } else {
        label = `${pct}%`;
      }
      text.textContent = label;
      text.setAttribute(
        'fill',
        isSelected ? '#ffffff' : `rgba(${r},${g},${b},${Math.min(1, a + 0.4)})`,
      );
    }
  }

  // Update crosshairs
  const center = cellCenter(selectedCol, selectedRow);
  crosshairH.setAttribute('x1', PAD_LEFT);
  crosshairH.setAttribute('x2', PAD_LEFT + COLS_COUNT * CELL);
  crosshairH.setAttribute('y1', center.y);
  crosshairH.setAttribute('y2', center.y);
  crosshairV.setAttribute('x1', center.x);
  crosshairV.setAttribute('x2', center.x);
  crosshairV.setAttribute('y1', 0);
  crosshairV.setAttribute('y2', ROWS_COUNT * CELL);

  // Glow + ring
  const [sr, sg, sb] = cellColor(selectedCol, selectedRow);
  glowCircle.setAttribute('cx', center.x);
  glowCircle.setAttribute('cy', center.y);
  glowCircle.setAttribute('fill', `rgba(${sr},${sg},${sb},0.15)`);
  selRing.setAttribute('cx', center.x);
  selRing.setAttribute('cy', center.y);
  selRing.setAttribute('stroke', `rgb(${sr},${sg},${sb})`);

  // Axis label highlights
  for (let r = 0; r < ROWS_COUNT; r++) {
    const el = svgEl.querySelector(`.matrix-ylabel-${r}`);
    if (el) {
      const [lr, lg, lb] = cellColor(0, r);
      el.setAttribute(
        'fill',
        r === selectedRow ? `rgb(${lr},${lg},${lb})` : 'var(--text-tertiary, #888)',
      );
      el.setAttribute('font-weight', r === selectedRow ? '700' : '400');
    }
  }
  for (let c = 0; c < COLS_COUNT; c++) {
    const el = svgEl.querySelector(`.matrix-xlabel-${c}`);
    if (el) {
      const [lr, lg, lb] = cellColor(c, 0);
      el.setAttribute(
        'fill',
        c === selectedCol ? `rgb(${lr},${lg},${lb})` : 'var(--text-tertiary, #888)',
      );
      el.setAttribute('font-weight', c === selectedCol ? '700' : '400');
    }
  }
}

function spawnParticles(col, row) {
  const center = cellCenter(col, row);
  const [r, g, b] = cellColor(col, row);
  for (let i = 0; i < 8; i++) {
    const circle = ns('circle');
    circle.setAttribute('r', '2');
    circle.setAttribute('fill', `rgb(${r},${g},${b})`);
    particleSvgGroup.appendChild(circle);
    particles.push({
      el: circle,
      x: center.x,
      y: center.y,
      vx: (Math.random() - 0.5) * 3,
      vy: -Math.random() * 3 - 1,
      life: 1,
    });
  }
}

function startBreathing() {
  function tick() {
    breathPhase += 0.02;

    // Update breathing alpha on non-selected cells only
    for (let row = 0; row < ROWS_COUNT; row++) {
      for (let col = 0; col < COLS_COUNT; col++) {
        if (col === selectedCol && row === selectedRow) continue;
        if (dist(col, row, selectedCol, selectedRow) <= 1) continue;
        const { rect } = cellGroups[row][col];
        const [r, g, b] = cellColor(col, row);
        const a = cellAlpha(col, row, breathPhase);
        rect.setAttribute('fill', `rgba(${r},${g},${b},${a})`);
      }
    }

    // Animate particles
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.life -= 0.025;
      if (p.life <= 0) {
        p.el.remove();
        particles.splice(i, 1);
      } else {
        p.el.setAttribute('cx', p.x);
        p.el.setAttribute('cy', p.y);
        p.el.setAttribute('opacity', p.life);
      }
    }

    animFrame = requestAnimationFrame(tick);
  }
  animFrame = requestAnimationFrame(tick);
}

// ─── Public API ─────────────────────────────────────────────

export function initMatrix(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return;
  container.textContent = '';
  buildSVG(container);
}

export function getMatrixSelection() {
  const pct = estimatePct(selectedCol, selectedRow);
  return {
    col: selectedCol,
    row: selectedRow,
    resolution: COLS[selectedCol].label,
    resolutionValue: COLS[selectedCol].value,
    resolutionPx: COLS[selectedCol].px,
    quality: ROWS[selectedRow].label,
    qualityCrf: ROWS[selectedRow].crf,
    estimatedPct: pct,
    estimatedBytes: sourceData ? Math.round((sourceData.size * pct) / 100) : null,
  };
}

export function updateMatrixEstimates(codec, encoder, source) {
  currentCodec = codec || currentCodec;
  currentEncoder = encoder || currentEncoder;
  if (source !== undefined) sourceData = source;
  if (svgEl) renderCells();
}

export function onMatrixChange(callback) {
  changeCallbacks.push(callback);
}

export function setMatrixSelection(col, row) {
  if (col >= 0 && col < COLS_COUNT && row >= 0 && row < ROWS_COUNT) {
    selectedCol = col;
    selectedRow = row;
    if (svgEl) renderCells();
  }
}

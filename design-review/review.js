const LS_KEY = 'design-review:ratings:v1';
const LS_WINNERS = 'design-review:winners:v1';

const state = {
  assets: [],
  ratings: loadRatings(),
  winners: loadWinners(),
  manifestDir: '',
  view: 'grid',
  filter: 'all',
};

function loadRatings() {
  try {
    return JSON.parse(localStorage.getItem(LS_KEY) || '{}');
  } catch {
    return {};
  }
}
function saveRatings() {
  localStorage.setItem(LS_KEY, JSON.stringify(state.ratings));
}
function loadWinners() {
  try {
    return JSON.parse(localStorage.getItem(LS_WINNERS) || '{}');
  } catch {
    return {};
  }
}
function saveWinners() {
  localStorage.setItem(LS_WINNERS, JSON.stringify(state.winners));
}

function setStatus(msg, cls = '') {
  const el = document.getElementById('status');
  el.textContent = msg;
  el.className = 'status ' + cls;
}

async function loadManifest() {
  const path = document.getElementById('manifest-path').value.trim();
  if (!path) {
    setStatus('Enter a manifest path', 'err');
    return;
  }
  state.manifestDir = path.replace(/[^/]+$/, '');
  try {
    const resp = await fetch(path, { cache: 'no-store' });
    if (!resp.ok) throw new Error('HTTP ' + resp.status);
    const data = await resp.json();
    state.assets = Array.isArray(data) ? data : data.assets || [];
    setStatus(`Loaded ${state.assets.length} assets`, 'ok');
    render();
  } catch (err) {
    state.assets = [];
    setStatus('Could not load manifest: ' + err.message, 'err');
    render();
  }
}

function resolvePath(asset) {
  const p = asset.path || asset.filename || '';
  if (/^https?:\/\//.test(p) || p.startsWith('/')) return p;
  return state.manifestDir + p;
}

function isImage(asset) {
  const t = (asset.type || '').toLowerCase();
  if (t === 'svg' || t === 'image' || t === 'png' || t === 'jpg' || t === 'jpeg') return true;
  const p = (asset.path || asset.filename || '').toLowerCase();
  return /\.(svg|png|jpe?g|webp|gif)$/.test(p);
}

function isSvg(asset) {
  const t = (asset.type || '').toLowerCase();
  if (t === 'svg') return true;
  return /\.svg$/.test((asset.path || asset.filename || '').toLowerCase());
}

const DANGEROUS_TAGS = new Set(['script', 'iframe', 'object', 'embed', 'foreignobject']);

function sanitizeSvg(rootEl) {
  const walker = document.createTreeWalker(rootEl, NodeFilter.SHOW_ELEMENT);
  const toRemove = [];
  let node = walker.currentNode;
  while (node) {
    if (node !== rootEl) {
      const tag = node.tagName.toLowerCase();
      if (DANGEROUS_TAGS.has(tag)) {
        toRemove.push(node);
      } else {
        for (const attr of Array.from(node.attributes)) {
          const name = attr.name.toLowerCase();
          const val = attr.value.trim().toLowerCase();
          if (name.startsWith('on')) node.removeAttribute(attr.name);
          else if ((name === 'href' || name === 'xlink:href') && val.startsWith('javascript:'))
            node.removeAttribute(attr.name);
        }
      }
    }
    node = walker.nextNode();
  }
  toRemove.forEach((n) => n.remove());
}

async function renderThumb(thumbEl, asset) {
  const url = resolvePath(asset);
  if (asset.variant) {
    const badge = document.createElement('div');
    badge.className = 'variant-badge';
    badge.textContent = 'V ' + asset.variant;
    thumbEl.appendChild(badge);
  }
  if (isSvg(asset)) {
    try {
      const resp = await fetch(url);
      if (!resp.ok) throw new Error();
      const text = await resp.text();
      const doc = new DOMParser().parseFromString(text, 'image/svg+xml');
      const svg = doc.documentElement;
      if (!svg || svg.tagName.toLowerCase() !== 'svg') throw new Error('not svg');
      sanitizeSvg(svg);
      const wrap = document.createElement('div');
      wrap.style.cssText =
        'width:100%;height:100%;display:flex;align-items:center;justify-content:center;';
      wrap.appendChild(document.importNode(svg, true));
      thumbEl.appendChild(wrap);
    } catch {
      showPlaceholder(thumbEl, 'SVG load failed');
    }
  } else if (isImage(asset)) {
    const img = document.createElement('img');
    img.src = url;
    img.alt = asset.filename || '';
    img.onerror = () => {
      thumbEl.replaceChildren();
      showPlaceholder(thumbEl, 'Image load failed');
    };
    thumbEl.appendChild(img);
  } else {
    showPlaceholder(thumbEl, (asset.type || 'unknown') + ' preview not supported');
  }
}

function showPlaceholder(thumbEl, text) {
  const p = document.createElement('div');
  p.className = 'placeholder';
  p.textContent = text;
  thumbEl.appendChild(p);
}

function currentRating(assetId) {
  return state.ratings[assetId] || { stars: 0, status: null, note: '', savedAt: null };
}

function buildCard(asset) {
  const tpl = document.getElementById('card-tpl').content.cloneNode(true);
  const card = tpl.querySelector('.card');
  const id = asset.id || asset.filename;
  card.dataset.id = id;

  const rating = currentRating(id);
  if (rating.status) card.classList.add('status-' + rating.status);

  tpl.querySelector('.fname').textContent = asset.filename || asset.path || id;

  const metaParts = [];
  if (asset.type) metaParts.push(asset.type.toUpperCase());
  if (typeof asset.cost === 'number') metaParts.push('$' + asset.cost.toFixed(4));
  if (asset.timestamp) metaParts.push(new Date(asset.timestamp).toLocaleString());
  if (asset.generation_id) metaParts.push('gen:' + asset.generation_id);
  tpl.querySelector('.meta').textContent = metaParts.join(' · ');

  const promptEl = tpl.querySelector('.prompt');
  if (asset.prompt) promptEl.textContent = asset.prompt;
  else promptEl.hidden = true;

  const starsEl = tpl.querySelector('.stars');
  for (let i = 1; i <= 5; i++) {
    const s = document.createElement('span');
    s.className = 'star' + (i <= rating.stars ? ' on' : '');
    s.textContent = '★';
    s.dataset.value = String(i);
    s.setAttribute('role', 'radio');
    s.setAttribute('aria-checked', i === rating.stars ? 'true' : 'false');
    s.addEventListener('click', () => {
      const cur = currentRating(id);
      cur.stars = cur.stars === i ? 0 : i;
      state.ratings[id] = cur;
      saveRatings();
      render();
    });
    starsEl.appendChild(s);
  }

  const approve = tpl.querySelector('.vote-btn.approve');
  const reject = tpl.querySelector('.vote-btn.reject');
  if (rating.status === 'approved') approve.classList.add('on');
  if (rating.status === 'rejected') reject.classList.add('on');
  approve.addEventListener('click', () => setAssetStatus(id, 'approved'));
  reject.addEventListener('click', () => setAssetStatus(id, 'rejected'));

  const note = tpl.querySelector('.note');
  note.value = rating.note || '';

  const savedAt = tpl.querySelector('.saved-at');
  if (rating.savedAt)
    savedAt.textContent = 'saved ' + new Date(rating.savedAt).toLocaleTimeString();

  tpl.querySelector('.save').addEventListener('click', () => {
    const cur = currentRating(id);
    cur.note = note.value;
    cur.savedAt = new Date().toISOString();
    state.ratings[id] = cur;
    saveRatings();
    render();
  });

  renderThumb(tpl.querySelector('.thumb'), asset);
  return tpl;
}

function setAssetStatus(id, value) {
  const cur = currentRating(id);
  cur.status = cur.status === value ? null : value;
  state.ratings[id] = cur;
  saveRatings();
  render();
}

function matchesFilter(asset) {
  if (state.filter === 'all') return true;
  const r = currentRating(asset.id || asset.filename);
  if (state.filter === 'unrated') return !r.status && !r.stars;
  return r.status === state.filter;
}

function renderGrid() {
  const grid = document.getElementById('grid-view');
  grid.replaceChildren();
  const list = state.assets.filter(matchesFilter);
  for (const asset of list) grid.appendChild(buildCard(asset));
}

function renderCompare() {
  const container = document.getElementById('compare-view');
  container.replaceChildren();
  const groups = new Map();
  for (const a of state.assets) {
    const gid = a.generation_id || '(ungrouped)';
    if (!groups.has(gid)) groups.set(gid, []);
    groups.get(gid).push(a);
  }
  for (const [gid, assets] of groups) {
    if (assets.length < 2 && gid === '(ungrouped)') continue;
    const group = document.createElement('section');
    group.className = 'group';

    const head = document.createElement('div');
    head.className = 'group-head';
    const h3 = document.createElement('h3');
    h3.textContent = assets[0].prompt || gid;
    const gidEl = document.createElement('span');
    gidEl.className = 'gid';
    gidEl.textContent = gid + ' · ' + assets.length + ' variants';
    head.append(h3, gidEl);
    group.appendChild(head);

    const variants = document.createElement('div');
    variants.className = 'variants';
    const winnerData = state.winners[gid] || { assetId: null, reason: '' };
    for (const a of assets) {
      const cell = document.createElement('div');
      cell.className = 'variant-cell';
      const aid = a.id || a.filename;
      if (winnerData.assetId === aid) cell.classList.add('winner');
      const thumb = document.createElement('div');
      thumb.className = 'thumb';
      renderThumb(thumb, a);
      const label = document.createElement('div');
      label.className = 'label';
      label.textContent = (a.variant ? '[' + a.variant + '] ' : '') + (a.filename || aid);
      cell.append(thumb, label);
      cell.addEventListener('click', () => {
        state.winners[gid] = {
          assetId: winnerData.assetId === aid ? null : aid,
          reason: winnerData.reason,
          savedAt: new Date().toISOString(),
        };
        saveWinners();
        render();
      });
      variants.appendChild(cell);
    }
    group.appendChild(variants);

    const wRow = document.createElement('div');
    wRow.className = 'winner-row';
    const reasonInput = document.createElement('input');
    reasonInput.type = 'text';
    reasonInput.placeholder = 'Winner reasoning (optional)';
    reasonInput.value = winnerData.reason || '';
    const saveBtn = document.createElement('button');
    saveBtn.className = 'btn primary';
    saveBtn.textContent = 'Save reason';
    saveBtn.addEventListener('click', () => {
      state.winners[gid] = {
        assetId: winnerData.assetId,
        reason: reasonInput.value,
        savedAt: new Date().toISOString(),
      };
      saveWinners();
      setStatus('Saved', 'ok');
    });
    wRow.append(reasonInput, saveBtn);
    group.appendChild(wRow);

    container.appendChild(group);
  }
  if (!container.children.length) {
    const p = document.createElement('p');
    p.style.color = 'var(--muted)';
    p.textContent = 'No grouped variants. Assets need a shared generation_id to appear here.';
    container.appendChild(p);
  }
}

function render() {
  const empty = document.getElementById('empty');
  const grid = document.getElementById('grid-view');
  const compare = document.getElementById('compare-view');
  if (!state.assets.length) {
    empty.hidden = false;
    grid.hidden = true;
    compare.hidden = true;
    return;
  }
  empty.hidden = true;
  if (state.view === 'grid') {
    grid.hidden = false;
    compare.hidden = true;
    renderGrid();
  } else {
    grid.hidden = true;
    compare.hidden = false;
    renderCompare();
  }
}

function exportJsonl() {
  const lines = [];
  for (const [id, r] of Object.entries(state.ratings)) {
    lines.push(JSON.stringify({ type: 'rating', asset_id: id, ...r }));
  }
  for (const [gid, w] of Object.entries(state.winners)) {
    lines.push(JSON.stringify({ type: 'winner', generation_id: gid, ...w }));
  }
  const blob = new Blob([lines.join('\n') + '\n'], { type: 'application/jsonl' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  a.download = `ratings-${stamp}.jsonl`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function wireUi() {
  document.querySelectorAll('.tab').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach((b) => b.classList.remove('on'));
      btn.classList.add('on');
      state.view = btn.dataset.view;
      render();
    });
  });
  document.getElementById('reload-btn').addEventListener('click', loadManifest);
  document.getElementById('export-btn').addEventListener('click', exportJsonl);
  document.getElementById('reset-btn').addEventListener('click', () => {
    if (!confirm('Clear all ratings and winners from localStorage?')) return;
    localStorage.removeItem(LS_KEY);
    localStorage.removeItem(LS_WINNERS);
    state.ratings = {};
    state.winners = {};
    render();
    setStatus('State cleared', 'ok');
  });
  document.getElementById('filter').addEventListener('change', (e) => {
    state.filter = e.target.value;
    render();
  });
}

wireUi();
loadManifest();

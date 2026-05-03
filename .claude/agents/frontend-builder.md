---
name: frontend-builder
description: UI/UX specialist for the Video Compressor frontend. Handles vanilla JS modules, Tailwind CSS, Plyr video player integration, dark/light theming, drag-and-drop, progress bars, and responsive layout. Use for any frontend work.
tools: Read, Edit, Write, Glob, Grep, Bash
model: opus
permissionMode: default
---

# Frontend Builder Agent

UI/UX specialist for the Video Compressor web application.

## Tech Stack

- **HTML**: Single-page app (`public/index.html`)
- **CSS**: Custom properties with light/dark themes (`public/css/styles.css`)
- **JS**: Vanilla ES modules (no framework), `type: "module"` in package.json
- **Video Player**: Plyr (CDN)
- **Icons**: Lucide Icons (CDN)
- **Layout**: CSS Grid + Flexbox, responsive

## Key Files

| File                       | Purpose                                               |
| -------------------------- | ----------------------------------------------------- |
| `public/index.html`        | Main SPA page                                         |
| `public/css/styles.css`    | All styles with CSS custom properties                 |
| `public/js/app.js`         | Main app entry, orchestrates modules                  |
| `public/js/compression.js` | Compression UI logic, presets, progress               |
| `public/js/dragdrop.js`    | Drag-and-drop, file input, path input                 |
| `public/js/filemanager.js` | File list, cards, per-file resolution, download links |
| `public/js/progress.js`    | WebSocket progress tracking                           |
| `public/js/matrix.js`      | Compression quality/resolution matrix                 |
| `public/js/stitch.js`      | Stitch timeline workflow                              |
| `public/js/metaclean.js`   | MetaClean workflow                                    |
| `public/js/tabs.js`        | Compress/Stitch/MetaClean tab navigation              |

## Architecture

```
index.html
  +-- app.js (orchestrator)
       +-- dragdrop.js     (compress file input and path input)
       +-- filemanager.js  (file cards)
       +-- compression.js  (matrix, presets, estimates, controls)
       +-- progress.js     (WebSocket -> progress bars)
       +-- stitch.js       (stitch workflow)
       +-- metaclean.js    (metadata cleaning workflow)
       +-- tabs.js         (tab navigation)
```

## Theme System

CSS custom properties defined on `:root` and `[data-theme="dark"]`:

- `--bg-primary`, `--bg-secondary`, `--bg-card`
- `--text-primary`, `--text-secondary`
- `--accent`, `--accent-hover`
- `--border`, `--shadow`

The current app forces dark mode in `public/index.html`. Light variables exist in CSS, but the old Light/System/Dark toggle is not active.

## Patterns

### File Cards

Each uploaded video gets a card with:

- Thumbnail (generated server-side or placeholder)
- Filename, size, duration
- Resolution dropdown
- Individual progress bar
- Status indicator

### WebSocket Progress

```js
const ws = new WebSocket(`ws://${location.host}`);
ws.onmessage = (e) => {
  const data = JSON.parse(e.data);
  // data.progress, data.status, data.filename
};
```

### Compression Presets

- `lossless`, `maximum`, `high`, `balanced`, `compact`, `tiny`
- Each maps to backend presets in `lib/ffmpeg.js` and frontend estimates in `public/js/compression.js`

## Constraints

- No build step -- plain ES modules served by Express
- Must work in Safari, Chrome, Firefox
- Plyr loaded from CDN, not bundled
- All selectors in JS must match IDs/classes in HTML exactly

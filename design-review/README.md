# Design Review

Local-only UI for reviewing generated design assets (SVG / PNG) from the
design-pipeline skill. No Firebase, no server, no build step.

## Run

```bash
cd "/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR/design-review"
python3 -m http.server 8080
```

Open http://localhost:8080 in a browser.

Opening `index.html` via `file://` also works for SVG/PNG that resolve to the
same directory tree, but browsers may block cross-directory `fetch()` of the
manifest. Prefer `python3 -m http.server` for reliability.

## What it expects

The design pipeline must write a manifest at:

```
../.agents/skills/design-pipeline/output/manifest.json
```

(The path is editable in the UI.)

Manifest shape:

```json
{
  "generated_at": "2026-04-21T12:00:00Z",
  "assets": [
    {
      "id": "asset-001",
      "generation_id": "gen-abc",
      "filename": "hero-v1.svg",
      "path": "hero-v1.svg",
      "type": "svg",
      "prompt": "hero banner...",
      "variant": "A",
      "cost": 0.012,
      "timestamp": "2026-04-21T12:00:00Z"
    }
  ]
}
```

`path` is resolved relative to the manifest file's directory. Absolute URLs
and absolute paths are used as-is.

Top-level array (`[{...}, {...}]`) is also accepted.

## What it does

- **Grid view** — every asset, inline SVG or `<img>`, with filename, type,
  cost, timestamp, prompt.
- **Compare view** — assets grouped by `generation_id`. Click a variant to
  mark it the winner. Add reasoning and save.
- **Rate** — 5-star rating per asset (click again to clear).
- **Approve / Reject** — mutually exclusive vote.
- **Notes** — free-text per asset.
- **Filter** — All / Unrated / Approved / Rejected.

## Persistence

State lives in `localStorage` under keys:

- `design-review:ratings:v1`
- `design-review:winners:v1`

Click **Download ratings.jsonl** to export everything as newline-delimited
JSON (one object per rating or winner decision). File name includes a
timestamp so repeated exports do not clobber.

## Reset

Click **Reset state** in the header, or clear the two `localStorage` keys
manually from devtools.

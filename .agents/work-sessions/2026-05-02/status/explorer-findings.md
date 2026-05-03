# Explorer Findings -- 2026-05-02

This file preserves the read-only explorer-agent findings from the protocol/audit planning pass.

## KINWOVEN Protocol Patterns

- `AGENTS.md` should be the source of truth.
- `CLAUDE.md` should be pointer-only.
- Add a quick-reference work-session protocol file.
- Use structured AI chat log entries with agent identity, confidence, evidence, findings, decisions, next steps, and result.
- Use root-level `RUNNING-LIST.md` and `DREAMS.jsonl`.
- Use `STATUS.md` every session and `TASK-MANIFEST.md` for 3+ tasks.
- Use descriptive `handoffs/` files instead of one generic handoff.
- Add a shared session-logging convention.

## Video Compressor Docs Drift

- `AGENTS.md` and `CLAUDE.md` were stale and duplicated each other.
- Old file trees mentioned deleted `public/js/theme.js`.
- Old file trees omitted `lib/exiftool.js`, `lib/stitch.js`, `public/js/tabs.js`, `public/js/metaclean.js`, `public/js/stitch.js`, `public/js/matrix.js`, and `public/js/timeline-deps.js`.
- Queue docs said one `PQueue` concurrency 4; current code uses HW concurrency 2 and SW concurrency 3.
- MetaClean, Stitch, and Download were listed as future plans even though routes/UI exist.
- Theme docs described Light/System/Dark localStorage toggle, but the app currently forces dark mode.
- Preset docs described old `max`, `balanced`, `small`, `streaming` names; current code uses six tiers.
- Some agent docs referenced nonexistent `lib/presets.js`.
- Skill files had a heading before YAML frontmatter; some Agent Skills parsers expect frontmatter at byte 0.

## Built Features Summary

- Compress: upload/probe, path input, thumbnails, Plyr preview, trim/crop, matrix, target-size helper, codec/format/audio/FPS/two-pass/metadata/fast-start controls, WebSocket progress, download links.
- Stitch: upload/probe, thumbnail timeline, SortableJS reorder, interact.js trim handles, optional compression, result download.
- MetaClean: ExifTool detection, image/video upload, attribution/privacy modes, surgical removal, removed/preserved report UI, clean download.
- Extra backend support: `/api/download`, `/api/metadata`, `/api/stitch/probe`.
- `lib/exiftool.js` includes `deepCleanVideo()`, but it is not wired to route/UI.

## Main Stress-Test Risks

- Stitch trim likely has request-shape drift: frontend sends `clip.trim`, backend/lib expect `trimStart`/`trimEnd`.
- Software/hardware encoder toggle appears estimate-only; backend still chooses hardware when available.
- Compression matrix may allow upscale choices; backend only skips scale when equal height.
- `stitchReencode()` assumes every clip has audio via `[i:a]`; silent clips may fail.
- Stitch runs inside HTTP request, outside `JobQueue`.
- Frontend uses `innerHTML` with user-controlled filenames/metadata in several places.
- `buildArgs()` broadly adds VideoToolbox decode flags, including software/non-mac scenarios.
- MetaClean uploaded outputs land in temp upload dir and can disappear after server restart cleanup.

## Tooling and QA Findings

- `.github/workflows/ci.yml` exists and runs ESLint, Prettier, backend syntax checks, and `npm audit --audit-level=high`.
- No app tests found and no `test` script.
- App-only syntax check passes.
- App-only Prettier check passes.
- App-only ESLint has warnings, no errors.
- `npm run lint` can fail locally because `eslint .` includes untracked `design-review/` and `.claude/worktrees/`.
- `npm run format:check` can fail locally on `.claude/worktrees/.../.claude/settings.local.json`.
- `npm audit --audit-level=high` reports high issues in `flatted`, `minimatch`, `path-to-regexp`; moderate issues in `brace-expansion`, `uuid`.

## Audit Dashboard Feasibility

- Static dashboard is feasible with no backend changes under `public/audit/`.
- Express already serves `public/`, so the dashboard would be available at `http://localhost:3000/audit/`.
- Recommended structure:
  - `public/audit/index.html`
  - `public/audit/routes.html`
  - `public/audit/frontend.html`
  - `public/audit/compression.html`
  - `public/audit/findings.html`
  - `public/audit/css/audit.css`
  - `public/audit/js/*.js`
  - `public/audit/data/audit.json`

## Recommended 8-Lane Audit

1. lead/synthesis
2. backend/API/security
3. FFmpeg/compression
4. frontend/UI
5. Stitch/MetaClean workflows
6. docs/skills/protocol
7. QA/stress/performance
8. iOS port strategy

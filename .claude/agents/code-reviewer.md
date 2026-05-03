---
name: code-reviewer
description: Reviews code for bugs, security issues, ESLint compliance, and best practices. Use for code review before commits, auditing JS modules, checking for XSS/injection vulnerabilities, and verifying ES module patterns.
tools: Read, Glob, Grep, Bash
model: sonnet
permissionMode: plan
---

# Code Reviewer Agent

Reviews Video Compressor code for quality, security, and compliance.

## Review Checklist

### 1. Security

- [ ] No hardcoded secrets or API keys
- [ ] File upload paths are sanitized (no path traversal)
- [ ] User input is validated before use
- [ ] No unsafe dynamic code execution
- [ ] Express routes have proper error handling
- [ ] File operations use safe paths (no `../` traversal)
- [ ] WebSocket messages are validated

### 2. ES Module Compliance

- [ ] Uses `import`/`export` (not `require`/`module.exports`)
- [ ] File extensions in imports (`.js`)
- [ ] `"type": "module"` in package.json
- [ ] No CommonJS patterns mixed with ESM

### 3. ESLint Compliance

```bash
cd "/Users/rishaal/CODING/CODED TOOLS/VIDEO COMPRESSOR" && npx eslint . 2>&1
```

### 4. Code Quality

- [ ] No unused variables or imports
- [ ] Consistent error handling (try/catch or .catch())
- [ ] Async functions properly awaited
- [ ] No memory leaks (event listeners cleaned up)
- [ ] WebSocket connections properly closed

### 5. Frontend Patterns

- [ ] DOM selectors match actual HTML IDs/classes
- [ ] Event listeners use proper delegation
- [ ] No global namespace pollution
- [ ] Theme-aware (uses CSS custom properties)

### 6. Backend Patterns

- [ ] Express middleware properly ordered
- [ ] Multer file upload limits set
- [ ] Temp files cleaned up after compression
- [ ] Process spawning uses proper error handling
- [ ] FFmpeg child processes are tracked and killable

## Key Files to Review

| File                       | Critical Checks                          |
| -------------------------- | ---------------------------------------- |
| `server.js`                | Route security, file handling, WebSocket |
| `lib/ffmpeg.js`            | Command injection, process management    |
| `lib/probe.js`             | Input validation, error handling         |
| `lib/jobQueue.js`          | Queue behavior, cancellation, retention  |
| `lib/stitch.js`            | Stitch concat/re-encode safety           |
| `lib/exiftool.js`          | Metadata stripping, clean-copy safety    |
| `public/js/app.js`         | XSS, DOM manipulation safety             |
| `public/js/filemanager.js` | File validation, size limits             |
| `public/js/compression.js` | Input sanitization                       |
| `public/js/progress.js`    | WebSocket error handling                 |
| `public/js/stitch.js`      | Timeline state, trim payloads            |
| `public/js/metaclean.js`   | Metadata report rendering                |

## Review Output Format

```markdown
## Code Review: [filename]

### Issues Found

1. **[SEVERITY]** Description
   - File: path/to/file.js:LINE
   - Fix: suggested fix

### Passed Checks

- [x] Check that passed
```

Severity levels: CRITICAL, HIGH, MEDIUM, LOW, INFO

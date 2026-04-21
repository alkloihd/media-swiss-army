/**
 * dragdrop.js - Drag-and-drop, file input, and path input handling
 */

import { addFilesToQueue, addFileByPath, showNotification } from './app.js';

const VIDEO_EXTENSIONS = [
  '.mp4',
  '.mkv',
  '.avi',
  '.mov',
  '.webm',
  '.wmv',
  '.flv',
  '.ts',
  '.m4v',
  '.mts',
  '.m2ts',
  '.mpg',
  '.mpeg',
  '.3gp',
  '.vob',
  '.ogv',
  '.f4v',
];

function isVideoFile(file) {
  // Check by MIME type
  if (file.type && file.type.startsWith('video/')) return true;

  // Check by extension
  const name = file.name.toLowerCase();
  return VIDEO_EXTENSIONS.some((ext) => name.endsWith(ext));
}

function showDropError(dropZone, message) {
  // Remove existing error
  const existing = dropZone.querySelector('.drop-error');
  if (existing) existing.remove();

  const errorEl = document.createElement('div');
  errorEl.className = 'drop-error';
  errorEl.textContent = message;
  dropZone.appendChild(errorEl);

  setTimeout(() => {
    errorEl.classList.add('drop-error-fade');
    setTimeout(() => errorEl.remove(), 400);
  }, 3000);
}

export function initDragDrop() {
  const dropZone = document.getElementById('drop-zone');
  const fileInput = document.getElementById('file-input');
  const pathInput = document.getElementById('path-input');
  const pathSubmit = document.getElementById('path-submit');

  if (!dropZone || !fileInput) return;

  // ─── Drag Events ─────────────────────────────────────────
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
    e.dataTransfer.dropEffect = 'copy';
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

  dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    e.stopPropagation();
    dragCounter = 0;
    dropZone.classList.remove('drag-over');

    const files = e.dataTransfer?.files;
    if (!files || files.length === 0) return;

    const videoFiles = Array.from(files).filter((f) => isVideoFile(f));
    const rejectedCount = files.length - videoFiles.length;

    if (videoFiles.length === 0) {
      showDropError(
        dropZone,
        'No valid video files found. Supported: MP4, MKV, AVI, MOV, WebM, etc.',
      );
      return;
    }

    if (rejectedCount > 0) {
      showNotification(`${rejectedCount} non-video file(s) skipped`, 'warning');
    }

    addFilesToQueue(videoFiles);
  });

  // ─── Click to Browse ─────────────────────────────────────
  dropZone.addEventListener('click', (e) => {
    // Don't trigger if clicking the path input area
    if (e.target.closest('#path-input-area')) return;
    fileInput.click();
  });

  fileInput.addEventListener('change', () => {
    const files = fileInput.files;
    if (!files || files.length === 0) return;

    const videoFiles = Array.from(files).filter((f) => isVideoFile(f));
    const rejectedCount = files.length - videoFiles.length;

    if (videoFiles.length === 0) {
      showDropError(dropZone, 'No valid video files selected.');
      fileInput.value = '';
      return;
    }

    if (rejectedCount > 0) {
      showNotification(`${rejectedCount} non-video file(s) skipped`, 'warning');
    }

    addFilesToQueue(videoFiles);
    fileInput.value = '';
  });

  // ─── Path Input ──────────────────────────────────────────
  if (pathInput && pathSubmit) {
    const submitPath = () => {
      const value = pathInput.value.trim();
      if (!value) {
        pathInput.classList.add('input-error');
        setTimeout(() => pathInput.classList.remove('input-error'), 2000);
        return;
      }

      // Support multiple paths separated by newlines or semicolons
      const paths = value
        .split(/[;\n]+/)
        .map((p) => p.trim())
        .filter(Boolean);

      for (const p of paths) {
        addFileByPath(p);
      }

      pathInput.value = '';
      pathInput.classList.remove('input-error');
    };

    pathSubmit.addEventListener('click', submitPath);

    pathInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        submitPath();
      }
    });
  }

  // ─── Prevent default browser drag behavior ───────────────
  document.addEventListener('dragover', (e) => e.preventDefault());
  document.addEventListener('drop', (e) => e.preventDefault());
}

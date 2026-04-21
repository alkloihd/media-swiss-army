/**
 * timeline-deps.js - Dynamically load interact.js for timeline trim handles
 */

let loadPromise = null;

export function loadInteract() {
  if (window.interact) return Promise.resolve(window.interact);

  if (loadPromise) return loadPromise;

  loadPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/interactjs/dist/interact.min.js';
    script.onload = () => resolve(window.interact);
    script.onerror = () => reject(new Error('Failed to load interact.js'));
    document.head.appendChild(script);
  });

  return loadPromise;
}

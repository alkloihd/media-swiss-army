/**
 * tabs.js - Tab navigation for Compress / Stitch / MetaClean
 */

export function initTabs() {
  const buttons = document.querySelectorAll('[data-tab-button]');
  const panels = document.querySelectorAll('[data-tab-panel]');

  buttons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.tabButton;

      // Update button states
      buttons.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');

      // Show/hide panels
      panels.forEach((p) => {
        p.style.display = p.dataset.tabPanel === target ? 'block' : 'none';
      });
    });
  });
}

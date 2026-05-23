// mosko-fintech vendored Mermaid initializer.
// Loads from local docs/_assets/mermaid.min.js (UMD bundle); no CDN fetch at view time.
// Per ADR-009 Decision 5 / sub-decision 3 — vendored runtime for fintech security posture.
// Used by docs/PRD/index.html, docs/ARCH/index.html, docs/SECURITY/index.html.

(function () {
  if (typeof mermaid === "undefined") {
    console.error("[mermaid-init] mermaid global not found. Ensure mermaid.min.js loads before mermaid-init.js.");
    return;
  }

  var darkMode = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;

  mermaid.initialize({
    startOnLoad: false,
    theme: darkMode ? "dark" : "default",
    securityLevel: "loose",
    flowchart: { curve: "basis" },
    themeVariables: {
      fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Inter, system-ui, sans-serif"
    }
  });

  window.addEventListener("DOMContentLoaded", function () {
    // Cache raw mermaid source before mermaid mutates it (used on theme switch).
    document.querySelectorAll(".mermaid").forEach(function (el) {
      if (!el.dataset.source) el.dataset.source = el.textContent;
    });
    mermaid.run();
  });

  // Re-render on dark/light mode toggle.
  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
      document.querySelectorAll(".mermaid").forEach(function (el) {
        el.removeAttribute("data-processed");
        el.innerHTML = el.dataset.source || el.textContent;
      });
      location.reload();
    });
  }
})();

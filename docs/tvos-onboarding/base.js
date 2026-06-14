/* base.js — shared helpers for the first-run mockups
   - scales each 1920×1080 .stage-inner to fit its column
   - renders deterministic faux-QR codes into .qr[data-qr]
   - subtle scroll reveal for frames (reduce-motion aware)
*/
(function () {
  "use strict";

  /* ---- 1920×1080 fit-to-width scaler ---- */
  function fit() {
    document.querySelectorAll(".stage").forEach(function (stage) {
      var inner = stage.querySelector(".stage-inner");
      if (!inner) return;
      var w = stage.clientWidth;
      var scale = w / 1920;
      inner.style.setProperty("--scale", scale.toFixed(4));
      stage.style.height = Math.round(1080 * scale) + "px";
    });
  }

  /* ---- Deterministic QR-ish renderer (visual only, not scannable) ---- */
  function seeded(seed) {
    var s = 0;
    for (var i = 0; i < seed.length; i++) s = (s * 31 + seed.charCodeAt(i)) >>> 0;
    return function () { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  }
  function finder(x, y) {
    return (
      '<rect x="' + x + '" y="' + y + '" width="7" height="7" rx="1.4" fill="#0a0a0a"/>' +
      '<rect x="' + (x + 1) + '" y="' + (y + 1) + '" width="5" height="5" rx="1" fill="#fff"/>' +
      '<rect x="' + (x + 2) + '" y="' + (y + 2) + '" width="3" height="3" rx="0.6" fill="#0a0a0a"/>'
    );
  }
  function renderQR(el) {
    var n = 25; // modules
    var rnd = seeded(el.getAttribute("data-qr") || "silo");
    var cells = "";
    function reserved(r, c) {
      return (r < 8 && c < 8) || (r < 8 && c > n - 9) || (r > n - 9 && c < 8);
    }
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (reserved(r, c)) continue;
        if (rnd() > 0.52) {
          cells += '<rect x="' + c + '" y="' + r + '" width="1" height="1" fill="#0a0a0a"/>';
        }
      }
    }
    var svg =
      '<svg viewBox="0 0 ' + n + ' ' + n + '" shape-rendering="crispEdges">' +
      '<rect width="' + n + '" height="' + n + '" fill="#fff"/>' +
      cells +
      finder(0, 0) + finder(n - 7, 0) + finder(0, n - 7) +
      "</svg>";
    el.innerHTML = svg;
  }

  function reveal() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    document.documentElement.classList.add("has-reveal");
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
      });
    }, { threshold: 0.12 });
    document.querySelectorAll(".stage").forEach(function (s) { io.observe(s); });
  }

  function init() {
    document.querySelectorAll(".qr[data-qr]").forEach(renderQR);
    fit();
    reveal();
  }

  window.addEventListener("resize", fit);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else { init(); }
})();

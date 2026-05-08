// Corely — Initialization bridge scripts
// Externalisé pour respecter CSP Manifest V3 (pas de scripts inline)
'use strict';

// Helper: dispatch CustomEvent from Dart
function dispatchCustomEvent(type, detail) {
  var event;
  if (detail !== null && detail !== undefined) {
    event = new CustomEvent(type, { detail: detail });
  } else {
    event = new CustomEvent(type);
  }
  window.dispatchEvent(event);
}

// Hide loading spinner on first Flutter frame
window.addEventListener('flutter-first-frame', function () {
  var loading = document.getElementById('loading');
  if (loading) loading.style.display = 'none';
});

// Diagnostics : si Flutter ne charge pas en 30s, afficher l'erreur
window.__corelyLoadStart = Date.now();
setTimeout(function () {
  var el = document.getElementById('loading');
  if (el && el.style.display !== 'none') {
    console.error('[Corely] Flutter n\'a pas chargé en 30s. Vérifiez la console pour les erreurs.');
    el.innerHTML = '<div style="color:#ff6b6b;text-align:center;padding:20px;font-size:14px;">'
      + 'Erreur de chargement<br><small>Ouvrez la console (F12) pour les détails</small></div>';
  }
}, 30000);

// Capturer les erreurs JS globales
window.onerror = function (msg, url, line, col, error) {
  console.error('[Corely JS Error]', msg, url, line, col, error);
};
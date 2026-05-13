// Corely — Initialization bridge scripts
// Externalisé pour respecter CSP Manifest V3 (pas de scripts inline)
'use strict';

// ── CSP Manifest V3 : interception complète des scripts ─────────────────────
// Chrome Manifest V3 bloque les scripts inline ET les scripts externes non-extension.
// On intercepte TOUTE création et insertion de <script> pour :
// 1. Bloquer les scripts externes (Google Sign-In, analytics, etc.)
// 2. Exécuter les scripts inline via new Function() au lieu du DOM
// 3. Laisser passer les scripts locaux de l'extension (même origine)

var _origCreateElement = document.createElement.bind(document);
var _origSetAttribute = Element.prototype.setAttribute;
var _origAppendChild = Node.prototype.appendChild;
var _origInsertBefore = Node.prototype.insertBefore;

// Vérifier si un src est autorisé (même origine que l'extension)
function _isAllowedSrc(src) {
  if (!src) return true;
  // Autoriser les scripts locaux à l'extension
  if (src.indexOf('chrome-extension://') === 0) return true;
  // Autoriser les chemins relatifs et absolus locaux
  if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) return false;
  // Autoriser les chemins relatifs (sans protocole)
  return true;
}

// Exécuter un script inline capturé
function _executeInlineScript(text) {
  if (text && text.trim().length > 0) {
    try { new Function(text)(); }
    catch (e) { console.debug('[Corely CSP] Script inline ignoré:', e.message); }
  }
}

// Créer un élément script "fantôme" qui remplace un script bloqué
// Le fantôme simule le chargement réussi pour que le code appelant ne bloque pas
function _createGhostScript(originalSrc) {
  var ghost = _origCreateElement('script');
  // Simuler le chargement réussi avec un délai
  setTimeout(function() {
    ghost.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
  }, 10);
  return ghost;
}

// Intercepter document.createElement pour capturer les scripts inline
document.createElement = function (tagName, options) {
  var el = _origCreateElement(tagName, options);
  if (tagName && tagName.toLowerCase() === 'script') {
    var inlineContent = '';

    // Intercepter textContent pour les scripts inline
    var _origTextContent = Object.getOwnPropertyDescriptor(Node.prototype, 'textContent');
    Object.defineProperty(el, 'textContent', {
      get: function () { return _origTextContent.get.call(this); },
      set: function (text) {
        if (text && !this.getAttribute('src')) {
          inlineContent = text;
          // Ne PAS définir textContent sur l'élément (CSP le bloquerait)
          _origTextContent.set.call(this, '');
        } else {
          inlineContent = '';
          _origTextContent.set.call(this, text);
        }
      },
      configurable: true,
      enumerable: true
    });

    // Stocker le contenu inline pour appendChild/insertBefore
    el.__corely_inline = function () {
      _executeInlineScript(inlineContent);
      inlineContent = '';
    };
  }
  return el;
};

// Intercepter setAttribute pour bloquer les scripts externes à la source
Element.prototype.setAttribute = function (name, value) {
  if (this.nodeName === 'SCRIPT' && name.toLowerCase() === 'src') {
    if (!_isAllowedSrc(value)) {
      console.debug('[Corely CSP] Script externe bloqué (setAttribute):', value);
      // Ne PAS définir le src — empêcher le chargement
      // Mais simuler un événement load pour ne pas bloquer l'appelant
      var self = this;
      setTimeout(function() {
        self.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
      }, 10);
      return;
    }
  }
  return _origSetAttribute.call(this, name, value);
};

// Intercepter appendChild pour gérer les scripts
Node.prototype.appendChild = function (child) {
  if (child && child.nodeName === 'SCRIPT') {
    var src = child.getAttribute && child.getAttribute('src');

    // Script avec src externe — bloquer
    if (src && !_isAllowedSrc(src)) {
      console.debug('[Corely CSP] Script externe bloqué (appendChild):', src);
      // Simuler le chargement réussi
      setTimeout(function() {
        child.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
      }, 10);
      return child;
    }

    // Script inline capturé — exécuter via Function()
    if (child.__corely_inline) {
      child.__corely_inline();
      // Simuler le chargement réussi
      setTimeout(function() {
        child.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
      }, 10);
      return child;
    }

    // Script inline avec textContent direct
    var text = child.textContent || child.innerText || '';
    if (text && text.trim().length > 0 && !child.getAttribute('src')) {
      _executeInlineScript(text);
      setTimeout(function() {
        child.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
      }, 10);
      return child;
    }

    // Script autorisé (local) — ajouter au DOM
    return _origAppendChild.call(this, child);
  }
  return _origAppendChild.call(this, child);
};

// Intercepter insertBefore (utilisé par Flutter pour insérer des scripts)
Node.prototype.insertBefore = function (newNode, referenceNode) {
  if (newNode && newNode.nodeName === 'SCRIPT') {
    var src = newNode.getAttribute && newNode.getAttribute('src');

    // Script avec src externe — bloquer
    if (src && !_isAllowedSrc(src)) {
      console.debug('[Corely CSP] Script externe bloqué (insertBefore):', src);
      setTimeout(function() {
        newNode.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
      }, 10);
      return newNode;
    }

    // Script inline capturé
    if (newNode.__corely_inline) {
      newNode.__corely_inline();
      setTimeout(function() {
        newNode.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
      }, 10);
      return newNode;
    }

    // Script inline avec textContent direct
    var text = newNode.textContent || newNode.innerText || '';
    if (text && text.trim().length > 0 && !newNode.getAttribute('src')) {
      _executeInlineScript(text);
      setTimeout(function() {
        newNode.dispatchEvent(new Event('load', { bubbles: false, cancelable: false }));
      }, 10);
      return newNode;
    }

    return _origInsertBefore.call(this, newNode, referenceNode);
  }
  return _origInsertBefore.call(this, newNode, referenceNode);
};

// ── Helper: dispatch CustomEvent from Dart ─────────────────────────────────
function dispatchCustomEvent(type, detail) {
  var event;
  if (detail !== null && detail !== undefined) {
    event = new CustomEvent(type, { detail: detail });
  } else {
    event = new CustomEvent(type);
  }
  window.dispatchEvent(event);
}

// ── Loading spinner + diagnostics ──────────────────────────────────────────
window.addEventListener('flutter-first-frame', function () {
  var loading = document.getElementById('loading');
  if (loading) loading.style.display = 'none';
});

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
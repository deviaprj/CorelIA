// Corely — Content Script
// Capture le texte sélectionné et l'envoie au background SW.
// Écoute les demandes de résumé de page depuis le side panel.
'use strict';

// ── Sélection de texte ───────────────────────────────────────────────────────
document.addEventListener('mouseup', () => {
  const selected = window.getSelection()?.toString().trim();
  if (selected && selected.length > 0) {
    chrome.runtime.sendMessage({
      type: 'SELECTION_CHANGED',
      text: selected,
    }).catch(() => {
      // Extension peut être déchargée — ignorer
    });
  }
});

// ── Résumé de page ────────────────────────────────────────────────────────────
// Écoute les messages du side panel demandant un résumé de la page courante
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'GET_PAGE_CONTENT') {
    const pageContent = extractPageContent();
    sendResponse({
      title: document.title,
      url: window.location.href,
      content: pageContent,
    });
  }
  return false; // Synchrone
});

/// Extrait le contenu principal de la page (texte lisible).
/// Priorise les éléments sémantiques HTML, fallback au body complet.
function extractPageContent() {
  // 1. Essayer les éléments sémantiques principaux
  const selectors = [
    'article',
    'main',
    '[role="main"]',
    '.post-content',
    '.article-body',
    '.entry-content',
    '#content',
    '#main-content',
  ];

  for (const selector of selectors) {
    const el = document.querySelector(selector);
    if (el && el.textContent.trim().length > 100) {
      return cleanText(el.textContent);
    }
  }

  // 2. Fallback : body complet, limité à 15000 caractères
  return cleanText(document.body.textContent).substring(0, 15000);
}

/// Nettoie le texte brut (espaces multiples, lignes vides).
function cleanText(text) {
  return text
    .replace(/\s+/g, ' ')
    .replace(/\n\s*\n/g, '\n\n')
    .trim();
}
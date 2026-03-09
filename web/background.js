// AironBot — Service Worker (Manifest V3)
'use strict';

// ── Initialisation ────────────────────────────────────────────────────────────
chrome.runtime.onInstalled.addListener(() => {
  // Menu contextuel "Demander à AironBot"
  chrome.contextMenus.create({
    id: 'ask_aironbot',
    title: 'Demander à AironBot : "%s"',
    contexts: ['selection'],
  });

  // Activer le side panel sur clic sur l'icône
  chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
});

// ── Clic sur l'icône action ───────────────────────────────────────────────────
chrome.action.onClicked.addListener((tab) => {
  chrome.sidePanel.open({ tabId: tab.id });
});

// ── Menu contextuel ───────────────────────────────────────────────────────────
chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== 'ask_aironbot') return;

  const selectedText = info.selectionText ?? '';
  if (!selectedText) return;

  // Ouvrir le side panel et envoyer le texte sélectionné
  chrome.sidePanel.open({ tabId: tab.id }, () => {
    // Délai pour laisser l'UI Flutter s'initialiser
    setTimeout(() => {
      chrome.runtime.sendMessage({
        type: 'SELECTED_TEXT',
        text: selectedText,
      });
    }, 800);
  });
});

// ── Messages depuis content_script ou l'UI Flutter ───────────────────────────
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'PING') {
    sendResponse({ status: 'ok' });
  }
  // Laisser les autres messages passer (async)
  return false;
});

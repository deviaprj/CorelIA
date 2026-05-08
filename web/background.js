// Corely — Service Worker (Manifest V3)
'use strict';

// ── Initialisation ────────────────────────────────────────────────────────────
chrome.runtime.onInstalled.addListener(() => {
  // Menu contextuel "Demander à Corely"
  chrome.contextMenus.create({
    id: 'ask_corely',
    title: 'Demander à Corely : "%s"',
    contexts: ['selection'],
  });

  // Ouvrir le side panel au clic sur l'icône d'action
  chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
});

// ── Menu contextuel ───────────────────────────────────────────────────────────
chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId !== 'ask_corely') return;

  const selectedText = info.selectionText ?? '';
  if (!selectedText) return;

  // Ouvrir le side panel et envoyer le texte sélectionné
  chrome.sidePanel.open({ tabId: tab.id }, () => {
    // Délai pour laisser l'UI Flutter s'initialiser
    setTimeout(() => {
      chrome.runtime.sendMessage({
        type: 'SELECTED_TEXT',
        text: selectedText,
      }).catch(() => {});
    }, 800);
  });
});

// ── Messages depuis content_script ou l'UI Flutter ───────────────────────────
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === 'PING') {
    sendResponse({ status: 'ok' });
    return false;
  }

  // Relayer les messages vers le side panel via chrome.storage.local
  // Le bridge Flutter dans le side panel lit ces événements
  if (message.type === 'SELECTED_TEXT' || message.type === 'PAGE_CONTENT') {
    chrome.storage.local.set({
      pendingExtensionEvent: {
        type: message.type,
        detail: message.type === 'SELECTED_TEXT'
            ? { text: message.text }
            : { title: message.title, url: message.url, content: message.content },
        timestamp: Date.now(),
      },
    });
    // Notifier le side panel qu'un événement est en attente
    chrome.runtime.sendMessage({ type: 'EXTENSION_EVENT_PENDING' }).catch(() => {});
  }

  return false;
});
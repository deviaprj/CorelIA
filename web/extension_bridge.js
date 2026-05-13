// Corely — Extension Bridge
// Pont entre le background SW (chrome.runtime) et le side panel Flutter.
// Écoute les messages du SW et les convertit en CustomEvents sur window
// pour que le code Dart puisse les capter via dart:js_interop.
'use strict';

(function initExtensionBridge() {
  // Vérifier qu'on est dans une extension Chrome
  if (typeof chrome === 'undefined' || !chrome.runtime) {
    console.warn('[ExtensionBridge] chrome.runtime non disponible.');
    return;
  }

  // Écouter les messages du background SW
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (!message || !message.type) return false;

    switch (message.type) {
      case 'SELECTED_TEXT':
        // Texte sélectionné via menu contextuel "Demander à Corely"
        window.dispatchEvent(new CustomEvent('corely_selected_text', {
          detail: { text: message.text || '' },
        }));
        break;

      case 'PAGE_CONTENT':
        // Contenu de page envoyé par le content script
        window.dispatchEvent(new CustomEvent('corely_page_content', {
          detail: {
            title: message.title || '',
            url: message.url || '',
            content: message.content || '',
          },
        }));
        break;

      case 'EXTENSION_EVENT_PENDING':
        // Le SW signale qu'un événement est en attente dans chrome.storage
        // Lire et traiter l'événement
        if (chrome.storage && chrome.storage.local) {
          chrome.storage.local.get('pendingExtensionEvent', (result) => {
            if (result && result.pendingExtensionEvent) {
              const event = result.pendingExtensionEvent;
              const now = Date.now();
              if (event.timestamp && (now - event.timestamp) < 5000) {
                if (event.type === 'SELECTED_TEXT') {
                  window.dispatchEvent(new CustomEvent('corely_selected_text', {
                    detail: event.detail || {},
                  }));
                } else if (event.type === 'PAGE_CONTENT') {
                  window.dispatchEvent(new CustomEvent('corely_page_content', {
                    detail: event.detail || {},
                  }));
                }
              }
              // Nettoyer l'événement traité
              chrome.storage.local.remove('pendingExtensionEvent');
            }
          });
        }
        break;

      case 'BROWSER_ACTION_RESULT':
        // Résultat d'une action navigateur relayé par le background SW
        // Forward au CustomEvent pour que browser_actions.js le capte
        // (browser_actions.js écoute aussi chrome.runtime.onMessage directement)
        window.dispatchEvent(new CustomEvent('corely_browser_action_result', {
          detail: message.detail || message,
        }));
        break;
    }

    sendResponse({ received: true });
    return false;
  });

  // Écouter les demandes du code Flutter (ex: extraire le contenu de la page)
  window.addEventListener('corely_request_page_content', () => {
    // Envoyer un message au content script pour extraire le contenu de la page
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs && tabs[0] && tabs[0].id) {
        chrome.tabs.sendMessage(tabs[0].id, { type: 'GET_PAGE_CONTENT' }, (response) => {
          if (response) {
            window.dispatchEvent(new CustomEvent('corely_page_content', {
              detail: {
                title: response.title || '',
                url: response.url || '',
                content: response.content || '',
              },
            }));
          }
        });
      }
    });
  });

  console.info('[ExtensionBridge] Initialisé (chrome.runtime.onMessage).');
})();
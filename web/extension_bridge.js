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
        // Relay result from background SW to Flutter via CustomEvent
        window.dispatchEvent(new CustomEvent('corely_browser_action_result', {
          detail: message.detail || message,
        }));
        break;
    }

    sendResponse({ received: true });
    return false;
  });

  // ── Écouter les actions navigateur du code Flutter ──────────────────────
  window.addEventListener('corely_browser_action', (event) => {
    const detail = event.detail;
    if (!detail || !detail.action) return;

    console.info('[ExtensionBridge] Browser action reçue:', detail.action, detail.actionId);

    // Récupérer le tabId actif pour les actions qui en ont besoin
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const tabId = (tabs && tabs[0] && tabs[0].id) ? tabs[0].id : null;

      const message = {
        type: 'BROWSER_ACTION',
        actionId: detail.actionId,
        action: detail.action,
        params: detail.params || {},
        tabId: tabId,
      };

      chrome.runtime.sendMessage(message).then((response) => {
        // Réponse du background SW — forwarder au Dart via CustomEvent
        if (response && !response.success && response.error) {
          console.warn('[ExtensionBridge] Réponse action:', detail.actionId, 'success: false, error:', response.error);
        } else {
          console.info('[ExtensionBridge] Réponse action:', detail.actionId, 'success:', response?.success);
        }
        window.dispatchEvent(new CustomEvent('corely_browser_action_result', {
          detail: {
            actionId: detail.actionId,
            action: detail.action,
            success: response?.success ?? false,
            data: response?.data ?? null,
            error: response?.error ?? null,
          },
        }));
      }).catch((err) => {
        console.error('[ExtensionBridge] Erreur action:', detail.actionId, err.message || String(err));
        window.dispatchEvent(new CustomEvent('corely_browser_action_result', {
          detail: {
            actionId: detail.actionId,
            action: detail.action,
            success: false,
            data: null,
            error: err.message || String(err),
          },
        }));
      });
    });
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
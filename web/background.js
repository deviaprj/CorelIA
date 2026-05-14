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

  // ── Browser actions ──────────────────────────────────────────────────────
  if (message.type === 'BROWSER_ACTION') {
    handleBrowserAction(message, _sender, sendResponse);
    return true; // Keep channel open for async response
  }

  return false;
});

// ── Browser action handler ─────────────────────────────────────────────────
async function handleBrowserAction(message, _sender, sendResponse) {
  var actionId = message.actionId;
  var action = message.action;
  var params = message.params || {};
  var tabId = message.tabId;

  try {
    switch (action) {
      // ── Navigation actions (chrome.tabs API) ──────────────────────────────
      case 'OPEN_URL': {
        var tab = await chrome.tabs.create({ url: params.url });
        sendResponse({ success: true, data: { tabId: tab.id, url: tab.url || params.url } });
        break;
      }

      case 'NAVIGATE_BACK': {
        var backTabId = tabId || await getActiveTabId();
        if (backTabId) {
          await chrome.tabs.goBack(backTabId);
          var backTab = await chrome.tabs.get(backTabId);
          sendResponse({ success: true, data: { url: backTab.url } });
        } else {
          sendResponse({ success: false, error: 'No active tab' });
        }
        break;
      }

      case 'NAVIGATE_FORWARD': {
        var fwdTabId = tabId || await getActiveTabId();
        if (fwdTabId) {
          await chrome.tabs.goForward(fwdTabId);
          var fwdTab = await chrome.tabs.get(fwdTabId);
          sendResponse({ success: true, data: { url: fwdTab.url } });
        } else {
          sendResponse({ success: false, error: 'No active tab' });
        }
        break;
      }

      case 'SCREENSHOT': {
        var dataUrl = await chrome.tabs.captureVisibleTab(null, { format: 'png' });
        sendResponse({ success: true, data: { dataUrl: dataUrl } });
        break;
      }

      // ── DOM actions (chrome.scripting.executeScript) ──────────────────────
      case 'CLICK_ELEMENT':
      case 'FILL_FORM':
      case 'SCROLL':
      case 'EXTRACT_TEXT':
      case 'EXTRACT_LINKS':
      case 'EXTRACT_TABLES':
      case 'EXTRACT_FORMS':
      case 'EXTRACT_MEDIA':
      case 'PAGE_METADATA':
      case 'HIGHLIGHT_ELEMENT':
      case 'AUTOFILL_PAGE':
      case 'WAIT_FOR_SELECTOR':
      case 'GET_ELEMENT_INFO': {
        var domTabId = tabId || await getActiveTabId();
        if (!domTabId) {
          sendResponse({ success: false, error: 'No active tab' });
          break;
        }

        // Helper: send DOM_ACTION message with 8s timeout
        var sendDomMessage = function (targetTabId) {
          return new Promise(function (resolve, reject) {
            var timer = setTimeout(function () {
              resolve({ success: false, error: 'DOM action timed out (8s)' });
            }, 8000);

            chrome.tabs.sendMessage(targetTabId, {
              type: 'DOM_ACTION',
              action: action,
              params: params,
            }, function (response) {
              clearTimeout(timer);
              if (chrome.runtime.lastError) {
                resolve({ success: false, error: chrome.runtime.lastError.message });
              } else {
                resolve(response || { success: false, error: 'No response from DOM script' });
              }
            });
          });
        };

        // Try sending message first (dom_actions.js may already be injected)
        var domResults = await sendDomMessage(domTabId);

        // If content script not ready, inject it and retry once
        if (!domResults.success && domResults.error &&
            (domResults.error.includes('Could not establish connection') ||
             domResults.error.includes('Receiving end does not exist') ||
             domResults.error.includes('The message port closed'))) {

          console.info('[Background] Injecting dom_actions.js into tab', domTabId);
          try {
            await chrome.scripting.executeScript({
              target: { tabId: domTabId },
              files: ['dom_actions.js'],
            });
            // Small delay for script initialization
            await new Promise(function (r) { setTimeout(r, 200); });
            domResults = await sendDomMessage(domTabId);
          } catch (injectErr) {
            domResults = { success: false, error: 'Script injection failed: ' + (injectErr.message || String(injectErr)) };
          }
        }

        sendResponse(domResults);
        break;
      }

      // ── Content actions (forwarded to content script) ─────────────────────
      case 'GET_PAGE_CONTENT':
      case 'SUMMARIZE_PAGE': {
        var contentTabId = tabId || await getActiveTabId();
        if (!contentTabId) {
          sendResponse({ success: false, error: 'No active tab' });
          break;
        }
        var contentResults = await new Promise(function (resolve) {
          chrome.tabs.sendMessage(contentTabId, {
            type: action,
            params: params,
          }, function (response) {
            if (chrome.runtime.lastError) {
              resolve({ success: false, error: chrome.runtime.lastError.message });
            } else {
              resolve(response || { success: false, error: 'No response from content script' });
            }
          });
        });
        sendResponse(contentResults);
        break;
      }

      // ── Download action ────────────────────────────────────────────────────
      case 'DOWNLOAD': {
        var urls = params.urls || [params.url];
        var downloaded = [];
        for (var i = 0; i < urls.length; i++) {
          try {
            var downloadId = await chrome.downloads.download({
              url: urls[i],
              filename: params.filename || undefined,
              saveAs: false,
            });
            downloaded.push({ url: urls[i], id: downloadId, success: true });
          } catch (dlErr) {
            downloaded.push({ url: urls[i], success: false, error: dlErr.message || String(dlErr) });
          }
        }
        sendResponse({ success: true, data: { downloaded: downloaded } });
        break;
      }

      // ── PDF generation ─────────────────────────────────────────────────────
      case 'SAVE_AS_PDF': {
        var pdfTabId = tabId || await getActiveTabId();
        if (!pdfTabId) {
          sendResponse({ success: false, error: 'No active tab' });
          break;
        }
        // Use chrome.printing.submitJob if available (Chrome 116+),
        // otherwise fall back to injecting window.print() in the page
        try {
          await chrome.scripting.executeScript({
            target: { tabId: pdfTabId },
            func: function (opts) {
              // Create a minimal print dialog that auto-saves as PDF
              // Most users have "Save as PDF" in their print dialog
              window.print();
              return { printed: true };
            },
            args: [{ filename: params.filename || 'page' }],
          });
          sendResponse({ success: true, data: { message: 'Print dialog opened' } });
        } catch (pdfErr) {
          sendResponse({ success: false, error: pdfErr.message || String(pdfErr) });
        }
        break;
      }

      default:
        sendResponse({ success: false, error: 'Unknown action: ' + action });
    }
  } catch (err) {
    sendResponse({ success: false, error: err.message || String(err) });
  }
}

async function getActiveTabId() {
  var tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  return (tabs && tabs[0] && tabs[0].id) ? tabs[0].id : null;
}
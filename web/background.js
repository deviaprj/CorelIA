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

function normalizeExternalUrl(inputUrl) {
  if (!inputUrl || typeof inputUrl !== 'string') return null;
  const raw = inputUrl.trim();
  if (!raw) return null;

  const shortcuts = {
    google: 'google.com',
    youtube: 'youtube.com',
    gmail: 'gmail.com',
    github: 'github.com',
    wikipedia: 'wikipedia.org',
    x: 'x.com',
    twitter: 'x.com',
  };

  const completeHostname = (hostname) => {
    const lower = hostname.toLowerCase();
    if (lower.includes('.')) return hostname;
    return shortcuts[lower] || `${lower}.com`;
  };

  if (/^(mailto|tel):/i.test(raw)) return raw;
  if (/\s/.test(raw) && !raw.includes('/') && !raw.includes('.')) {
    return `https://${completeHostname(raw)}`;
  }

  let candidate = raw;
  if (candidate.startsWith('//')) candidate = `https:${candidate}`;
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(candidate)) {
    candidate = `https://${candidate.replace(/^\/+/, '')}`;
  }

  try {
    const parsed = new URL(candidate);
    parsed.hostname = completeHostname(parsed.hostname);
    return parsed.toString();
  } catch (_) {
    return null;
  }
}

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
        const normalizedUrl = normalizeExternalUrl(params.url);
        if (!normalizedUrl) {
          sendResponse({ success: false, error: 'Invalid URL' });
          break;
        }
        try {
          var tab = await Promise.race([
            chrome.tabs.create({ url: normalizedUrl }),
            new Promise((_, rej) => setTimeout(() => rej(new Error('Tab creation timed out (8s)')), 8000)),
          ]);
          sendResponse({ success: true, data: { tabId: tab.id, url: tab.url || normalizedUrl } });
        } catch (urlErr) {
          sendResponse({ success: false, error: urlErr.message || String(urlErr) });
        }
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
            // Wait for script initialization (listener setup)
            await new Promise(function (r) { setTimeout(r, 500); });
            domResults = await sendDomMessage(domTabId);
          } catch (injectErr) {
            domResults = { success: false, error: 'Script injection failed: ' + (injectErr.message || String(injectErr)) };
          }
        }

        sendResponse(domResults);
        break;
      }

      // ── Content actions (extracted directly via scripting API) ────────────
      case 'GET_PAGE_CONTENT':
      case 'SUMMARIZE_PAGE': {
        var contentTabId = tabId || await getActiveTabId();
        if (!contentTabId) {
          sendResponse({ success: false, error: 'No active tab' });
          break;
        }
        try {
          var injectionResults = await Promise.race([
            chrome.scripting.executeScript({
              target: { tabId: contentTabId },
              func: function () {
                // Extract readable page content
                var selectors = [
                  'article', 'main', '[role="main"]',
                  '.post-content', '.article-body', '.entry-content',
                  '#content', '#main-content'
                ];
                for (var i = 0; i < selectors.length; i++) {
                  var el = document.querySelector(selectors[i]);
                  if (el && el.textContent.trim().length > 100) {
                    return {
                      title: document.title,
                      url: window.location.href,
                      content: el.textContent.replace(/\s+/g, ' ').trim().substring(0, 15000),
                      success: true
                    };
                  }
                }
                return {
                  title: document.title,
                  url: window.location.href,
                  content: (document.body ? document.body.textContent : '').replace(/\s+/g, ' ').trim().substring(0, 15000),
                  success: true
                };
              }
            }),
            new Promise(function (_, rej) {
              setTimeout(function () { rej(new Error('Content extraction timed out (8s)')); }, 8000);
            })
          ]);
          if (injectionResults && injectionResults[0] && injectionResults[0].result) {
            sendResponse({ success: true, data: injectionResults[0].result });
          } else {
            sendResponse({ success: false, error: 'No content extracted' });
          }
        } catch (injectErr) {
          sendResponse({ success: false, error: injectErr.message || String(injectErr) });
        }
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

      // ── Binary document download (base64 payload) ───────────────────────
      case 'DOWNLOAD_DATA': {
        var contentBase64 = (params.contentBase64 || '').trim();
        var mimeType = (params.mimeType || 'application/octet-stream').trim();
        var filename = (params.filename || 'corely_document').trim();

        if (!contentBase64) {
          sendResponse({ success: false, error: 'Missing contentBase64 payload' });
          break;
        }

        try {
          // Manifest V3 service workers have no DOM — URL.createObjectURL is unavailable.
          // chrome.downloads.download() accepts data URLs directly (no 2 MB limit here).
          var dataUrl = 'data:' + mimeType + ';base64,' + contentBase64;

          var id = await Promise.race([
            chrome.downloads.download({
              url: dataUrl,
              filename: filename,
              saveAs: false,
            }),
            new Promise((_, rej) => setTimeout(() => rej(new Error('Download timed out (10s)')), 10000)),
          ]);

          sendResponse({ success: true, data: { id: id, filename: filename } });
        } catch (dlErr) {
          sendResponse({ success: false, error: dlErr.message || String(dlErr) });
        }
        break;
      }

      // ── PDF generation ─────────────────────────────────────────────────────
      case 'SAVE_AS_PDF': {
        var pdfTabId = tabId || await getActiveTabId();
        if (!pdfTabId) {
          sendResponse({ success: false, error: 'No active tab' });
          break;
        }
        try {
          var pdfResult = await Promise.race([
            chrome.scripting.executeScript({
              target: { tabId: pdfTabId },
              func: function (opts) {
                window.print();
                return { printed: true };
              },
              args: [{ filename: params.filename || 'page' }],
            }),
            new Promise((_, rej) => setTimeout(() => rej(new Error('PDF print timed out (8s)')), 8000)),
          ]);
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
  if (!tabs || tabs.length === 0) return null;
  // Exclude chrome-extension:// tabs (side panel itself) to get the real active page
  var realTab = tabs.find(function(t) {
    return t.id && t.url && !t.url.startsWith('chrome-extension://');
  });
  if (realTab && realTab.id) return realTab.id;
  // Fallback: return first tab if no real tab found (shouldn't happen in normal use)
  return (tabs[0] && tabs[0].id) ? tabs[0].id : null;
}
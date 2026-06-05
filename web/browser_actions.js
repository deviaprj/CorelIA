// Corely — Browser Actions Bridge
// Handles bidirectional browser action commands from Flutter.
// Listens for corely_browser_action CustomEvent from Dart,
// routes them through the background SW, and dispatches results
// back to Flutter via corely_browser_action_result CustomEvent.
'use strict';

(function initBrowserActions() {
  if (typeof chrome === 'undefined' || !chrome.runtime) {
    console.warn('[BrowserActions] chrome.runtime not available.');
    return;
  }

  // Actions handled directly by background SW (no tab script injection needed)
  var BACKGROUND_ACTIONS = [
    'OPEN_URL', 'NAVIGATE_BACK', 'NAVIGATE_FORWARD', 'SCREENSHOT',
    'DOWNLOAD', 'SAVE_AS_PDF'
  ];

  // ── Listen for action requests from Flutter ────────────────────────────────
  window.addEventListener('corely_browser_action', function (event) {
    var detail = event.detail || {};
    var actionId = detail.actionId;
    var action = detail.action;
    var params = detail.params || {};

    if (!actionId || !action) {
      console.warn('[BrowserActions] Missing actionId or action:', detail);
      return;
    }

    handleBrowserAction(actionId, action, params);
  });

  // ── Listen for action results from background SW ───────────────────────────
  chrome.runtime.onMessage.addListener(function (message, _sender, sendResponse) {
    if (!message || message.type !== 'BROWSER_ACTION_RESULT') return false;

    // Forward result to Flutter via CustomEvent
    window.dispatchEvent(new CustomEvent('corely_browser_action_result', {
      detail: message.detail || message,
    }));

    sendResponse({ received: true });
    return false;
  });

  // ── Action routing ──────────────────────────────────────────────────────────
  async function handleBrowserAction(actionId, action, params) {
    // Background actions: route directly to background SW
    if (BACKGROUND_ACTIONS.indexOf(action) !== -1) {
      try {
        var response = await chrome.runtime.sendMessage({
          type: 'BROWSER_ACTION',
          actionId: actionId,
          action: action,
          params: params,
        });
        dispatchResult(actionId, action, response.success !== false, response.data || response, response.error);
      } catch (err) {
        dispatchResult(actionId, action, false, null, err.message || String(err));
      }
      return;
    }

    // Tab actions: need an active tab
    var tabId = await getActiveTabId();
    if (!tabId) {
      dispatchResult(actionId, action, false, null, 'No active tab found');
      return;
    }

    // Content script actions (GET_PAGE_CONTENT, SUMMARIZE_PAGE)
    if (action === 'GET_PAGE_CONTENT' || action === 'SUMMARIZE_PAGE') {
      try {
        var contentResponse = await new Promise(function (resolve) {
          chrome.tabs.sendMessage(tabId, {
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
        dispatchResult(actionId, action, contentResponse.success !== false, contentResponse, contentResponse.error);
      } catch (err) {
        dispatchResult(actionId, action, false, null, err.message || String(err));
      }
      return;
    }

    // DOM actions: route through background SW for chrome.scripting.executeScript
    try {
      var domResponse = await chrome.runtime.sendMessage({
        type: 'BROWSER_ACTION',
        actionId: actionId,
        action: action,
        params: params,
        tabId: tabId,
      });
      dispatchResult(actionId, action, domResponse.success !== false, domResponse.data, domResponse.error);
    } catch (err) {
      dispatchResult(actionId, action, false, null, err.message || String(err));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  function getActiveTabId() {
    return new Promise(function (resolve) {
      chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
        if (tabs && tabs[0] && tabs[0].id) {
          resolve(tabs[0].id);
        } else {
          resolve(null);
        }
      });
    });
  }

  function dispatchResult(actionId, action, success, data, error) {
    window.dispatchEvent(new CustomEvent('corely_browser_action_result', {
      detail: {
        actionId: actionId,
        action: action,
        success: !!success,
        data: data || null,
        error: error || null,
      },
    }));
  }

  console.info('[BrowserActions] Initialized.');
})();
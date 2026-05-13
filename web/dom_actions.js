// Corely — DOM Actions (injectable via chrome.scripting.executeScript)
// Handles DOM manipulation commands in the context of the active page.
// Injected by background.js via chrome.scripting.executeScript({files: ['dom_actions.js']})
// and then triggered via chrome.tabs.sendMessage({type: 'DOM_ACTION', ...}).
'use strict';

(function () {
  // Listen for action messages from background SW
  chrome.runtime.onMessage.addListener(function (message, _sender, sendResponse) {
    if (message.type !== 'DOM_ACTION') return false;

    try {
      var result = executeDomAction(message.action, message.params || {});
      sendResponse({ success: true, data: result });
    } catch (err) {
      sendResponse({ success: false, error: err.message || String(err) });
    }
    return false;
  });

  function executeDomAction(action, params) {
    switch (action) {
      case 'CLICK_ELEMENT': return clickElement(params);
      case 'FILL_FORM': return fillForm(params);
      case 'SCROLL': return scrollPage(params);
      case 'EXTRACT_TEXT': return extractText(params);
      case 'EXTRACT_LINKS': return extractLinks(params);
      default:
        throw new Error('Unknown DOM action: ' + action);
    }
  }

  // ── Click an element ────────────────────────────────────────────────────────
  function clickElement(params) {
    var selector = params.selector;
    if (!selector) throw new Error('Missing selector parameter');

    var el = document.querySelector(selector);
    if (!el) throw new Error('Element not found: ' + selector);

    el.click();
    return { clicked: true, tagName: el.tagName, selector: selector };
  }

  // ── Fill a form field ──────────────────────────────────────────────────────
  function fillForm(params) {
    var selector = params.selector;
    var value = params.value;
    if (!selector) throw new Error('Missing selector parameter');
    if (value === undefined || value === null) throw new Error('Missing value parameter');

    var el = document.querySelector(selector);
    if (!el) throw new Error('Element not found: ' + selector);

    // Focus and set value
    el.focus();

    // Clear existing value
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      el.value = '';
      // Use native input setter for React-controlled inputs
      var nativeInputValueSetter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype, 'value'
      );
      if (nativeInputValueSetter && nativeInputValueSetter.set) {
        nativeInputValueSetter.set.call(el, value);
      } else {
        el.value = value;
      }
    } else {
      el.textContent = value;
    }

    // Dispatch events for frameworks (React, Vue, Angular)
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));

    return { filled: true, selector: selector };
  }

  // ── Scroll the page ────────────────────────────────────────────────────────
  function scrollPage(params) {
    var direction = params.direction || 'down';
    var amount = params.amount || 500;

    window.scrollBy({
      top: direction === 'down' ? amount : -amount,
      behavior: 'smooth',
    });

    return {
      scrolled: true,
      direction: direction,
      amount: amount,
      scrollY: window.scrollY,
      scrollHeight: document.documentElement.scrollHeight,
    };
  }

  // ── Extract text from a selector ────────────────────────────────────────────
  function extractText(params) {
    var selector = params.selector || 'body';
    var el = document.querySelector(selector);
    if (!el) throw new Error('Element not found: ' + selector);

    var text = el.textContent.trim();
    // Limit to 15000 characters
    if (text.length > 15000) {
      text = text.substring(0, 15000);
    }

    return { text: text, selector: selector };
  }

  // ── Extract links from the page ────────────────────────────────────────────
  function extractLinks(params) {
    var selector = params.selector || 'a';
    var filter = params.filter || 'all'; // 'all', 'video', 'image', 'audio', 'document'
    var allLinks = Array.from(document.querySelectorAll(selector))
      .slice(0, 200)
      .map(function (a) {
        return {
          text: (a.textContent || '').trim().substring(0, 200),
          href: a.href || '',
        };
      })
      .filter(function (l) {
        return l.href && !l.href.startsWith('javascript:');
      });

    if (filter === 'all') {
      return { links: allLinks.slice(0, 100), count: allLinks.length };
    }

    // Filter by media type based on URL patterns and extensions
    var videoExts = ['.mp4', '.webm', '.mkv', '.avi', '.mov', '.flv', '.m4v'];
    var imageExts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.ico'];
    var audioExts = ['.mp3', '.wav', '.ogg', '.flac', '.aac', '.m4a'];
    var docExts = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv'];

    var videoHosts = ['youtube.com', 'youtu.be', 'vimeo.com', 'dailymotion.com', 'twitch.tv'];
    var imageHosts = ['imgur.com', 'flickr.com', 'unsplash.com', 'instagram.com', 'pinterest.com'];

    var filtered = allLinks.filter(function (l) {
      var lower = l.href.toLowerCase();
      switch (filter) {
        case 'video':
          return videoExts.some(function (e) { return lower.includes(e); }) ||
                 videoHosts.some(function (h) { return lower.includes(h); });
        case 'image':
          return imageExts.some(function (e) { return lower.includes(e); }) ||
                 imageHosts.some(function (h) { return lower.includes(h); }) ||
                 lower.includes('/image') || lower.includes('/img/');
        case 'audio':
          return audioExts.some(function (e) { return lower.includes(e); });
        case 'document':
          return docExts.some(function (e) { return lower.includes(e); });
        default:
          return true;
      }
    });

    return { links: filtered.slice(0, 100), count: filtered.length, filter: filter };
  }
})();
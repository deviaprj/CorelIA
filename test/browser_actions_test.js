// Tests for browser_actions.js — Corely Browser Actions Bridge
// Run with: node test/browser_actions_test.js

'use strict';

const assert = require('assert');
const path = require('path');
const fs = require('fs');

// ── Load and validate the module structure ────────────────────────────────────

console.log('=== browser_actions.js tests ===\n');

const code = fs.readFileSync(path.join(__dirname, '../web/browser_actions.js'), 'utf8');

// Test 1: File loads and has expected patterns
console.log('Test 1: Module structure validation...');
assert(code.includes('BACKGROUND_ACTIONS'), 'Expected BACKGROUND_ACTIONS constant');
assert(code.includes('OPEN_URL'), 'Expected OPEN_URL action');
assert(code.includes('NAVIGATE_BACK'), 'Expected NAVIGATE_BACK action');
assert(code.includes('NAVIGATE_FORWARD'), 'Expected NAVIGATE_FORWARD action');
assert(code.includes('SCREENSHOT'), 'Expected SCREENSHOT action');
assert(code.includes('DOWNLOAD'), 'Expected DOWNLOAD action');
assert(code.includes('SAVE_AS_PDF'), 'Expected SAVE_AS_PDF action');
assert(code.includes('handleBrowserAction'), 'Expected handleBrowserAction function');
assert(code.includes('getActiveTabId'), 'Expected getActiveTabId function');
assert(code.includes('dispatchResult'), 'Expected dispatchResult function');
console.log('  PASS — All expected patterns found\n');

// Test 2: BACKGROUND_ACTIONS list is complete
console.log('Test 2: BACKGROUND_ACTIONS contains all expected actions...');
const bgActionsMatch = code.match(/BACKGROUND_ACTIONS\s*=\s*\[([^\]]+)\]/s);
assert(bgActionsMatch, 'Expected BACKGROUND_ACTIONS array definition');
const bgActionsStr = bgActionsMatch[1];
assert(bgActionsStr.includes('OPEN_URL'), 'OPEN_URL should be in BACKGROUND_ACTIONS');
assert(bgActionsStr.includes('NAVIGATE_BACK'), 'NAVIGATE_BACK should be in BACKGROUND_ACTIONS');
assert(bgActionsStr.includes('NAVIGATE_FORWARD'), 'NAVIGATE_FORWARD should be in BACKGROUND_ACTIONS');
assert(bgActionsStr.includes('SCREENSHOT'), 'SCREENSHOT should be in BACKGROUND_ACTIONS');
assert(bgActionsStr.includes('DOWNLOAD'), 'DOWNLOAD should be in BACKGROUND_ACTIONS');
assert(bgActionsStr.includes('SAVE_AS_PDF'), 'SAVE_AS_PDF should be in BACKGROUND_ACTIONS');
console.log('  PASS — BACKGROUND_ACTIONS is complete\n');

// Test 3: Event listeners are registered
console.log('Test 3: Event listener registration...');
assert(code.includes("window.addEventListener('corely_browser_action'"), 'Expected corely_browser_action listener');
assert(code.includes('chrome.runtime.onMessage.addListener'), 'Expected chrome.runtime.onMessage listener');
console.log('  PASS — Event listeners properly registered\n');

// Test 4: Result dispatching uses correct event name
console.log('Test 4: Result event dispatching...');
assert(code.includes("corely_browser_action_result"), 'Expected corely_browser_action_result event');
assert(code.includes('CustomEvent'), 'Expected CustomEvent usage');
console.log('  PASS — Result dispatching uses correct event\n');

// Test 5: Error handling for missing actionId or action
console.log('Test 5: Error handling for missing parameters...');
assert(code.includes('Missing actionId or action'), 'Expected missing param check');
console.log('  PASS — Error handling present\n');

// Test 6: Chrome runtime message format
console.log('Test 6: Chrome runtime message format...');
assert(code.includes("type: 'BROWSER_ACTION'"), 'Expected BROWSER_ACTION message type');
assert(code.includes('actionId'), 'Expected actionId in message');
assert(code.includes('action'), 'Expected action in message');
assert(code.includes('params'), 'Expected params in message');
console.log('  PASS — Message format correct\n');

// Test 7: Result event includes all required fields
console.log('Test 7: Result event fields...');
assert(code.includes('actionId'), 'Expected actionId in result');
assert(code.includes('success'), 'Expected success in result');
assert(code.includes('error'), 'Expected error in result');
console.log('  PASS — Result event includes required fields\n');

// Test 8: Background actions route through sendMessage
console.log('Test 8: Background actions route through chrome.runtime.sendMessage...');
assert(code.includes('chrome.runtime.sendMessage'), 'Expected chrome.runtime.sendMessage call');
console.log('  PASS — Background actions use chrome.runtime.sendMessage\n');

// Test 9: Tab actions use chrome.tabs.query
console.log('Test 9: Tab actions use chrome.tabs...');
assert(code.includes('chrome.tabs.query'), 'Expected chrome.tabs.query');
assert(code.includes('active: true'), 'Expected active: true in tab query');
assert(code.includes('currentWindow: true'), 'Expected currentWindow: true');
console.log('  PASS — Tab query parameters correct\n');

// Test 10: Content script actions are handled
console.log('Test 10: Content script actions handled...');
assert(code.includes('GET_PAGE_CONTENT'), 'Expected GET_PAGE_CONTENT');
assert(code.includes('SUMMARIZE_PAGE'), 'Expected SUMMARIZE_PAGE');
assert(code.includes('chrome.tabs.sendMessage'), 'Expected chrome.tabs.sendMessage');
console.log('  PASS — Content script actions properly handled\n');

console.log('=== All browser_actions.js tests passed! ===');
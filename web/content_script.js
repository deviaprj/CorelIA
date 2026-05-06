// Corely — Content Script
// Capture le texte sélectionné et l'envoie au background SW
'use strict';

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

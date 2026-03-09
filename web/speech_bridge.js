// AironBot — Web Speech API bridge
// Injecté dans la page d'extension (index.html) pour accéder à
// window.SpeechRecognition, qui n'est pas disponible dans les Service Workers.
'use strict';

(function initSpeechBridge() {
  const SpeechRecognition =
    window.SpeechRecognition || window.webkitSpeechRecognition;

  if (!SpeechRecognition) {
    console.warn('[SpeechBridge] API non disponible dans ce navigateur.');
    return;
  }

  let recognition = null;

  // Flutter → JS : écouter les appels depuis Dart via CustomEvent
  window.addEventListener('aironbot_speech_start', (e) => {
    const lang = e.detail?.lang ?? 'fr-FR';
    startRecognition(lang);
  });

  window.addEventListener('aironbot_speech_stop', () => {
    if (recognition) recognition.stop();
  });

  function startRecognition(lang) {
    if (recognition) recognition.abort();

    recognition = new SpeechRecognition();
    recognition.lang = lang;
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;

    recognition.onresult = (event) => {
      const last = event.results[event.results.length - 1];
      const transcript = last[0].transcript;
      const isFinal = last.isFinal;

      // JS → Flutter : émettre un CustomEvent
      window.dispatchEvent(
        new CustomEvent('aironbot_speech_result', {
          detail: { transcript, isFinal },
        })
      );
    };

    recognition.onerror = (event) => {
      window.dispatchEvent(
        new CustomEvent('aironbot_speech_error', {
          detail: { error: event.error },
        })
      );
    };

    recognition.onend = () => {
      window.dispatchEvent(new CustomEvent('aironbot_speech_end'));
      recognition = null;
    };

    recognition.start();
  }

  console.info('[SpeechBridge] Initialisé.');
})();

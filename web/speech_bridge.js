// Corely — Web Speech API bridge (STT + TTS)
// Injecté dans la page d'extension (index.html) pour accéder à
// window.SpeechRecognition et window.SpeechSynthesis,
// qui ne sont pas disponibles dans les Service Workers.
'use strict';

(function initSpeechBridge() {
  // ── STT (Speech-to-Text) ─────────────────────────────────────────────────────
  const SpeechRecognition =
    window.SpeechRecognition || window.webkitSpeechRecognition;

  if (!SpeechRecognition) {
    console.warn('[SpeechBridge] STT API non disponible dans ce navigateur.');
  }

  let recognition = null;

  // Flutter → JS : démarrer l'écoute
  window.addEventListener('corely_speech_start', (e) => {
    const lang = e.detail?.lang ?? 'fr-FR';
    startRecognition(lang);
  });

  // Flutter → JS : arrêter l'écoute
  window.addEventListener('corely_speech_stop', () => {
    if (recognition) recognition.stop();
  });

  function startRecognition(lang) {
    if (!SpeechRecognition) return;
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

      window.dispatchEvent(
        new CustomEvent('corely_speech_result', {
          detail: { transcript, isFinal },
        })
      );
    };

    recognition.onerror = (event) => {
      window.dispatchEvent(
        new CustomEvent('corely_speech_error', {
          detail: { error: event.error },
        })
      );
    };

    recognition.onend = () => {
      window.dispatchEvent(new CustomEvent('corely_speech_end'));
      recognition = null;
    };

    recognition.start();
  }

  // ── TTS (Text-to-Speech) ──────────────────────────────────────────────────
  const synth = window.speechSynthesis;

  // Mapping émotion → paramètres voix
  const emotionConfig = {
    neutral:   { rate: 1.0,  pitch: 1.0,  voice: null },
    joyful:    { rate: 1.15, pitch: 1.25, voice: null },
    sad:       { rate: 0.85, pitch: 0.85, voice: null },
    serious:   { rate: 0.9,  pitch: 0.9,  voice: null },
    excited:   { rate: 1.25, pitch: 1.35, voice: null },
    cheerful:  { rate: 1.1,  pitch: 1.2,  voice: null },
    friendly:  { rate: 1.05, pitch: 1.1,  voice: null },
  };

  // Charger les voix disponibles et choisir la meilleure voix française
  let frVoice = null;
  function loadVoices() {
    const voices = synth.getVoices();
    // Priorité : voix neurale française Google > voix française native > toute voix FR
    frVoice = voices.find(v => v.name.includes('Google') && v.lang.startsWith('fr'))
      || voices.find(v => v.lang === 'fr-FR' && v.localService)
      || voices.find(v => v.lang.startsWith('fr'));
    if (frVoice) {
      console.info('[SpeechBridge] Voix TTS sélectionnée :', frVoice.name);
    }
  }

  if (synth) {
    synth.onvoiceschanged = loadVoices;
    loadVoices();
  }

  // Flutter → JS : lire du texte avec émotion
  window.addEventListener('corely_tts_speak', (e) => {
    const text = e.detail?.text ?? '';
    const emotion = (e.detail?.emotion ?? 'neutral').toLowerCase();
    const config = emotionConfig[emotion] || emotionConfig.neutral;

    if (!synth || !text.trim()) return;

    synth.cancel(); // Arrêter toute lecture en cours

    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = 'fr-FR';
    utterance.rate = config.rate;
    utterance.pitch = config.pitch;
    utterance.volume = 1.0;

    if (frVoice) utterance.voice = frVoice;

    utterance.onend = () => {
      window.dispatchEvent(new CustomEvent('corely_tts_end'));
    };

    utterance.onerror = (event) => {
      window.dispatchEvent(
        new CustomEvent('corely_tts_error', {
          detail: { error: event.error },
        })
      );
    };

    synth.speak(utterance);
  });

  // Flutter → JS : arrêter la lecture TTS
  window.addEventListener('corely_tts_stop', () => {
    if (synth) synth.cancel();
  });

  // Flutter → JS : vérifier si TTS est en cours
  window.addEventListener('corely_tts_status', () => {
    window.dispatchEvent(
      new CustomEvent('corely_tts_status_response', {
        detail: { speaking: synth ? synth.speaking : false },
      })
    );
  });

  console.info('[SpeechBridge] Initialisé (STT + TTS).');
})();
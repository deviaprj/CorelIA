// Corely — Web Speech API bridge (STT + TTS)
// Injecté dans la page d'extension (index.html) pour accéder à
// window.SpeechRecognition et window.SpeechSynthesis,
// qui ne sont pas disponibles dans les Service Workers.
//
// v2 — Multi-language, continuous dictation mode, improved error recovery.
'use strict';

(function initSpeechBridge() {
  // ── STT (Speech-to-Text) ─────────────────────────────────────────────────────
  const SpeechRecognition =
    window.SpeechRecognition || window.webkitSpeechRecognition;

  if (!SpeechRecognition) {
    console.warn('[SpeechBridge] STT API non disponible dans ce navigateur.');
  }

  let recognition = null;
  let _continuousMode = false;
  let _currentLang = 'fr-FR';
  let _retryCount = 0;
  const MAX_RETRIES = 3;
  let _retryTimer = null;

  // Language voice map — best voices for each supported language
  const langVoiceMap = {
    'fr-FR': { code: 'fr', name: 'French' },
    'en-US': { code: 'en', name: 'English' },
    'es-ES': { code: 'es', name: 'Spanish' },
    'de-DE': { code: 'de', name: 'German' },
    'it-IT': { code: 'it', name: 'Italian' },
    'pt-PT': { code: 'pt', name: 'Portuguese' },
  };

  let cachedVoices = {}; // lang -> best voice

  // Flutter → JS : démarrer l'écoute
  window.addEventListener('corely_speech_start', (e) => {
    const lang = e.detail?.lang ?? 'fr-FR';
    const continuous = e.detail?.continuous ?? false;
    _continuousMode = continuous;
    _currentLang = lang;
    _retryCount = 0;
    startRecognition(lang, continuous);
  });

  // Flutter → JS : arrêter l'écoute
  window.addEventListener('corely_speech_stop', () => {
    _continuousMode = false;
    clearTimeout(_retryTimer);
    if (recognition) {
      try { recognition.stop(); } catch (_) {}
    }
  });

  // Flutter → JS : vérifier disponibilité micro
  window.addEventListener('corely_mic_check', () => {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      window.dispatchEvent(
        new CustomEvent('corely_mic_status', {
          detail: { available: false, error: 'getUserMedia not supported' },
        })
      );
      return;
    }

    navigator.mediaDevices.getUserMedia({ audio: true })
      .then((stream) => {
        stream.getTracks().forEach(t => t.stop());
        window.dispatchEvent(
          new CustomEvent('corely_mic_status', {
            detail: { available: true },
          })
        );
      })
      .catch((err) => {
        window.dispatchEvent(
          new CustomEvent('corely_mic_status', {
            detail: { available: false, error: err.name || err.message },
          })
        );
      });
  });

  function startRecognition(lang, continuous) {
    if (!SpeechRecognition) {
      window.dispatchEvent(
        new CustomEvent('corely_speech_error', {
          detail: { error: 'speech-recognition-unavailable' },
        })
      );
      return;
    }

    // Clean up previous instance
    if (recognition) {
      try { recognition.abort(); } catch (_) {}
      recognition = null;
    }

    try {
      recognition = new SpeechRecognition();
      recognition.lang = lang;
      recognition.continuous = continuous;
      recognition.interimResults = true;
      recognition.maxAlternatives = 1;

      recognition.onresult = (event) => {
        _retryCount = 0; // Reset retry on successful result
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
        console.warn('[SpeechBridge] Erreur STT :', event.error);

        // Handle retriable errors
        if (event.error === 'network' || event.error === 'audio-capture' ||
            event.error === 'service-not-allowed') {
          if (_retryCount < MAX_RETRIES && _continuousMode) {
            _retryCount++;
            console.info('[SpeechBridge] Retry ' + _retryCount + '/' + MAX_RETRIES);
            clearTimeout(_retryTimer);
            _retryTimer = setTimeout(() => {
              if (_continuousMode) {
                startRecognition(lang, continuous);
              }
            }, 1000 * _retryCount);
            return;
          }
        }

        window.dispatchEvent(
          new CustomEvent('corely_speech_error', {
            detail: { error: event.error, message: event.message },
          })
        );
      };

      recognition.onend = () => {
        // Auto-restart in continuous mode
        if (_continuousMode && recognition != null) {
          try {
            recognition.start();
            return;
          } catch (e) {
            console.warn('[SpeechBridge] Échec redémarrage continu :', e);
          }
        }

        window.dispatchEvent(new CustomEvent('corely_speech_end'));
        recognition = null;
      };

      recognition.start();
      console.info('[SpeechBridge] Écoute démarrée (lang=' + lang +
        ', continuous=' + continuous + ')');
    } catch (e) {
      console.error('[SpeechBridge] Échec démarrage STT :', e);
      window.dispatchEvent(
        new CustomEvent('corely_speech_error', {
          detail: { error: 'start-failed', message: e.message },
        })
      );
    }
  }

  // ── TTS (Text-to-Speech) ──────────────────────────────────────────────────
  const synth = window.speechSynthesis;

  // Mapping émotion → paramètres voix
  const emotionConfig = {
    neutral:   { rate: 0.81,  pitch: 1.0,  voice: null },
    joyful:    { rate: 0.93,  pitch: 1.25, voice: null },
    sad:       { rate: 0.68,  pitch: 0.85, voice: null },
    serious:   { rate: 0.73,  pitch: 0.9,  voice: null },
    excited:   { rate: 1.01,  pitch: 1.35, voice: null },
    cheerful:  { rate: 0.89,  pitch: 1.2,  voice: null },
    friendly:  { rate: 0.85,  pitch: 1.1,  voice: null },
  };

  function getBestVoice(lang) {
    if (cachedVoices[lang]) return cachedVoices[lang];

    const voices = synth.getVoices();
    if (voices.length === 0) return null;

    const langPrefix = lang.split('-')[0];

    // Priority: Google neural > native local > any matching lang
    let best = voices.find(v => v.name.includes('Google') && v.lang.startsWith(langPrefix))
      || voices.find(v => v.lang === lang && v.localService)
      || voices.find(v => v.lang.startsWith(langPrefix))
      || null;

    if (best) {
      cachedVoices[lang] = best;
      console.info('[SpeechBridge] Voix TTS pour ' + lang + ' :', best.name);
    }
    return best;
  }

  function loadAllVoices() {
    const voices = synth.getVoices();
    if (voices.length === 0) return;

    // Cache best voice for each supported language
    Object.keys(langVoiceMap).forEach(lang => {
      getBestVoice(lang);
    });
  }

  if (synth) {
    synth.onvoiceschanged = loadAllVoices;
    loadAllVoices();
  }

  // Flutter → JS : lire du texte avec émotion et langue
  window.addEventListener('corely_tts_speak', (e) => {
    const text = e.detail?.text ?? '';
    const emotion = (e.detail?.emotion ?? 'neutral').toLowerCase();
    const lang = e.detail?.lang ?? 'fr-FR';
    const config = emotionConfig[emotion] || emotionConfig.neutral;

    if (!synth || !text.trim()) return;

    synth.cancel(); // Arrêter toute lecture en cours

    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = lang;
    utterance.rate = config.rate;
    utterance.pitch = config.pitch;
    utterance.volume = 1.0;

    // Try to use best voice for this language
    const voice = getBestVoice(lang);
    if (voice) utterance.voice = voice;

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

  console.info('[SpeechBridge] Initialisé v2 (STT multi-langue + continu + TTS multi-langue).');
})();

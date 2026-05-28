/// Émotions TTS — partagées entre mobile et web.
/// Ce fichier est importé directement (pas via import conditionnel).
enum TtsEmotion {
  neutral,
  joyful,
  sad,
  serious,
  excited,
  cheerful,
  friendly,
}

/// Configuration TTS pour une émotion.
class EmotionTtsConfig {
  final double rate;
  final double pitch;

  const EmotionTtsConfig({
    required this.rate,
    required this.pitch,
  });
}

/// Mapping émotion → config TTS.
/// Valeurs calibrées pour Google Speech Services (flutter_tts).
/// Base : 0.42 (speechRate init). Emotion rates relatifs :
///   neutral=0.52, friendly=0.54, joyful=0.58, excited=0.64.
/// Avec chunks de 300 chars, le moteur TTS gère mieux la prosodie interne.
const emotionTtsConfigs = <TtsEmotion, EmotionTtsConfig>{
  TtsEmotion.neutral:  EmotionTtsConfig(rate: 0.52, pitch: 1.00),
  TtsEmotion.joyful:   EmotionTtsConfig(rate: 0.58, pitch: 1.06),
  TtsEmotion.sad:      EmotionTtsConfig(rate: 0.46, pitch: 0.92),
  TtsEmotion.serious:  EmotionTtsConfig(rate: 0.49, pitch: 0.96),
  TtsEmotion.excited:  EmotionTtsConfig(rate: 0.64, pitch: 1.10),
  TtsEmotion.cheerful: EmotionTtsConfig(rate: 0.56, pitch: 1.04),
  TtsEmotion.friendly: EmotionTtsConfig(rate: 0.54, pitch: 1.02),
};

/// Configs calibrees pour Microsoft Edge TTS.
/// Edge utilise une echelle SSML : 0.5 = -50%, 1.0 = +0%, 2.0 = +100%.
const edgeEmotionTtsConfigs = <TtsEmotion, EmotionTtsConfig>{
  TtsEmotion.neutral: EmotionTtsConfig(rate: 0.85, pitch: 1.00),
  TtsEmotion.joyful: EmotionTtsConfig(rate: 1.00, pitch: 1.15),
  TtsEmotion.sad: EmotionTtsConfig(rate: 0.70, pitch: 0.90),
  TtsEmotion.serious: EmotionTtsConfig(rate: 0.75, pitch: 0.95),
  TtsEmotion.excited: EmotionTtsConfig(rate: 1.10, pitch: 1.20),
  TtsEmotion.cheerful: EmotionTtsConfig(rate: 0.95, pitch: 1.10),
  TtsEmotion.friendly: EmotionTtsConfig(rate: 0.90, pitch: 1.05),
};
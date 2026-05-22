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
/// Valeurs calibrees pour Google Speech Services (flutter_tts).
/// 0.5 = lent, 0.6 = agreable, 0.7 = rapide, 1.0 = vitesse normale.
/// Configs calibrees pour Google Speech Services (flutter_tts).
/// 0.5 = lent, 0.6 = agreable, 0.7 = rapide, 1.0 = vitesse normale.
const emotionTtsConfigs = <TtsEmotion, EmotionTtsConfig>{
  TtsEmotion.neutral: EmotionTtsConfig(rate: 0.58, pitch: 1.00),
  TtsEmotion.joyful: EmotionTtsConfig(rate: 0.64, pitch: 1.08),
  TtsEmotion.sad: EmotionTtsConfig(rate: 0.52, pitch: 0.92),
  TtsEmotion.serious: EmotionTtsConfig(rate: 0.55, pitch: 0.96),
  TtsEmotion.excited: EmotionTtsConfig(rate: 0.70, pitch: 1.12),
  TtsEmotion.cheerful: EmotionTtsConfig(rate: 0.62, pitch: 1.06),
  TtsEmotion.friendly: EmotionTtsConfig(rate: 0.60, pitch: 1.04),
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
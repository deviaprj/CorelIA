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
  final String voice;
  final double rate;
  final double pitch;

  const EmotionTtsConfig({
    required this.voice,
    required this.rate,
    required this.pitch,
  });
}

/// Mapping émotion → config TTS.
const emotionTtsConfigs = <TtsEmotion, EmotionTtsConfig>{
  TtsEmotion.neutral: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 1.0, pitch: 1.0),
  TtsEmotion.joyful: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 1.15, pitch: 1.25),
  TtsEmotion.sad: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 0.85, pitch: 0.85),
  TtsEmotion.serious: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 0.90, pitch: 0.90),
  TtsEmotion.excited: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 1.25, pitch: 1.40),
  TtsEmotion.cheerful: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 1.10, pitch: 1.20),
  TtsEmotion.friendly: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 1.05, pitch: 1.10),
};
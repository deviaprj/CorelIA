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
  TtsEmotion.neutral: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 0.85, pitch: 1.00),
  TtsEmotion.joyful: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 0.95, pitch: 1.15),
  TtsEmotion.sad: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 0.75, pitch: 0.88),
  TtsEmotion.serious: EmotionTtsConfig(voice: 'fr-FR-HenriNeural', rate: 0.80, pitch: 0.92),
  TtsEmotion.excited: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 1.00, pitch: 1.20),
  TtsEmotion.cheerful: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 0.92, pitch: 1.12),
  TtsEmotion.friendly: EmotionTtsConfig(voice: 'fr-FR-DeniseNeural', rate: 0.90, pitch: 1.08),
};
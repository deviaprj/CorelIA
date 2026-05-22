import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tts_emotion.dart';
import 'voice_conversation_service.dart';
import 'voice_service.dart';

/// Splash animé réactif à la voix pour le mode conversation vocale.
///
/// Caractéristiques :
/// - Forme centrale organique qui pulse avec le volume micro
/// - Gradient animé concentrique qui change avec l'émotion
/// - Transitions fluides entre les états (60fps)
/// - Transcript en temps réel pendant l'écoute
class AuroraSplash extends ConsumerStatefulWidget {
  const AuroraSplash({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<AuroraSplash> createState() => _AuroraSplashState();
}

class _AuroraSplashState extends ConsumerState<AuroraSplash>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _gradientController;
  late AnimationController _waveController;

  double _smoothedAmplitude = 0.0;
  double _targetAmplitude = 0.0;
  static const _smoothingFactor = 0.15;

  Color _currentColor = const Color(0xFF00BCD4); // cyan
  Color _targetColor = const Color(0xFF00BCD4);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _gradientController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Color _getEmotionColor(TtsEmotion emotion) {
    switch (emotion) {
      case TtsEmotion.neutral:
        return const Color(0xFF00BCD4); // cyan
      case TtsEmotion.joyful:
        return const Color(0xFFFFC107); // amber
      case TtsEmotion.sad:
        return const Color(0xFF3F51B5); // indigo
      case TtsEmotion.serious:
        return const Color(0xFF2E7D32); // vert foncé
      case TtsEmotion.excited:
        return const Color(0xFFFF5722); // deep orange
      case TtsEmotion.cheerful:
        return const Color(0xFFFF9800); // orange
      case TtsEmotion.friendly:
        return const Color(0xFF8BC34A); // light green
    }
  }

  Color _getStateColor(VoiceConversationState convState) {
    switch (convState) {
      case VoiceConversationState.listening:
        return const Color(0xFF4CAF50); // green
      case VoiceConversationState.thinking:
        return const Color(0xFF2196F3); // blue
      case VoiceConversationState.speaking:
        return const Color(0xFFFF9800); // orange
      case VoiceConversationState.error:
        return const Color(0xFFF44336); // red
      case VoiceConversationState.idle:
        return const Color(0xFF9E9E9E); // grey
    }
  }

  IconData _getStateIcon(VoiceConversationState convState) {
    switch (convState) {
      case VoiceConversationState.listening:
        return Icons.mic;
      case VoiceConversationState.thinking:
        return Icons.psychology;
      case VoiceConversationState.speaking:
        return Icons.record_voice_over;
      case VoiceConversationState.error:
        return Icons.error;
      case VoiceConversationState.idle:
        return Icons.help;
    }
  }

  String _getStateText(VoiceConversationState convState) {
    switch (convState) {
      case VoiceConversationState.listening:
        return 'Écoute en cours...';
      case VoiceConversationState.thinking:
        return 'Je réfléchis...';
      case VoiceConversationState.speaking:
        return 'Je parle...';
      case VoiceConversationState.error:
        return 'Erreur';
      case VoiceConversationState.idle:
        return 'Mode vocal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final voiceConv =
        ref.watch(voiceConversationProvider(widget.conversationId));
    final voiceState = ref.watch(voiceServiceProvider);

    // Amplitude cible
    if (voiceConv.state == VoiceConversationState.listening) {
      _targetAmplitude = voiceState.micLevel;
    } else if (voiceConv.state == VoiceConversationState.speaking) {
      _targetAmplitude = 0.5 + _pulseController.value * 0.3;
    } else {
      _targetAmplitude = 0.0;
    }

    // Lissage de l'amplitude
    _smoothedAmplitude = _smoothedAmplitude +
        (_targetAmplitude - _smoothedAmplitude) * _smoothingFactor;

    // Couleur cible
    if (voiceConv.state == VoiceConversationState.speaking) {
      _targetColor = _getEmotionColor(voiceConv.emotion);
    } else {
      _targetColor = _getStateColor(voiceConv.state);
    }
    _currentColor = Color.lerp(_currentColor, _targetColor, 0.08)!;

    final size = MediaQuery.of(context).size;
    final baseRadius = size.shortestSide * 0.15;
    final maxPulse = size.shortestSide * 0.12;
    final amplitude = _smoothedAmplitude.clamp(0.0, 1.0);
    final pulseRadius = baseRadius + (maxPulse * amplitude);

    return Container(
      color: Colors.black87,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ondes concentriques
          AnimatedBuilder(
            animation: _waveController,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(3, (i) {
                  final wavePhase =
                      (_waveController.value + i * 0.33) % 1.0;
                  final waveRadius = pulseRadius * (1.2 + wavePhase * 1.5);
                  final waveOpacity =
                      (1.0 - wavePhase) * 0.15 * (0.3 + amplitude * 0.7);

                  return Container(
                    width: waveRadius * 2,
                    height: waveRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _currentColor.withOpacity(waveOpacity),
                        width: 2.0,
                      ),
                    ),
                  );
                }),
              );
            },
          ),

          // Gradient animé autour de la forme centrale
          AnimatedBuilder(
            animation:
                Listenable.merge([_pulseController, _gradientController]),
            builder: (context, _) {
              final gradPhase = _gradientController.value;
              final gradRadius = pulseRadius * (1.3 + gradPhase * 0.4);

              return Container(
                width: gradRadius * 2,
                height: gradRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _currentColor
                          .withOpacity(0.4 * (0.5 + amplitude * 0.5)),
                      _currentColor
                          .withOpacity(0.15 * (0.3 + amplitude * 0.7)),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              );
            },
          ),

          // Forme centrale (pulse avec le volume)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final breathe = _pulseController.value;
              final deform =
                  1.0 + (breathe - 0.5) * 0.08 * (0.5 + amplitude);

              return Transform.scale(
                scale: deform,
                child: Container(
                  width: pulseRadius * 2,
                  height: pulseRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _currentColor.withOpacity(0.9),
                        _currentColor.withOpacity(0.5),
                        _currentColor.withOpacity(0.1),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _currentColor
                            .withOpacity(0.4 * (0.3 + amplitude * 0.7)),
                        blurRadius: 60 * (0.5 + amplitude),
                        spreadRadius: 15 * (0.3 + amplitude * 0.7),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Icône + texte d'état
          if (voiceConv.state != VoiceConversationState.idle)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getStateIcon(voiceConv.state),
                  size: 48,
                  color: Colors.white.withOpacity(0.9),
                ),
                const SizedBox(height: 24),
                Text(
                  _getStateText(voiceConv.state),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                if (voiceConv.transcript != null &&
                    voiceConv.transcript!.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      '"${voiceConv.transcript}"',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
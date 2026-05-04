import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_conversation_service.dart';

/// Splash animé style auréole boréale pour le mode vocal.
///
/// Affiche une animation de lueurs colorées qui réagissent à la voix :
/// - Vert/pourpre quand l'utilisateur parle (écoute)
/// - Bleu/cyan quand l'IA réfléchit
/// - Jaune/or quand l'IA parle (TTS)
class AuroraSplash extends ConsumerWidget {
  const AuroraSplash({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceConv = ref.watch(voiceConversationProvider(conversationId));

    // Couleurs pour chaque état
    Color getSplashColor(VoiceConversationState state) {
      switch (state) {
        case VoiceConversationState.listening:
          // Vert pourpre opaque pour masquer la conversation
          return Colors.black87;
        case VoiceConversationState.thinking:
          // Bleu intense opaque
          return Colors.black87;
        case VoiceConversationState.speaking:
          // Jaune/or intense opaque
          return Colors.black87;
        case VoiceConversationState.processingStt:
        case VoiceConversationState.error:
        case VoiceConversationState.idle:
          return Colors.black.withOpacity(0.95); // Opaque pour masquer la conversation
      }
    }

    final splashColor = getSplashColor(voiceConv.state);

    // Animations des particules
    final particles = <AuroraParticle>[];
    final rng = Random();
    for (int i = 0; i < 15; i++) {
      particles.add(AuroraParticle(
        x: rng.nextDouble() * 100,
        y: rng.nextDouble() * 100,
        size: 2 + rng.nextDouble() * 6,
        speed: 0.2 + rng.nextDouble() * 0.6,
        color: _getRandomAuroraColor(rng),
      ));
    }

    return Container(
      color: splashColor,
      child: Stack(
        children: [
          // Animation des particules
          ...particles.map((p) => AnimatedParticle(particle: p)),

          // Texte d'indication centré
          if (voiceConv.state != VoiceConversationState.idle)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Indicateur d'état
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getStateColor(voiceConv.state).withOpacity(0.2),
                      boxShadow: [
                        BoxShadow(
                          color: _getStateColor(voiceConv.state).withOpacity(0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _getStateIcon(voiceConv.state),
                        size: 48,
                        color: _getStateColor(voiceConv.state),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Texte d'état
                  Text(
                    _getStateText(voiceConv.state),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  // Si en écoute, afficher la transcription en temps réel
                  if (voiceConv.transcript != null &&
                      voiceConv.transcript!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
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
            ),
        ],
      ),
    );
  }

  Color _getStateColor(VoiceConversationState state) {
    switch (state) {
      case VoiceConversationState.listening:
        return Colors.green;
      case VoiceConversationState.thinking:
        return Colors.blue;
      case VoiceConversationState.speaking:
        return Colors.orange;
      case VoiceConversationState.processingStt:
        return Colors.cyan;
      case VoiceConversationState.error:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStateIcon(VoiceConversationState state) {
    switch (state) {
      case VoiceConversationState.listening:
        return Icons.mic;
      case VoiceConversationState.thinking:
        return Icons.psychology;
      case VoiceConversationState.speaking:
        return Icons.record_voice_over;
      case VoiceConversationState.processingStt:
        return Icons.transcribe;
      case VoiceConversationState.error:
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  String _getStateText(VoiceConversationState state) {
    switch (state) {
      case VoiceConversationState.listening:
        return 'Écoute en cours...';
      case VoiceConversationState.thinking:
        return 'Je réfléchis...';
      case VoiceConversationState.speaking:
        return 'Je vous écoute !';
      case VoiceConversationState.processingStt:
        return 'Transcription...';
      case VoiceConversationState.error:
        return 'Erreur';
      default:
        return 'Mode vocal';
    }
  }
}

/// Particule pour l'animation auréole
class AuroraParticle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final Color color;

  AuroraParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.color,
  });

  AuroraParticle copyWith({
    double? x,
    double? y,
    double? size,
    double? speed,
    Color? color,
  }) => AuroraParticle(
        x: x ?? this.x,
        y: y ?? this.y,
        size: size ?? this.size,
        speed: speed ?? this.speed,
        color: color ?? this.color,
      );
}

/// Widget animé pour une particule
class AnimatedParticle extends StatefulWidget {
  final AuroraParticle particle;

  const AnimatedParticle({super.key, required this.particle});

  @override
  State<AnimatedParticle> createState() => _AnimatedParticleState();
}

class _AnimatedParticleState extends State<AnimatedParticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: (5 / widget.particle.speed).toInt()),
    )..repeat();

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final x = (widget.particle.x + (sin(_animation.value * 3.14159) * 5)) % 100;
    final y = (widget.particle.y + (_animation.value * 20)) % 100;

    return Positioned(
      left: (size.width * x / 100) - (widget.particle.size * 10),
      top: (size.height * y / 100) - (widget.particle.size * 10),
      child: AnimatedOpacity(
        opacity: (1 - _animation.value) * 0.6,
        duration: const Duration(milliseconds: 500),
        child: Container(
          width: widget.particle.size * 10,
          height: widget.particle.size * 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.particle.color.withOpacity(
              (1 - _animation.value) * 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

Color _getRandomAuroraColor(Random rng) {
  final colors = [
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.cyan,
    Colors.pink,
    Colors.orange,
  ];
  return colors[rng.nextInt(colors.length)];
}

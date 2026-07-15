import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/corely_theme.dart';
import 'voice_conversation_service.dart';
import 'voice_service.dart';

/// Splash vocal repensé — thème Corely avec visualisation sonore.
///
/// États :
/// - listening : orbe pulsant + anneaux + icône micro verte
/// - thinking  : points orbitaux rotatifs (bleu Corely)
/// - speaking  : barres d'égaliseur animées réactives à l'amplitude simulée
class AuroraSplash extends ConsumerStatefulWidget {
  const AuroraSplash({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<AuroraSplash> createState() => _AuroraSplashState();
}

class _AuroraSplashState extends ConsumerState<AuroraSplash>
    with TickerProviderStateMixin {
  late AnimationController _breatheCtrl;
  late AnimationController _waveCtrl;
  late AnimationController _thinkCtrl;
  late AnimationController _barCtrl;

  double _smoothedAmplitude = 0.0;
  static const _smoothingFactor = 0.12;

  @override
  void initState() {
    super.initState();
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _thinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _breatheCtrl.dispose();
    _waveCtrl.dispose();
    _thinkCtrl.dispose();
    _barCtrl.dispose();
    super.dispose();
  }

  Color _stateColor(VoiceConversationState s) {
    switch (s) {
      case VoiceConversationState.listening:
        return const Color(0xFF22C55E);
      case VoiceConversationState.thinking:
        return CorelyTokens.accent;
      case VoiceConversationState.speaking:
        return CorelyTokens.accent;
      case VoiceConversationState.error:
        return const Color(0xFFEF4444);
      case VoiceConversationState.idle:
        return const Color(0xFF64748B);
    }
  }

  String _stateLabel(VoiceConversationState s) {
    switch (s) {
      case VoiceConversationState.listening:
        return 'Je vous écoute…';
      case VoiceConversationState.thinking:
        return 'Je réfléchis…';
      case VoiceConversationState.speaking:
        return 'Corely parle…';
      case VoiceConversationState.error:
        return 'Erreur vocale';
      case VoiceConversationState.idle:
        return 'Mode vocal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(voiceConversationProvider(widget.conversationId));
    final voice = ref.watch(voiceServiceProvider);
    final convState = conv.state;

    // Lissage amplitude
    if (convState == VoiceConversationState.listening) {
      _smoothedAmplitude +=
          (voice.micLevel - _smoothedAmplitude) * _smoothingFactor;
    } else if (convState == VoiceConversationState.speaking) {
      _smoothedAmplitude +=
          (0.65 - _smoothedAmplitude) * 0.07;
    } else {
      _smoothedAmplitude += (0.0 - _smoothedAmplitude) * 0.1;
    }

    final accent = _stateColor(convState);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF001218),
            Color(0xFF003F5C),
            Color(0xFF00263A),
            Color(0xFF001218),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.35, 0.65, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Ondes concentriques (CustomPainter)
          if (convState != VoiceConversationState.idle)
            AnimatedBuilder(
              animation: _waveCtrl,
              builder: (ctx, _) => CustomPaint(
                painter: _WavePainter(
                  phase: _waveCtrl.value,
                  amplitude: _smoothedAmplitude.clamp(0.1, 1.0),
                  color: accent,
                ),
              ),
            ),

          // Orbe central + contenu selon état
          Center(
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([_breatheCtrl, _thinkCtrl, _barCtrl]),
              builder: (ctx, _) {
                final breathe = 1.0 +
                    _breatheCtrl.value *
                        0.10 *
                        (_smoothedAmplitude.clamp(0.0, 1.0) + 0.4);
                const orbSize = 148.0;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Halo externe (glow)
                    Transform.scale(
                      scale: breathe * 1.4,
                      child: Container(
                        width: orbSize,
                        height: orbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withOpacity(
                                  0.20 * (0.4 + _smoothedAmplitude * 0.6)),
                              accent.withOpacity(0.05),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Orbe principal
                    Transform.scale(
                      scale: breathe,
                      child: Container(
                        width: orbSize,
                        height: orbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.18),
                              accent.withOpacity(0.80),
                              CorelyTokens.primary.withOpacity(0.95),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(
                                  0.55 * (0.3 + _smoothedAmplitude * 0.7)),
                              blurRadius:
                                  50.0 + _smoothedAmplitude * 35.0,
                              spreadRadius: 8,
                            ),
                            BoxShadow(
                              color: CorelyTokens.primary.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: -6,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Barres égaliseur (speaking)
                    if (convState == VoiceConversationState.speaking)
                      _SoundWaveBars(
                        progress: _barCtrl.value,
                        amplitude:
                            _smoothedAmplitude.clamp(0.25, 1.0),
                        color: Colors.white.withOpacity(0.92),
                        barCount: 7,
                        width: 88.0,
                        height: 44.0,
                      ),

                    // Points orbitaux (thinking)
                    if (convState == VoiceConversationState.thinking)
                      _OrbitDots(
                        progress: _thinkCtrl.value,
                        radius: 54.0,
                        dotColor: Colors.white.withOpacity(0.88),
                      ),

                    // Micro (listening)
                    if (convState == VoiceConversationState.listening)
                      const Icon(
                        Icons.mic_rounded,
                        size: 46,
                        color: Colors.white,
                      ),

                    // Erreur
                    if (convState == VoiceConversationState.error)
                      Icon(
                        Icons.error_outline_rounded,
                        size: 44,
                        color: Colors.white.withOpacity(0.9),
                      ),
                  ],
                );
              },
            ),
          ),

          // Badge statut en bas
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(
                    _stateLabel(convState),
                    key: ValueKey(convState),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (conv.transcript != null &&
                    conv.transcript!.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(36, 14, 36, 0),
                    child: Text(
                      '« ${conv.transcript} »',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.60),
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),

          // Logo Corely en haut
          Positioned(
            top: 64,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: CorelyTokens.avatarGradient,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'C',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Corely',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.90),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Barres d'égaliseur ────────────────────────────────────────────────────────

class _SoundWaveBars extends StatelessWidget {
  const _SoundWaveBars({
    required this.progress,
    required this.amplitude,
    required this.color,
    required this.barCount,
    required this.width,
    required this.height,
  });

  final double progress;
  final double amplitude;
  final Color color;
  final int barCount;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (i) {
          final phase = i / barCount;
          // Chaque barre a une fréquence légèrement différente
          final freq = 1.0 + (i % 3) * 0.7;
          final rawH = 0.15 +
              0.85 *
                  amplitude *
                  (0.35 +
                      0.65 *
                          sin((progress * 2 * pi * freq) +
                                  phase * 2 * pi)
                              .abs());
          final barH = (rawH * height).clamp(4.0, height);
          final barW = (width / barCount) * 0.52;

          return Container(
            width: barW,
            height: barH,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(barW / 2),
            ),
          );
        }),
      ),
    );
  }
}

// ── Points orbitaux (thinking) ────────────────────────────────────────────────

class _OrbitDots extends StatelessWidget {
  const _OrbitDots({
    required this.progress,
    required this.radius,
    required this.dotColor,
  });

  final double progress;
  final double radius;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(3, (i) {
          final angle = (progress * 2 * pi) + (i * 2 * pi / 3);
          final orbitR = radius * 0.68;
          final x = orbitR * cos(angle);
          final y = orbitR * sin(angle);
          final dotSize = 7.0 + i * 1.5;

          return Transform.translate(
            offset: Offset(x, y),
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor.withOpacity(0.55 + i * 0.18),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Peintre ondes concentriques ───────────────────────────────────────────────

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.phase,
    required this.amplitude,
    required this.color,
  });

  final double phase;
  final double amplitude;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.shortestSide * 0.11;

    for (var i = 0; i < 4; i++) {
      final wavePhase = (phase + i * 0.25) % 1.0;
      final radius = baseRadius * (1.6 + wavePhase * 2.8);
      final opacity =
          (1.0 - wavePhase) * 0.11 * amplitude * (1.0 - i * 0.15);

      if (opacity < 0.004) continue;

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.color != color;
}


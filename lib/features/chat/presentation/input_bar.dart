import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'voice_service.dart';
import 'voice_conversation_service.dart';

class InputBar extends ConsumerStatefulWidget {
  const InputBar({
    super.key,
    required this.onSend,
    this.isLoading = false,
  });

  final void Function(String) onSend;
  final bool isLoading;

  @override
  ConsumerState<InputBar> createState() => _InputBarState();
}

class _InputBarState extends ConsumerState<InputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final val = _controller.text.isNotEmpty;
      if (val != _hasText) setState(() => _hasText = val);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Remplit le champ de texte avec une valeur
  void setText(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;
    _controller.clear();
    widget.onSend(text);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceServiceProvider);
    final voiceNotifier = ref.read(voiceServiceProvider.notifier);
    final voiceConv = ref.watch(voiceConversationProvider);
    final voiceConvNotifier = ref.read(voiceConversationProvider.notifier);

    // Remplir le champ avec le résultat de la reconnaissance vocale
    ref.listen(voiceServiceProvider, (_, next) {
      if (next.transcript.isNotEmpty) {
        _controller.text = next.transcript;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });

    final colorScheme = Theme.of(context).colorScheme;
    final isVoiceActive = voiceConv.state != VoiceConversationState.idle;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 5,
                        minLines: 1,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Écrivez un message...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    // Bouton dictée (STT)
                    _DictationButton(
                      isListening: voiceState.isListening,
                      onTap: () async {
                        if (voiceState.isListening) {
                          voiceNotifier.stopListening();
                        } else {
                          final ok = await voiceNotifier.ensureInitialized();
                          if (ok) {
                            voiceNotifier.startListening();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Reconnaissance vocale non disponible')),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Bouton mode conversation vocale mains-libres
            IconButton(
              onPressed: () {
                if (isVoiceActive) {
                  voiceConvNotifier.stop();
                } else {
                  voiceConvNotifier.startConversation();
                }
              },
              icon: Icon(
                isVoiceActive
                    ? Icons.headset_mic
                    : Icons.headset_mic_outlined,
                size: 24,
                color: isVoiceActive
                    ? colorScheme.error
                    : colorScheme.primary,
              ),
              tooltip: isVoiceActive
                  ? 'Arrêter conversation vocale'
                  : 'Conversation vocale mains-libres',
            ),
            const SizedBox(width: 4),
            // Bouton envoyer
            AnimatedScale(
              scale: _hasText || widget.isLoading ? 1 : 0.7,
              duration: const Duration(milliseconds: 150),
              child: FilledButton(
                onPressed: widget.isLoading ? null : _send,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                child: widget.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DictationButton extends StatelessWidget {
  const _DictationButton({
    required this.isListening,
    required this.onTap,
  });

  final bool isListening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        isListening ? Icons.mic : Icons.mic_none_outlined,
        size: 24,
        color: isListening ? colorScheme.error : colorScheme.primary,
      ),
      tooltip: isListening ? 'Arrêter dictée' : 'Dictée vocale',
    );
  }
}

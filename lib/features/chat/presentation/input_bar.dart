import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'voice_service.dart';

/// Donnees d'une piece jointe en attente d'envoi.
class AttachmentData {
  final String? imageBase64;
  final String? imageMimeType;
  final String? fileName;
  final String? fileContent;
  final String previewLabel;

  const AttachmentData({
    this.imageBase64,
    this.imageMimeType,
    this.fileName,
    this.fileContent,
    required this.previewLabel,
  });

  bool get isImage => imageBase64 != null;
  bool get isFile => fileName != null;
}

/// Callback d'envoi avec texte + piece jointe optionnelle.
typedef SendCallback = void Function(
  String text, {
  String? imageBase64,
  String? imageMimeType,
  String? fileName,
  String? fileContent,
});

/// Barre de saisie avec support piece jointe, micro compact et envoi.
class InputBar extends ConsumerStatefulWidget {
  const InputBar({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.attachment,
    this.onCancelAttachment,
    this.onSlashTextChanged,
  });

  final SendCallback onSend;
  final bool isLoading;
  final AttachmentData? attachment;
  final VoidCallback? onCancelAttachment;
  final ValueChanged<String?>? onSlashTextChanged;

  @override
  ConsumerState<InputBar> createState() => InputBarState();
}

class InputBarState extends ConsumerState<InputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  DateTime? _lastSentAt;
  bool _suppressSlashFilter = false;

  TextEditingController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text;
    final val = text.isNotEmpty;
    if (val != _hasText) setState(() => _hasText = val);
    // Notify parent when typing a slash command
    if (widget.onSlashTextChanged != null && !_suppressSlashFilter) {
      if (text.startsWith('/')) {
        widget.onSlashTextChanged!(text.substring(1));
      } else {
        widget.onSlashTextChanged!(null);
      }
    }
  }

  /// Replace current text with a slash command (e.g. "/download ").
  void setCommandText(String commandWithSpace) {
    _suppressSlashFilter = true;
    _controller.text = commandWithSpace;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    _focusNode.requestFocus();
    // Re-enable slash filter after the current microtask cycle
    Future.microtask(() => _suppressSlashFilter = false);
  }

  /// Focus the text input field.
  void requestFocus() {
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSend => _hasText || widget.attachment != null;

  void _send() {
    final text = _controller.text.trim();
    if (!_canSend || widget.isLoading) return;

    final now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!).inMilliseconds < 600) {
      return;
    }
    _lastSentAt = now;

    final att = widget.attachment;
    _controller.clear();
    // Clear voice transcript so it doesn't re-fill the input
    final voiceNotifier = ref.read(voiceServiceProvider.notifier);
    voiceNotifier.clearTranscript();
    // Clear slash command filter after sending
    widget.onSlashTextChanged?.call(null);
    widget.onSend(
      text,
      imageBase64: att?.imageBase64,
      imageMimeType: att?.imageMimeType,
      fileName: att?.fileName,
      fileContent: att?.fileContent,
    );
    widget.onCancelAttachment?.call();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(voiceServiceProvider, (_, next) {
      if (next.transcript.isNotEmpty) {
        _controller.text = next.transcript;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });

    final colorScheme = Theme.of(context).colorScheme;
    final voiceState = ref.watch(voiceServiceProvider);
    final voiceNotifier = ref.read(voiceServiceProvider.notifier);
    final att = widget.attachment;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Apercu de la piece jointe
            if (att != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      att.isImage ? Icons.image : Icons.insert_drive_file,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        att.previewLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: widget.onCancelAttachment,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 18, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            // Champ texte + micro + envoi
            Row(
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
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: att != null ? 'Ajoutez votre question...' : 'Posez une question...',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onSubmitted: (_) => _send(),
                            textInputAction: TextInputAction.send,
                          ),
                        ),
                        _DictationButton(
                          isListening: voiceState.isListening,
                          onTap: () {
                            if (voiceState.isListening) {
                              voiceNotifier.stopListening();
                            } else {
                              voiceNotifier.startListening();
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedScale(
                  scale: _canSend || widget.isLoading ? 1 : 0.7,
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
          ],
        ),
      ),
    );
  }
}

class _DictationButton extends StatelessWidget {
  const _DictationButton({required this.isListening, required this.onTap});

  final bool isListening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: isListening ? 'Arrêter dictée' : 'Dictée vocale',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            isListening ? Icons.mic : Icons.mic_none_outlined,
            size: 20,
            color: isListening ? colorScheme.error : colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

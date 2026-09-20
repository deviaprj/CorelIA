import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/attachment.dart';

/// Callback d'envoi : texte seul (les pièces jointes sont gérées par l'écran).
typedef SendCallback = void Function(String text);

/// Barre de saisie : texte, pièce jointe, recherche Internet et envoi.
class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.onSend,
    required this.onAttach,
    this.isLoading = false,
    this.pendingAttachments = const [],
    this.onRemoveAttachment,
    this.searchEnabled = false,
    this.onToggleSearch,
  });

  final SendCallback onSend;
  final VoidCallback onAttach;
  final bool isLoading;
  final List<Attachment> pendingAttachments;
  final VoidCallback? onRemoveAttachment;
  final bool searchEnabled;
  final VoidCallback? onToggleSearch;

  @override
  State<InputBar> createState() => InputBarState();
}

class InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Préremplit le champ (édition d'un message).
  void setText(String text) {
    _controller.text = text;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: text.length));
    _focusNode.requestFocus();
  }

  bool get _canSend => _hasText || widget.pendingAttachments.isNotEmpty;

  void _send() {
    if (!_canSend || widget.isLoading) return;
    final text = _controller.text.trim();
    _controller.clear();
    widget.onSend(text);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.pendingAttachments.isNotEmpty)
              _AttachmentsPreview(
                attachments: widget.pendingAttachments,
                onRemove: widget.onRemoveAttachment,
              ),
            Row(
              children: [
                IconButton(
                  onPressed: widget.onAttach,
                  tooltip: 'Joindre un fichier',
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  onPressed: widget.onToggleSearch,
                  tooltip: widget.searchEnabled
                      ? 'Recherche Internet activée'
                      : 'Activer la recherche Internet',
                  icon: Icon(
                    widget.searchEnabled ? Icons.public : Icons.public_off,
                    color: widget.searchEnabled ? AppColors.primary : null,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Posez votre question...',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: widget.isLoading ? null : _send,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                    minimumSize: const Size(48, 48),
                  ),
                  child: widget.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: colorScheme.onPrimary,
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

class _AttachmentsPreview extends StatelessWidget {
  const _AttachmentsPreview({required this.attachments, this.onRemove});

  final List<Attachment> attachments;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: attachments
            .map(
              (att) => Row(
                children: [
                  Icon(
                    att.isImage ? Icons.image : Icons.insert_drive_file,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      att.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (onRemove != null)
                    InkWell(
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

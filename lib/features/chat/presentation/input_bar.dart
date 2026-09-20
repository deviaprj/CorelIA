import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/attachment.dart';

/// Callback d'envoi : texte seul (les pièces jointes sont gérées par l'écran).
typedef SendCallback = void Function(String text);

/// Zone de saisie pleine largeur.
///
/// Au repos, tout tient sur une seule ligne dans le bloc : bouton pièce jointe
/// à gauche, champ au centre, bouton d'envoi à droite.
///
/// Dès que le clavier s'ouvre (champ actif), le bloc gagne une ligne au-dessus :
/// le texte et le curseur occupent la ligne du haut, les deux boutons restent
/// sur la ligne du bas.
class InputBar extends StatefulWidget {
  const InputBar({
    super.key,
    required this.onSend,
    required this.onAttach,
    this.isLoading = false,
    this.pendingAttachments = const [],
    this.onRemoveAttachment,
  });

  final SendCallback onSend;
  final VoidCallback onAttach;
  final bool isLoading;
  final List<Attachment> pendingAttachments;
  final VoidCallback? onRemoveAttachment;

  @override
  State<InputBar> createState() => InputBarState();
}

class InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Conserve l'état du champ lorsqu'il change de disposition (1 ou 2 lignes).
  final _fieldKey = GlobalKey();

  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _focusNode.addListener(() {
      if (_focusNode.hasFocus == _isFocused) return;
      setState(() => _isFocused = _focusNode.hasFocus);
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.pendingAttachments.isNotEmpty)
              _AttachmentsPreview(
                attachments: widget.pendingAttachments,
                onRemove: widget.onRemoveAttachment,
              ),
            _composer(context),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey('input-composer'),
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isFocused ? AppColors.accent : colorScheme.outlineVariant,
          width: _isFocused ? 1.4 : 1,
        ),
      ),
      child: _isFocused ? _expandedLayout() : _singleLineLayout(),
    );
  }

  /// Une seule ligne : pièce jointe · champ · envoi.
  Widget _singleLineLayout() {
    return Row(
      children: [
        _attachButton(),
        Expanded(child: _field()),
        _sendButton(),
      ],
    );
  }

  /// Deux lignes : le champ au-dessus, les boutons en dessous.
  Widget _expandedLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, right: 6, top: 2),
          child: _field(),
        ),
        Row(
          children: [
            _attachButton(),
            const Spacer(),
            _sendButton(),
          ],
        ),
      ],
    );
  }

  Widget _field() {
    return TextField(
      key: _fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: 4,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 15, height: 1.3),
      decoration: const InputDecoration(
        hintText: 'Posez votre question...',
        // Le bloc (voir _composer) fournit le cadre : on neutralise le style
        // du thème pour éviter un champ imbriqué.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
  }

  Widget _attachButton() {
    return IconButton(
      onPressed: widget.onAttach,
      tooltip: 'Ajouter un fichier',
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      icon: const Icon(Icons.attach_file),
    );
  }

  Widget _sendButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = _canSend && !widget.isLoading;

    return FilledButton(
      onPressed: enabled ? _send : null,
      style: FilledButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(10),
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: widget.isLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimary,
              ),
            )
          : Icon(
              Icons.send_rounded,
              size: 18,
              color: colorScheme.onPrimary,
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

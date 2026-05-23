import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/message.dart';
import '../../../core/constants.dart';
import 'voice_service.dart';
import 'emotion_parser.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.showTts = true,
    this.onCopy,
    this.onEdit,
  });

  final Message message;
  final bool showTts;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == Role.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorScheme.secondaryContainer,
              child: Icon(Icons.auto_awesome,
                  size: 16, color: colorScheme.secondary),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth:
                        MediaQuery.of(context).size.width * 0.78,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: message.isStreaming && message.content.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: _TypingIndicator(),
                        )
                      : isUser
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (message.hasImage && message.imageBase64 != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        base64Decode(message.imageBase64!),
                                        fit: BoxFit.cover,
                                        width: 200,
                                        height: 200,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                      ),
                                    ),
                                  if (message.hasFile)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.insert_drive_file,
                                          size: 16,
                                          color: colorScheme.onPrimary.withOpacity(0.8),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            message.fileName!,
                                            style: TextStyle(
                                              color: colorScheme.onPrimary.withOpacity(0.9),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (message.content.isNotEmpty)
                                    Text(
                                      EmotionParser.toUiText(message.content),
                                      style: TextStyle(
                                        color: colorScheme.onPrimary,
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: MarkdownBody(
                                data: EmotionParser.toUiText(message.content),
                                selectable: true,
                                onTapLink: (text, href, title) async {
                                  if (href == null) return;
                                  final uri = Uri.tryParse(href);
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                                styleSheet: MarkdownStyleSheet(
                                  codeblockDecoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  code: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                ),
                if (!isUser && !message.isStreaming && message.content.isNotEmpty)
                  _ActionRow(message: message, showTts: showTts),
                if (isUser && message.content.isNotEmpty)
                  _UserActionRow(
                    message: message,
                    onCopy: onCopy,
                    onEdit: onEdit,
                  ),
                if (!isUser && message.hasSearchSources)
                  _SourcesRow(sources: message.searchSources!),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.message, this.showTts = true});
  final Message message;
  final bool showTts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceServiceProvider);
    final voiceNotifier = ref.read(voiceServiceProvider.notifier);
    final isSpeaking = voiceState.isSpeaking;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy_outlined,
          tooltip: 'Copier',
          onTap: () {
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copie dans le presse-papiers'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        _ActionButton(
          icon: Icons.share_outlined,
          tooltip: 'Partager',
          onTap: () {
            final preview = message.content.length > 200
                ? '${message.content.substring(0, 200)}...'
                : message.content;
            Share.share('$preview\n\n${AppConstants.shareTagline}');
          },
        ),
        if (showTts) ...[
          _ActionButton(
            icon: isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            tooltip: isSpeaking ? 'Arreter' : 'Lire',
            onTap: () {
              if (isSpeaking) {
                voiceNotifier.stopSpeaking();
              } else {
                voiceNotifier.speak(message.content);
              }
            },
          ),
        ],
      ],
    );
  }
}

/// Action row for user messages (copy + edit).
class _UserActionRow extends StatelessWidget {
  const _UserActionRow({
    required this.message,
    this.onCopy,
    this.onEdit,
  });

  final Message message;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy_outlined,
          tooltip: 'Copier',
          onTap: onCopy ?? () {
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copie dans le presse-papiers'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        if (onEdit != null)
          _ActionButton(
            icon: Icons.edit_outlined,
            tooltip: 'Modifier',
            onTap: onEdit!,
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16,
              color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

class _SourcesRow extends StatelessWidget {
  const _SourcesRow({required this.sources});

  final List<String> sources;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: sources.asMap().entries.map((entry) {
          final idx = entry.key;
          final parts = entry.value.split('|');
          final title = parts.isNotEmpty ? parts.first : 'Source';
          final url = parts.length > 1 ? parts[1] : '';

          return ActionChip(
            avatar: Icon(
              Icons.public,
              size: 14,
              color: colorScheme.primary,
            ),
            label: Text(
              '${idx + 1}. ${title.length > 24 ? "${title.substring(0, 24)}..." : title}',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.primary,
              ),
            ),
            backgroundColor: colorScheme.primaryContainer.withOpacity(0.4),
            side: BorderSide(color: colorScheme.primary.withOpacity(0.3)),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: url.isNotEmpty
                ? () async {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      )..repeat(reverse: true, period: Duration(milliseconds: 500 + i * 150)),
    );
    _anims = _controllers
        .map((c) => Tween<double>(begin: 0, end: 6).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.translate(
              offset: Offset(0, -_anims[i].value),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
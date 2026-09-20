import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/message.dart';

/// Bulle de message (utilisateur ou assistant).
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message, this.onEdit});

  final Message message;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _BotAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.userBubble : AppColors.botBubble,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(AppColors.bubbleRadius),
                      topRight: const Radius.circular(AppColors.bubbleRadius),
                      bottomLeft: Radius.circular(
                        isUser ? AppColors.bubbleRadius : AppColors.tailRadius,
                      ),
                      bottomRight: Radius.circular(
                        isUser ? AppColors.tailRadius : AppColors.bubbleRadius,
                      ),
                    ),
                    boxShadow: AppColors.bubbleShadow,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: message.isStreaming && message.content.isEmpty
                      ? const _TypingIndicator()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ..._attachments(context),
                            if (message.content.isNotEmpty)
                              isUser
                                  ? Text(
                                      message.content,
                                      style: const TextStyle(
                                        color: AppColors.onAccent,
                                      ),
                                    )
                                  : _MarkdownBody(content: message.content),
                          ],
                        ),
                ),
                if (!message.isStreaming && message.content.isNotEmpty)
                  _ActionRow(
                    content: message.content,
                    isUser: isUser,
                    onEdit: onEdit,
                  ),
                if (message.hasSearchSources)
                  _SourcesRow(sources: message.searchSources!),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  List<Widget> _attachments(BuildContext context) {
    final widgets = <Widget>[];
    for (final att in message.attachments) {
      if (att.isImage && att.imageBase64 != null) {
        widgets.add(
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(att.imageBase64!),
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    att.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppConfig.appName,
      child: Container(
        width: AppColors.avatarSize,
        height: AppColors.avatarSize,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.avatarGradient,
        ),
        alignment: Alignment.center,
        child: const Text(
          'C',
          style: TextStyle(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: content,
      selectable: true,
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 15,
          height: 1.5,
        ),
        a: const TextStyle(
          color: AppColors.primary,
          decoration: TextDecoration.underline,
        ),
        code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        codeblockDecoration: BoxDecoration(
          color: AppColors.chatBg,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.content, required this.isUser, this.onEdit});

  final String content;
  final bool isUser;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy_outlined,
          tooltip: 'Copier',
          onTap: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copié dans le presse-papiers'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        if (!isUser)
          _ActionButton(
            icon: Icons.share_outlined,
            tooltip: 'Partager',
            onTap: () {
              final preview =
                  content.length > 200 ? '${content.substring(0, 200)}...' : content;
              Share.share('$preview\n\n${AppConfig.shareTagline}');
            },
          ),
        if (isUser && onEdit != null)
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
          child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
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
          final parts = entry.value.split('|');
          final title = parts.isNotEmpty ? parts.first : 'Source';
          final url = parts.length > 1 ? parts[1] : '';
          return ActionChip(
            avatar: Icon(Icons.public, size: 14, color: colorScheme.primary),
            label: Text(
              '${entry.key + 1}. ${title.length > 24 ? '${title.substring(0, 24)}...' : title}',
              style: TextStyle(fontSize: 11, color: colorScheme.primary),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: url.isEmpty
                ? null
                : () async {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
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
  late final List<Animation<double>> _animations;

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
    _animations = _controllers
        .map(
          (c) => Tween<double>(begin: 0, end: 6).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut),
          ),
        )
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
          animation: _animations[i],
          builder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.translate(
              offset: Offset(0, -_animations[i].value),
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
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

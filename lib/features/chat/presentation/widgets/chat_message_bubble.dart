import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:flutter/material.dart';

/// One widget, branching on [ChatMessage.role]/[ChatMessage.status]
/// (data-model.md). `streaming` → a blinking cursor appended inline at the
/// end of the (possibly still-empty) bubble text, nothing below the bubble,
/// not tappable; `complete` → the bubble plus a small, gray, monospaced
/// timestamp below it; `failed` → "Falha ao gerar resposta — toque para
/// tentar novamente" in small red (regular, not monospaced) text below the
/// bubble, with the same timestamp still below that, tappable only in this
/// state (FR-004/FR-006).
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({required this.message, this.onRetryTap, super.key});

  final ChatMessage message;
  final VoidCallback? onRetryTap;

  bool get _isUser => message.role == ChatRole.user;

  @override
  Widget build(BuildContext context) {
    final isFailed = message.status == ChatMessageStatus.failed;

    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: isFailed ? onRetryTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
          child: Column(
            crossAxisAlignment: _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                ),
                decoration: BoxDecoration(
                  color: _isUser
                      ? DesignTokens.colorChatBubbleUser
                      : DesignTokens.colorSurfaceElevated,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(DesignTokens.radiusMd),
                    topRight: const Radius.circular(DesignTokens.radiusMd),
                    bottomLeft: Radius.circular(_isUser ? DesignTokens.radiusMd : 0),
                    bottomRight: Radius.circular(_isUser ? 0 : DesignTokens.radiusMd),
                  ),
                  boxShadow: _isUser ? null : DesignTokens.elevation1,
                ),
                child: Text.rich(
                  TextSpan(
                    text: message.content,
                    children: [
                      if (message.status == ChatMessageStatus.streaming)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: _StreamingCursor(),
                        ),
                    ],
                  ),
                  style: DesignTokens.textBodyMd,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingXs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
                child: _StatusLine(message: message),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    switch (message.status) {
      case ChatMessageStatus.streaming:
        // Prototype: no timestamp or spinner below the bubble while
        // streaming — the only in-progress indicator is the cursor inline
        // at the end of the bubble's own text.
        return const SizedBox.shrink();
      case ChatMessageStatus.complete:
        return _TimeText(message: message);
      case ChatMessageStatus.failed:
        // Prototype: the failure note sits above the time, not in place of
        // it (both render, stacked with the same 4dp gap as the rest of
        // this column) — regular (Karla) small text, not the monospaced
        // timestamp style.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Falha ao gerar resposta — toque para tentar novamente',
              style: DesignTokens.textBodyMd.copyWith(
                fontSize: 12,
                color: DesignTokens.colorError,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            _TimeText(message: message),
          ],
        );
    }
  }
}

/// Pulsing cursor appended at the end of a streaming message's text
/// (prototype-extract.md §2.2/§3: "blinking cursor at the end of the text").
class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.2 + 0.8 * (1 - (_controller.value - 0.5).abs() * 2).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 2,
            height: DesignTokens.textBodyMd.fontSize,
            margin: const EdgeInsets.only(left: 2),
            color: DesignTokens.colorTextPrimary,
          ),
        );
      },
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Text(
      TimeOfDay.fromDateTime(message.createdAt.toLocal()).format(context),
      style: DesignTokens.textMonoCaption.copyWith(
        color: DesignTokens.colorTextSecondary,
      ),
    );
  }
}

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/capture/presentation/widgets/open_insertion_modal.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _composerBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusFull)),
  borderSide: BorderSide(color: DesignTokens.colorBorder),
);

/// Replaces `_ComposerBar`. Owns its own [TextEditingController] — never
/// part of `ChatState` (research.md's "composer text is local" choice), so
/// nothing typed is ever lost on any failure.
class ChatComposer extends StatefulWidget {
  const ChatComposer({required this.canSend, super.key});

  final bool canSend;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.canSend) return;
    context.read<ChatBloc>().add(MessageSubmitted(text));
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        border: Border(top: BorderSide(color: DesignTokens.colorBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => openInsertionModal(context),
            icon: const Icon(Icons.add, color: DesignTokens.colorPrimary),
          ),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                return TextField(
                  controller: _controller,
                  enabled: widget.canSend,
                  maxLength: 8000,
                  // Prototype: a fully rounded pill in a darker beige than
                  // the bar it sits on (`colorSurfaceBg`, not the bar's own
                  // `colorSurfaceElevated`) — overridden here, not in the
                  // shared `InputDecorationTheme`, since every other text
                  // field in the app keeps that theme's rectangular shape.
                  decoration: InputDecoration(
                    hintText: 'Escreva uma mensagem...',
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: DesignTokens.colorSurfaceBg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingMd,
                      vertical: 10,
                    ),
                    border: _composerBorder,
                    enabledBorder: _composerBorder,
                    focusedBorder: _composerBorder,
                    disabledBorder: _composerBorder,
                  ),
                  onSubmitted: (_) => _handleSend(),
                );
              },
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final canTapSend = widget.canSend && value.text.trim().isNotEmpty;
              return IconButton(
                onPressed: canTapSend ? _handleSend : null,
                icon: Icon(
                  Icons.send_outlined,
                  color: canTapSend
                      ? DesignTokens.colorPrimary
                      : DesignTokens.colorTextSecondary,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

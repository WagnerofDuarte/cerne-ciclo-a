import 'dart:async';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_state.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_composer.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_message_bubble.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_offline_banner.dart';
import 'package:cerne/features/home/presentation/widgets/app_drawer.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Fixed dark-green header (☰ + "Cerne" wordmark) and the live conversation
/// area — `ChatBloc`/`ChatSessionsBloc` are provided by `app_router.dart`'s
/// `/home` route builder (research.md R7), not here.
class HomeChatShellPage extends StatefulWidget {
  const HomeChatShellPage({super.key});

  @override
  State<HomeChatShellPage> createState() => _HomeChatShellPageState();
}

class _HomeChatShellPageState extends State<HomeChatShellPage> {
  late final StreamSubscription<void> _reauthSubscription;

  @override
  void initState() {
    super.initState();
    // The one sanctioned cross-bloc touch point (research.md R3/R7) — lives
    // in this widget, never inside `ChatBloc` itself.
    _reauthSubscription = context.read<ChatBloc>().reauthRequired.listen((_) {
      if (!mounted) return;
      context.read<SessionBloc>().add(const AuthExpiredDetected());
    });
  }

  @override
  void dispose() {
    _reauthSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      drawer: const AppDrawer(),
      onDrawerChanged: (isOpen) {
        if (isOpen) {
          context.read<ChatSessionsBloc>().add(const SessionsRefreshRequested());
        }
      },
      appBar: AppBar(
        backgroundColor: DesignTokens.colorPrimary,
        foregroundColor: DesignTokens.colorOnPrimary,
        title: Text(
          'Cerne',
          style: DesignTokens.textTitleLg.copyWith(color: DesignTokens.colorOnPrimary),
        ),
      ),
      body: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, state) {
          final chatReady = state is ChatReady ? state : null;
          final List<ChatMessage> messages = chatReady?.messages ?? const [];
          final isOffline = chatReady?.isOffline ?? false;
          final canSend = chatReady?.canSend ?? false;
          final loadFailure = chatReady?.loadFailure;

          return Column(
            children: [
              if (isOffline) const ChatOfflineBanner(),
              Expanded(
                child: loadFailure != null
                    ? _ChatLoadFailureView(
                        message: loadFailure.message,
                        onRetry: () => context.read<ChatBloc>().add(
                          ConversationSelected(chatReady!.sessionId!),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.spacingMd,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return ChatMessageBubble(
                            message: message,
                            onRetryTap: () {
                              final userMessageId = index > 0
                                  ? messages[index - 1].id
                                  : null;
                              if (userMessageId == null) return;
                              context.read<ChatBloc>().add(
                                MessageRetryRequested(userMessageId),
                              );
                            },
                          );
                        },
                      ),
              ),
              ChatComposer(canSend: canSend),
            ],
          );
        },
      ),
    );
  }
}

/// The "standard no-connection state" (Edge Cases) — a conversation selected
/// while offline/erroring with nothing cached for it to fall back to.
/// Mirrors `RecordsPage`'s own `_LoadFailureView` pattern.
class _ChatLoadFailureView extends StatelessWidget {
  const _ChatLoadFailureView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: DesignTokens.textBodyLg, textAlign: TextAlign.center),
            const SizedBox(height: DesignTokens.spacingMd),
            ElevatedButton(onPressed: onRetry, child: const Text('Tentar novamente')),
          ],
        ),
      ),
    );
  }
}

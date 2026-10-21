import 'dart:async';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:cerne/features/chat/domain/entities/chat_session.dart';
import 'package:cerne/features/chat/domain/entities/chat_session_timestamp_formatter.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_state.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// A plain [Drawer] widget (not a route) listing "Novo Chat", the
/// "CONVERSAS" side-menu list, "Meus Registros", and "Configurações" —
/// never disposes Home/Chat's `State` underneath (research.md R3).
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _scrollController = ScrollController();
  late final StreamSubscription<void> _reauthSubscription;
  late final Future<String?> _accountEmail;

  @override
  void initState() {
    super.initState();
    _accountEmail = getIt<SecureTokenStorage>().readAccountEmail();
    _scrollController.addListener(_maybeRequestNextPage);
    _reauthSubscription = context.read<ChatSessionsBloc>().reauthRequired.listen((_) {
      if (!mounted) return;
      context.read<SessionBloc>().add(const AuthExpiredDetected());
    });
  }

  void _maybeRequestNextPage() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      context.read<ChatSessionsBloc>().add(const SessionsNextPageRequested());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    unawaited(_reauthSubscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: DesignTokens.colorSurfaceElevated,
      shape: const RoundedRectangleBorder(),
      width: MediaQuery.sizeOf(context).width * 0.8,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<String?>(
              future: _accountEmail,
              builder: (context, snapshot) {
                final email = snapshot.data;
                return Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingLg),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: DesignTokens.sizeAvatarMenu / 2,
                        backgroundColor: DesignTokens.colorPrimary,
                        child: Text(
                          email == null ? '?' : _initialsFromEmail(email),
                          style: DesignTokens.textTitleSm.copyWith(
                            color: DesignTokens.colorOnPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacingMd),
                      Expanded(
                        child: Text(
                          email == null ? '' : _displayNameFromEmail(email),
                          style: DesignTokens.textTitleSm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: DesignTokens.dividerThickness),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spacingMd,
                        DesignTokens.spacingMd,
                        DesignTokens.spacingMd,
                        DesignTokens.spacingSm,
                      ),
                      child: Text(
                        'CONVERSAS',
                        style: DesignTokens.textMonoCaption.copyWith(
                          color: DesignTokens.colorTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spacingMd,
                        0,
                        DesignTokens.spacingMd,
                        DesignTokens.spacingSm,
                      ),
                      child: _NewChatButton(
                        onTap: () {
                          Navigator.of(context).pop();
                          context.read<ChatBloc>().add(const NewConversationRequested());
                        },
                      ),
                    ),
                  ),
                  BlocBuilder<ChatSessionsBloc, ChatSessionsState>(
                    builder: (context, state) {
                      return switch (state) {
                        ChatSessionsLoading() => const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        ChatSessionsLoadFailure() => SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: TextButton(
                              onPressed: () => context
                                  .read<ChatSessionsBloc>()
                                  .add(const SessionsPageLoadRetried()),
                              child: const Text('Tentar novamente'),
                            ),
                          ),
                        ),
                        ChatSessionsLoaded(
                          sessions: final sessions,
                          isLoadingMore: final isLoadingMore,
                          pageLoadFailure: final pageLoadFailure,
                        ) =>
                          SliverList.builder(
                            itemCount:
                                sessions.length +
                                (isLoadingMore ? 1 : 0) +
                                (pageLoadFailure != null ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index < sessions.length) {
                                return _SessionTile(session: sessions[index]);
                              }
                              if (isLoadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(DesignTokens.spacingMd),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return _SessionsPageLoadFailureFooter(failure: pageLoadFailure!);
                            },
                          ),
                      };
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: DesignTokens.dividerThickness),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacingMd,
                DesignTokens.spacingSm,
                DesignTokens.spacingMd,
                DesignTokens.spacingXs,
              ),
              child: Column(
                children: [
                  _DrawerNavItem(
                    icon: Icons.menu_book_outlined,
                    label: 'Meus Registros',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.records);
                    },
                  ),
                  const SizedBox(height: DesignTokens.spacingXs / 2),
                  _DrawerNavItem(
                    icon: Icons.settings_outlined,
                    label: 'Configurações',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.settings);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DesignTokens.colorPrimary,
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 20, color: DesignTokens.colorOnPrimary),
              const SizedBox(width: DesignTokens.spacingSm),
              Text(
                'Novo Chat',
                style: DesignTokens.textBodyMd.copyWith(
                  fontWeight: FontWeight.w500,
                  color: DesignTokens.colorOnPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: DesignTokens.colorTextPrimary),
            const SizedBox(width: DesignTokens.spacingSm),
            Text(label, style: DesignTokens.textBodyMd),
          ],
        ),
      ),
    );
  }
}

class _SessionsPageLoadFailureFooter extends StatelessWidget {
  const _SessionsPageLoadFailureFooter({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        children: [
          Text(
            failure.message,
            style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorTextSecondary),
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () =>
                context.read<ChatSessionsBloc>().add(const SessionsPageLoadRetried()),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final ChatSession session;

  @override
  Widget build(BuildContext context) {
    final timestamp = session.lastUserMessageAt ?? session.updatedAt;
    final timestampLabel = ChatSessionTimestampFormatter.format(
      timestamp,
      now: DateTime.now(),
    );

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        context.read<ChatBloc>().add(ConversationSelected(session.id));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd + DesignTokens.spacingXs,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title,
              style: DesignTokens.textBodyMd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: DesignTokens.spacingXs / 2),
            Text(
              timestampLabel,
              style: DesignTokens.textMonoCaption.copyWith(color: DesignTokens.colorTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// There is no `name` field anywhere yet — the account's email (decoded
/// from the stored access token's own JWT, [SecureTokenStorage.readAccountEmail])
/// is the only real identity this app has on-device. Both derive from its
/// local-part (before `@`), split on `.`/`_`/`-`: "wagner.duarte@x.com" ->
/// name "Wagner Duarte", initials "WD". A real display name belongs to the
/// Configurações unit (prototype: "avatar with editable name/e-mail") —
/// this is a stand-in until that unit wires one in.
List<String> _emailNameWords(String email) => email
    .split('@')
    .first
    .split(RegExp(r'[._-]+'))
    .where((w) => w.isNotEmpty)
    .toList();

String _displayNameFromEmail(String email) {
  final words = _emailNameWords(email);
  if (words.isEmpty) return email;
  return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

String _initialsFromEmail(String email) {
  final words = _emailNameWords(email);
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
}

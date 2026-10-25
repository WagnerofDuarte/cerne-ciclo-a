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
import 'package:cerne/features/settings/domain/entities/account_profile.dart';
import 'package:cerne/features/settings/domain/repositories/account_profile_repository.dart';
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
  late final Future<({String? displayName, String? email})> _profile;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
    _scrollController.addListener(_maybeRequestNextPage);
    _reauthSubscription = context.read<ChatSessionsBloc>().reauthRequired.listen((_) {
      if (!mounted) return;
      context.read<SessionBloc>().add(const AuthExpiredDetected());
    });
  }

  // Resolves via `AccountProfileRepository` (`settings/domain/`), never
  // `AccountProfileLocalCache` directly — the same "presentation depends on
  // a domain interface, resolved via get_it" shape every other
  // cross-feature touch in this app already uses (research.md R13,
  // contracts/app-drawer-display-name-extension.md).
  Future<({String? displayName, String? email})> _loadProfile() async {
    final email = await getIt<SecureTokenStorage>().readAccountEmail();
    final cached = await getIt<AccountProfileRepository>().readCachedDisplayName();
    final displayName =
        cached ?? (email == null ? null : AccountProfile.defaultDisplayNameFromEmail(email));
    return (displayName: displayName, email: email);
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
            FutureBuilder<({String? displayName, String? email})>(
              future: _profile,
              builder: (context, snapshot) {
                final displayName = snapshot.data?.displayName ?? '';
                final profile = AccountProfile(displayName: displayName, email: '');
                return Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingLg),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: DesignTokens.sizeAvatarMenu / 2,
                        backgroundColor: DesignTokens.colorPrimary,
                        child: Text(
                          profile.initials,
                          style: DesignTokens.textTitleSm.copyWith(
                            color: DesignTokens.colorOnPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacingMd),
                      Expanded(
                        child: Text(
                          displayName,
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


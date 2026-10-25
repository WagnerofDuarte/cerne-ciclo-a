import 'dart:async';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/routing/app_router.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_event.dart';
import 'package:cerne/features/settings/presentation/bloc/settings_state.dart';
import 'package:cerne/features/settings/presentation/widgets/biometric_toggle_row.dart';
import 'package:cerne/features/settings/presentation/widgets/dashboard_card.dart';
import 'package:cerne/features/settings/presentation/widgets/delete_account_dialog.dart';
import 'package:cerne/features/settings/presentation/widgets/profile_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// "Configurações" — the four-concern screen replacing
/// `SettingsPlaceholderPage` (dashboard, account profile, biometric
/// toggle, sign-out/account-deletion). `SettingsBloc` is provided by
/// `app_router.dart`'s route builder, which also dispatches the first
/// `SettingsOpened`.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with RouteAware {
  late final StreamSubscription<void> _reauthSubscription;
  bool _deleteDialogShown = false;

  @override
  void initState() {
    super.initState();
    _reauthSubscription = context.read<SettingsBloc>().reauthRequired.listen((_) {
      if (!mounted) return;
      context.read<SessionBloc>().add(const AuthExpiredDetected());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    chatRouteObserver.subscribe(this, ModalRoute.of(context)! as PageRoute<void>);
  }

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    unawaited(_reauthSubscription.cancel());
    super.dispose();
  }

  // The reauth page above Settings was popped — re-request fresh data
  // (research.md R15), stronger than Records'/Chat's own "preserve state"
  // handling of the same overlay.
  @override
  void didPopNext() => context.read<SettingsBloc>().add(const SettingsOpened());

  Future<void> _showDeleteDialogOnce(BuildContext context) async {
    if (_deleteDialogShown) return;
    _deleteDialogShown = true;
    // showDialog inserts the dialog as a sibling overlay entry on the
    // Navigator, not as a descendant of this route's BlocProvider<SettingsBloc>
    // (set up in app_router.dart) — re-provide the bloc explicitly so
    // DeleteAccountDialog's BlocBuilder can find it.
    final settingsBloc = context.read<SettingsBloc>();
    await showDialog<void>(
      context: context,
      builder: (_) => BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: const DeleteAccountDialog(),
      ),
    );
    _deleteDialogShown = false;
    if (context.mounted && context.read<SettingsBloc>().state.deleteDialogOpen) {
      context.read<SettingsBloc>().add(const DeleteAccountDialogCancelled());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) => current.signedOut || current.accountDeleted,
          listener: (context, state) {
            // The dialog's own `showDialog` future is still pending at this
            // point (this listener fires in the same frame as
            // `deleteDialogOpen` turning false) — pop it first so
            // `context.go()` below never leaves a dangling route on top.
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            context.go(AppRoutes.login);
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) => current.deleteDialogOpen,
          listener: (context, state) => _showDeleteDialogOnce(context),
        ),
        // Plain cancel/failure-dismiss only — the success path's own
        // `deleteDialogOpen -> false` is handled by the destination
        // listener above (which fires in the very same emit), so this one
        // deliberately excludes it to avoid a double pop.
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) =>
              previous.deleteDialogOpen && !current.deleteDialogOpen && !current.accountDeleted,
          listener: (context, state) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: DesignTokens.colorSurfaceBg,
        body: SafeArea(
          child: Column(
            children: [
              const _Header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    0,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingXl,
                  ),
                  children: [
                    const ProfileHeader(),
                    const SizedBox(height: DesignTokens.spacingLg),
                    Text('Sua evolução', style: DesignTokens.textHeadlineMd),
                    const SizedBox(height: DesignTokens.spacingSm),
                    const DashboardCard(),
                    const SizedBox(height: DesignTokens.spacingLg),
                    const BiometricToggleRow(),
                    const SizedBox(height: DesignTokens.spacingLg),
                    const _SignOutAndDeleteSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, color: DesignTokens.colorTextPrimary),
          ),
          const Expanded(
            child: Text('Configurações', style: DesignTokens.textHeadlineMd),
          ),
        ],
      ),
    );
  }
}

class _SignOutAndDeleteSection extends StatelessWidget {
  const _SignOutAndDeleteSection();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: DesignTokens.colorBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: DesignTokens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => context.read<SettingsBloc>().add(const SignOutRequested()),
              child: const Text('Sair', style: DesignTokens.textBodyMd),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            InkWell(
              onTap: () =>
                  context.read<SettingsBloc>().add(const DeleteAccountDialogOpened()),
              child: Text(
                'Apagar conta',
                style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

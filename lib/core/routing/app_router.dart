import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cerne/features/auth/presentation/pages/login_signup_page.dart';
import 'package:cerne/features/home/presentation/pages/home_chat_shell_page.dart';
import 'package:cerne/features/records/presentation/pages/records_placeholder_page.dart';
import 'package:cerne/features/settings/presentation/pages/settings_placeholder_page.dart';
import 'package:cerne/features/splash/presentation/pages/splash_page.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cerne/features/vault/presentation/pages/vault_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Root [NavigatorState] key — exposed so the session-expired overlay
/// (`showDialog`) can raise itself over whichever screen is currently active,
/// regardless of `go_router`'s own internal navigator (research.md R3).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => BlocProvider<AuthBloc>(
        create: (_) => getIt<AuthBloc>(),
        child: const LoginSignupPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.vault,
      builder: (context, state) => BlocProvider<VaultBloc>(
        create: (_) => getIt<VaultBloc>(),
        child: const VaultPage(mode: VaultMode.gatekeeper),
      ),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeChatShellPage(),
    ),
    GoRoute(
      path: AppRoutes.records,
      builder: (context, state) => const RecordsPlaceholderPage(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsPlaceholderPage(),
    ),
  ],
);

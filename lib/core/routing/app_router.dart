import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cerne/features/auth/presentation/pages/login_signup_page.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_event.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_bloc.dart';
import 'package:cerne/features/chat/presentation/bloc/chat_sessions_event.dart';
import 'package:cerne/features/home/presentation/pages/home_chat_shell_page.dart';
import 'package:cerne/features/records/presentation/bloc/records_bloc.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:cerne/features/records/presentation/pages/records_page.dart';
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

/// Lets `HomeChatShellPage` detect being covered by (and returning from)
/// Records/Settings so it can pause/resume RF08's inactivity timer
/// (research.md R10) — `ChatBloc`'s one instance is never torn down by this
/// navigation.
final RouteObserver<PageRoute<void>> chatRouteObserver = RouteObserver<PageRoute<void>>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  observers: [chatRouteObserver],
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
      builder: (context, state) => MultiBlocProvider(
        providers: [
          BlocProvider<ChatBloc>(
            create: (_) => getIt<ChatBloc>()..add(const ChatStarted()),
          ),
          BlocProvider<ChatSessionsBloc>(
            create: (_) => getIt<ChatSessionsBloc>()..add(const SessionsStarted()),
          ),
        ],
        child: const HomeChatShellPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.records,
      builder: (context, state) => BlocProvider<RecordsBloc>(
        create: (_) => getIt<RecordsBloc>()..add(const RecordsStarted()),
        child: const RecordsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsPlaceholderPage(),
    ),
  ],
);

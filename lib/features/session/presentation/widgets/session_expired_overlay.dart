import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cerne/features/auth/presentation/pages/login_signup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A non-dismissible `showDialog` raised through the root [navigatorKey]
/// whenever `SessionBloc` emits `expiredRenewable` — centered card over a
/// light scrim, preserving the screen underneath exactly (research.md R3;
/// prototype-extract.md §2.2).
void showSessionExpiredOverlay(GlobalKey<NavigatorState> navigatorKey) {
  final context = navigatorKey.currentContext;
  if (context == null) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: DesignTokens.colorSurfaceElevated,
        icon: const Icon(Icons.lock, color: DesignTokens.colorPrimary),
        title: const Text('Sessão expirada'),
        content: Text(
          'Sua sessão expirou. Seu histórico e sua posição na tela foram '
          'preservados — entre novamente para continuar.',
          style: DesignTokens.textBodyMd,
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              navigatorKey.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => BlocProvider<AuthBloc>(
                    create: (_) => getIt<AuthBloc>(),
                    child: const LoginSignupPage(isReauth: true),
                  ),
                ),
              );
            },
            child: const Text('Entrar novamente'),
          ),
        ],
      ),
    ),
  );
}

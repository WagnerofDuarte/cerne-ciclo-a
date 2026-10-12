import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/features/session/domain/entities/session_status.dart';
import 'package:cerne/features/session/presentation/bloc/session_bloc.dart';
import 'package:cerne/features/session/presentation/bloc/session_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Wordmark "Cerne" centered on [DesignTokens.colorPrimary], loading dots;
/// dispatches the app-start event and routes to Home/Chat or Login once
/// `SessionBloc` resolves. On a network-error state, shows a visible retry
/// action instead of routing away — never stuck (R7; FR-010; Edge Cases).
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Dispatched exactly once per mount — go_router may rebuild this route's
    // builder on ancestor rebuilds, but initState only runs once.
    context.read<SessionBloc>().add(const AppStarted());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorPrimary,
      body: BlocConsumer<SessionBloc, SessionStatus>(
        listener: (context, status) {
          switch (status) {
            case SessionStatusAuthenticated():
              context.push(AppRoutes.vault);
            case SessionStatusUnauthenticated():
              context.push(AppRoutes.login);
            case SessionStatusChecking():
            case SessionStatusExpiredRenewable():
            case SessionStatusNetworkError():
              break;
          }
        },
        builder: (context, status) {
          final isNetworkError = status is SessionStatusNetworkError;
          return Stack(
            children: [
              Center(
                child: Text(
                  'Cerne',
                  style: DesignTokens.textDisplayLg.copyWith(
                    color: DesignTokens.colorOnPrimary,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: DesignTokens.spacingXl,
                child: Center(
                  child: isNetworkError
                      ? _RetryPrompt(
                          onRetry: () => context
                              .read<SessionBloc>()
                              .add(const AppStarted()),
                        )
                      : const _LoadingDots(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RetryPrompt extends StatelessWidget {
  const _RetryPrompt({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Sem conexão — não foi possível verificar sua sessão.',
          textAlign: TextAlign.center,
          style: DesignTokens.textBodyMd.copyWith(
            color: DesignTokens.colorOnPrimary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: DesignTokens.colorOnPrimary,
            side: const BorderSide(color: DesignTokens.colorOnPrimary),
          ),
          child: const Text('Tentar novamente'),
        ),
      ],
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value + index / 3) % 1.0;
            final opacity = 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingXs,
              ),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: DesignTokens.sizeLoadingDot,
                  height: DesignTokens.sizeLoadingDot,
                  decoration: const BoxDecoration(
                    color: DesignTokens.colorOnPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

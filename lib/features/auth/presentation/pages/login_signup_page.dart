import 'dart:async';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_event.dart';
import 'package:cerne/features/auth/presentation/bloc/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The single login/sign-up screen, toggled between modes by a text link
/// (FR-008). Blocks the network call and shows an inline validation message
/// for an empty field (Edge Cases: "no network call made").
class LoginSignupPage extends StatefulWidget {
  const LoginSignupPage({super.key, this.isReauth = false});

  /// True when this screen was pushed on top of the "Sessão expirada"
  /// overlay (session_expired_overlay.dart) rather than reached from a fresh
  /// launch — on success, it pops back to the preserved screen underneath
  /// instead of pushing a new Home/Chat route (FR-013/FR-014, User Story 5).
  final bool isReauth;

  @override
  State<LoginSignupPage> createState() => _LoginSignupPageState();
}

class _LoginSignupPageState extends State<LoginSignupPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _localValidationError;
  bool _showLoadingIndicator = false;
  Timer? _loadingIndicatorTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _loadingIndicatorTimer?.cancel();
    super.dispose();
  }

  void _onSubmit(AuthFormMode mode) {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _localValidationError = 'Preencha e-mail e senha.');
      return;
    }

    setState(() => _localValidationError = null);
    final bloc = context.read<AuthBloc>();
    bloc.add(
      mode == AuthFormMode.login
          ? LoginSubmitted(email: email, password: password)
          : SignUpSubmitted(email: email, password: password),
    );
  }

  void _handleStatusChange(AuthStatus status) {
    _loadingIndicatorTimer?.cancel();
    if (status == AuthStatus.loading) {
      // RNF01: only show a loading indicator once the call exceeds 300 ms.
      _loadingIndicatorTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _showLoadingIndicator = true);
      });
    } else {
      setState(() => _showLoadingIndicator = false);
    }
  }

  String _messageFor(Failure failure) {
    return switch (failure) {
      AuthInvalidFailure() =>
        'E-mail ou senha inválidos, ou e-mail já cadastrado.',
      ValidationFailure() => 'Não foi possível enviar — revise os campos.',
      RateLimitedFailure() => 'Muitas tentativas — aguarde um instante.',
      NetworkTimeoutFailure() || NetworkOfflineFailure() =>
        'Sem conexão — toque para tentar novamente.',
      _ => failure.message,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (context, state) {
            _handleStatusChange(state.status);
            if (state.status == AuthStatus.authenticated) {
              if (widget.isReauth) {
                // Pop the pushed Login route and the dialog route beneath
                // it, landing back on the exact screen/state the overlay
                // was raised over (FR-013/FR-014).
                Navigator.of(context, rootNavigator: true)
                  ..pop()
                  ..pop();
              } else {
                // research.md R3: context.push, never go/replace, so the
                // login screen's State is never disposed underneath Home/Chat.
                context.push(AppRoutes.vault);
              }
            }
          },
          builder: (context, state) {
            final isSignUp = state.formMode == AuthFormMode.signUp;
            final isLoading = state.status == AuthStatus.loading;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(DesignTokens.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: DesignTokens.spacing2xl),
                  Text(
                    isSignUp ? 'Crie sua conta' : 'Bem-vindo de volta',
                    style: DesignTokens.textTitleLg,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: DesignTokens.spacingXl),
                  Container(
                    padding: const EdgeInsets.all(DesignTokens.spacingLg),
                    decoration: BoxDecoration(
                      color: DesignTokens.colorSurfaceElevated,
                      borderRadius:
                          BorderRadius.circular(DesignTokens.radiusMd),
                      border: Border.all(color: DesignTokens.colorBorder),
                      boxShadow: DesignTokens.elevation1,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'E-mail',
                          style: DesignTokens.textLabelMd.copyWith(
                            color: DesignTokens.colorTextSecondary,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingXs),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !isLoading,
                          decoration: const InputDecoration(
                            hintText: 'voce@email.com',
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingMd),
                        Text(
                          'Senha',
                          style: DesignTokens.textLabelMd.copyWith(
                            color: DesignTokens.colorTextSecondary,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spacingXs),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          enabled: !isLoading,
                          decoration: const InputDecoration(
                            hintText: '••••••••',
                          ),
                        ),
                        if (_localValidationError != null) ...[
                          const SizedBox(height: DesignTokens.spacingSm),
                          Text(
                            _localValidationError!,
                            style: DesignTokens.textBodyMd.copyWith(
                              color: DesignTokens.colorError,
                            ),
                          ),
                        ],
                        if (state.status == AuthStatus.failure &&
                            state.failure != null) ...[
                          const SizedBox(height: DesignTokens.spacingSm),
                          Text(
                            _messageFor(state.failure!),
                            style: DesignTokens.textBodyMd.copyWith(
                              color: DesignTokens.colorError,
                            ),
                          ),
                        ],
                        const SizedBox(height: DesignTokens.spacingSm),
                        ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () => _onSubmit(state.formMode),
                          child: _showLoadingIndicator
                              ? const SizedBox(
                                  height: DesignTokens.sizeLoadingIndicator,
                                  width: DesignTokens.sizeLoadingIndicator,
                                  child: CircularProgressIndicator(
                                    strokeWidth: DesignTokens
                                        .strokeWidthLoadingIndicator,
                                  ),
                                )
                              : Text(isSignUp ? 'Criar conta' : 'Entrar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacingLg),
                  Center(
                    child: GestureDetector(
                      onTap: isLoading
                          ? null
                          : () => context
                              .read<AuthBloc>()
                              .add(const ToggleModeRequested()),
                      child: Text.rich(
                        TextSpan(
                          text: isSignUp ? 'Já tem conta? ' : 'Não tem conta? ',
                          style: DesignTokens.textBodyMd.copyWith(
                            color: DesignTokens.colorTextSecondary,
                          ),
                          children: [
                            TextSpan(
                              text: isSignUp ? 'Entrar' : 'Criar conta',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: DesignTokens.colorPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacingMd),
                  Center(
                    child: GestureDetector(
                      onTap: isLoading
                          ? null
                          : () => context.push(AppRoutes.vault),
                      child: Text(
                        'usar biometria',
                        style: DesignTokens.textMonoCaption.copyWith(
                          color: DesignTokens.colorTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

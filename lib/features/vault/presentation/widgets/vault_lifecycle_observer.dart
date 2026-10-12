import 'package:cerne/core/di/service_locator.dart';
import 'package:cerne/core/routing/app_router.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/domain/usecases/evaluate_background_resume_usecase.dart';
import 'package:cerne/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:cerne/features/vault/presentation/pages/vault_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Installed once in `main.dart`, alongside the existing session-expired
/// `BlocListener` (contracts/vault-lifecycle.md). On `paused` it records
/// "now"; on `resumed` it evaluates the fixed 5-minute rule and, if due,
/// pushes `VaultPage(mode: relock)` over whatever screen is on top —
/// `rootNavigatorKey.push`, never `go`/replace, so the screen underneath
/// keeps its exact state (research.md R3).
class VaultLifecycleObserver extends StatefulWidget {
  const VaultLifecycleObserver({required this.child, super.key});

  final Widget child;

  @override
  State<VaultLifecycleObserver> createState() =>
      _VaultLifecycleObserverState();
}

class _VaultLifecycleObserverState extends State<VaultLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final repo = getIt<VaultRepository>();
    switch (state) {
      case AppLifecycleState.paused:
        repo.recordBackgrounded(DateTime.now());
      case AppLifecycleState.resumed:
        final backgroundedAt = repo.consumeBackgroundedAt();
        final shouldRelock = const EvaluateBackgroundResumeUseCase().call(
          backgroundedAt: backgroundedAt,
          resumedAt: DateTime.now(),
        );
        // A relock push only ever makes sense once the vault has actually
        // been passed at least once this process — otherwise backgrounding
        // the app while still on LoginSignupPage could spuriously push a
        // vault screen with nothing underneath worth protecting.
        if (shouldRelock && repo.lastUnlockedAt != null) {
          rootNavigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => BlocProvider<VaultBloc>(
                create: (_) => getIt<VaultBloc>(),
                child: const VaultPage(mode: VaultMode.relock),
              ),
            ),
          );
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

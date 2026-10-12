# Contract: Background-resume relock (`VaultLifecycleObserver` + `EvaluateBackgroundResumeUseCase`)

Covers FR-007–FR-010 and User Story 1's background-resume scenarios, plus the Edge Cases'
"process killed while backgrounded" and "exactly at the 5-minute boundary" cases. This is the
mechanism that is independent of which screen (`VaultPage` included) happens to be on top when the
app backgrounds.

## `EvaluateBackgroundResumeUseCase` (domain layer, pure)

```dart
class EvaluateBackgroundResumeUseCase {
  const EvaluateBackgroundResumeUseCase();

  static const backgroundTimeout = Duration(minutes: 5);   // FR-009 — the ONLY place this constant is defined

  bool call({required DateTime? backgroundedAt, required DateTime resumedAt}) {
    if (backgroundedAt == null) return false;
    return !resumedAt.difference(backgroundedAt).isNegative &&
        resumedAt.difference(backgroundedAt) >= backgroundTimeout;
  }
}
```

- No I/O, no `package:flutter` import, no settings read — testable with plain `DateTime` literals,
  including the exact-boundary case the Edge Cases call out ("fewer than 5 minutes elapsed never
  re-prompts; 5 minutes or more always does") as a direct unit test:
  `call(backgroundedAt: t, resumedAt: t.add(Duration(minutes: 5)))` must be `true`;
  `t.add(Duration(minutes: 4, seconds: 59))` must be `false`.
- `backgroundTimeout` lives here, not as a `VaultRepository` field or a `VaultBloc` constant — one
  definition, referenced by tests and (if ever needed) by presentation, never duplicated.

## `VaultLifecycleObserver` (presentation layer, `WidgetsBindingObserver`)

```dart
class VaultLifecycleObserver extends StatefulWidget {
  const VaultLifecycleObserver({required this.child, super.key});
  final Widget child;
  // ...
}

class _VaultLifecycleObserverState extends State<VaultLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final repo = getIt<VaultRepository>();
    switch (state) {
      case AppLifecycleState.paused:
        repo.recordBackgrounded(DateTime.now());
      case AppLifecycleState.resumed:
        final backgroundedAt = repo.consumeBackgroundedAt();
        final shouldRelock = const EvaluateBackgroundResumeUseCase()
            .call(backgroundedAt: backgroundedAt, resumedAt: DateTime.now());
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
}
```

- **`repo.lastUnlockedAt != null` guard** — a relock push only ever makes sense once the vault has
  actually been passed at least once this process. Without this guard, backgrounding the app while
  still sitting on `LoginSignupPage` (unauthenticated, no session, nothing to protect yet) could
  spuriously push a vault screen with nothing underneath worth protecting. This mirrors
  `SessionBloc._onAuthExpiredDetected`'s own re-entrancy guard
  (`if (state is SessionStatusExpiredRenewable) return;`) — both exist to stop a cross-cutting
  observer from firing when its precondition screen isn't actually the one in front.
- Installed exactly once, in `main.dart`, wrapping `MaterialApp.router`'s `builder` child — the
  same spot the existing session-expired `BlocListener` already wraps (`main.dart`, current
  `CerneApp.build`). Both can coexist in the same `builder` without interacting: a `VaultPage`
  relock push and a `showSessionExpiredOverlay` dialog push are independent root-navigator
  pushes, and neither depends on the other's state.
- Not testable with `flutter_test`'s widget tests in the way `bloc_test` tests
  `EvaluateBackgroundResumeUseCase` — `WidgetsBindingObserver` lifecycle callbacks can be
  simulated via `tester.binding.handleAppLifecycleStateChanged(...)` in a widget test; that test
  belongs to `tasks.md`, not this plan.

## Who depends on this

Nothing in `domain/` or `data/` depends on `VaultLifecycleObserver` — it is purely a
presentation-layer wiring point that calls two already-contracted `VaultRepository` methods and
one pure usecase. `main.dart` is the only call site.

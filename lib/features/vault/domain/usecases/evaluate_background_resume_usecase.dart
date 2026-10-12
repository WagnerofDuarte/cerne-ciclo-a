/// FR-009's "fixed value, not configurable by the user" rule — a pure
/// function of two timestamps and one constant, no settings read, no
/// `package:flutter` import (contracts/vault-lifecycle.md).
class EvaluateBackgroundResumeUseCase {
  const EvaluateBackgroundResumeUseCase();

  static const backgroundTimeout = Duration(minutes: 5);

  bool call({required DateTime? backgroundedAt, required DateTime resumedAt}) {
    if (backgroundedAt == null) return false;
    final gap = resumedAt.difference(backgroundedAt);
    return !gap.isNegative && gap >= backgroundTimeout;
  }
}

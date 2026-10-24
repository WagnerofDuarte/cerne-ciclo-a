import 'package:equatable/equatable.dart';

/// FR-002's two trigger kinds. Wire-format mapping (`message_count`/
/// `inactivity`) lives in `ChatRemoteDataSource` only — this enum carries no
/// backend-shape knowledge (RNF06/Principle V).
enum InsightTriggerType { messageCount, inactivity }

/// One occurrence of a satisfied trigger condition — either about to be
/// attempted immediately, or deferred (FR-003) until the current turn
/// resolves. Equatable only for test convenience; never compared in
/// production logic beyond null-checks (research.md R5).
class InsightTrigger extends Equatable {
  const InsightTrigger({required this.type, required this.triggerKey});

  final InsightTriggerType type;
  final String triggerKey;

  @override
  List<Object?> get props => [type, triggerKey];
}

/// Pure, stateless `triggerKey` formatting (FR-002; research.md R2) — no
/// `package:flutter`, no network/storage access.
class InsightTriggerKeyBuilder {
  const InsightTriggerKeyBuilder._();

  static String forMessageCount(int count) => 'message_count:$count';

  static String forInactivity(DateTime firedAt) =>
      'inactivity:${firedAt.toUtc().toIso8601String()}';
}

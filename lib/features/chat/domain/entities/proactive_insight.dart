import 'package:equatable/equatable.dart';

/// The single visible card at any one time (FR-004) — ephemeral, never
/// persisted or reconstructed (FR-009; spec.md Key Entities). `anchorIndex`
/// is `ChatReady.messages.length` captured the instant generation actually
/// started (research.md R5) — the slot `home_chat_shell_page.dart`'s
/// `ListView.builder` renders this card into, ahead of whatever message sat
/// at that index when the attempt began.
class ProactiveInsight extends Equatable {
  const ProactiveInsight({required this.content, required this.anchorIndex});

  final String content;
  final int anchorIndex;

  @override
  List<Object?> get props => [content, anchorIndex];
}

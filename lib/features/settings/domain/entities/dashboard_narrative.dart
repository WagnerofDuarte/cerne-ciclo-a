import 'package:equatable/equatable.dart';

/// `GET /dashboard/narrative`'s decoded response. [generatedAt] is parsed
/// but never displayed — kept only because the response always carries it
/// and dropping a required field silently would be a worse modeling choice
/// than keeping it unused (data-model.md).
class DashboardNarrative extends Equatable {
  const DashboardNarrative({required this.text, required this.generatedAt});

  final String text;
  final DateTime generatedAt;

  @override
  List<Object?> get props => [text, generatedAt];
}

import 'package:equatable/equatable.dart';

/// One parsed Server-Sent-Events frame (`event:`/`data:` lines) yielded by
/// `ApiClient.sseStream()`. Generic transport shape — `data` is the raw JSON
/// text, parsed by the caller (`ChatRemoteDataSource`), never by `ApiClient`
/// itself (data-model.md, contracts/sse-transport-extension.md).
class SseFrame extends Equatable {
  const SseFrame({required this.event, required this.data});

  final String event;
  final String data;

  @override
  List<Object?> get props => [event, data];
}

import 'package:equatable/equatable.dart';

/// The identity a person signs up with or logs into (data-model.md Account).
/// Password is never a field here — it exists only transiently as form input
/// and an outbound request-body value.
class Account extends Equatable {
  const Account({required this.id, required this.email});

  final String id;
  final String email;

  @override
  List<Object?> get props => [id, email];
}

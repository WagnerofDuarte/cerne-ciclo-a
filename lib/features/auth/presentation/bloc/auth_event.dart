import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class LoginSubmitted extends AuthEvent {
  const LoginSubmitted({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

class SignUpSubmitted extends AuthEvent {
  const SignUpSubmitted({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

class ToggleModeRequested extends AuthEvent {
  const ToggleModeRequested();
}

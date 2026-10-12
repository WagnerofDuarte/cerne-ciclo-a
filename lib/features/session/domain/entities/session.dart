import 'package:cerne/features/auth/domain/entities/account.dart';
import 'package:equatable/equatable.dart';

/// Represents whether the user is currently authenticated; drives splash
/// routing (FR-009) and the "Sessão expirada" overlay (FR-013).
class Session extends Equatable {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.tokenType,
    required this.account,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String tokenType;
  final Account account;

  @override
  List<Object?> get props => [
        accessToken,
        refreshToken,
        expiresAt,
        tokenType,
        account,
      ];
}

import 'package:cerne/core/network/failure.dart';
import 'package:fpdart/fpdart.dart';

/// Deliberately narrow — a single field's read/write/clear path, rather
/// than a general-purpose account-settings repository (research.md R7,
/// contracts/account-profile-repository.md).
abstract class AccountProfileRepository {
  /// Local-only, no network, no `Either` — nothing here can fail in a way
  /// the caller must branch on beyond "was it ever set".
  Future<String?> readCachedDisplayName();

  /// `PATCH account-settings-update` with `{"displayName": name}` only. On
  /// `Right`, the response's own `data.displayName` (not the caller's input
  /// string) is written to the local cache before being returned.
  Future<Either<Failure, String>> updateDisplayName(String name);

  /// Deletes the one Keychain key; called by both the logout and
  /// account-deletion flows (research.md R9).
  Future<void> clearCachedDisplayName();
}

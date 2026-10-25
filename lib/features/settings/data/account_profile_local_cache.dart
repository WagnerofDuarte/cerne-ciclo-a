import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// On-device, cross-restart persistence for the confirmed display name
/// (research.md R5) — Keychain-backed, one key, same pattern as
/// `VaultSecureStorage`. The only new local persistence this unit
/// introduces.
class AccountProfileLocalCache {
  AccountProfileLocalCache({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'settingsDisplayName';

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String name) => _storage.write(key: _key, value: name);

  Future<void> clear() => _storage.delete(key: _key);
}

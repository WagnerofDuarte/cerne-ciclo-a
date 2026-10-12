import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps `flutter_secure_storage` for the four session fields (data-model.md
/// Session) — iOS Keychain-backed, never plaintext (research.md R5).
class SecureTokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  static const _expiresAtKey = 'expiresAt';
  static const _tokenTypeKey = 'tokenType';

  Future<void> writeSession({
    required String accessToken,
    required String refreshToken,
    required int expiresAt,
    required String tokenType,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _expiresAtKey, value: expiresAt.toString());
    await _storage.write(key: _tokenTypeKey, value: tokenType);
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<int?> readExpiresAt() async {
    final raw = await _storage.read(key: _expiresAtKey);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<String?> readTokenType() => _storage.read(key: _tokenTypeKey);

  Future<void> delete() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
    await _storage.delete(key: _tokenTypeKey);
  }
}

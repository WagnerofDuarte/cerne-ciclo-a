import 'dart:convert';

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

  /// Reads the `email` claim straight out of the stored access token's own
  /// JWT payload — no network call, and no new field to persist, since the
  /// access token (GoTrue-issued) already carries it. A JWT's payload is
  /// signed, never encrypted, so decoding it client-side (never verifying
  /// the signature — that's the backend's job on every request) reveals
  /// nothing the backend doesn't already hand this device. `null` for
  /// anything malformed or missing, never throws.
  Future<String?> readAccountEmail() async {
    final token = await readAccessToken();
    if (token == null) return null;
    final segments = token.split('.');
    if (segments.length != 3) return null;
    try {
      final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(segments[1])));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      return payload['email'] as String?;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> delete() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiresAtKey);
    await _storage.delete(key: _tokenTypeKey);
  }
}

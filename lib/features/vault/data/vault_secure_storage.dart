import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain-backed storage for the two keys this unit adds: the PIN hash
/// and the local biometrics-preference mirror (data-model.md Device PIN /
/// Biometrics Preference). `savePin`/PIN comparison store and compare only
/// `sha256(pin)` (hex string), never the raw digit string (research.md R2).
class VaultSecureStorage {
  VaultSecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _pinHashKey = 'vaultPinHash';
  static const _biometricPreferenceKey = 'vaultBiometricPreference';

  static final RegExp _fourDigits = RegExp(r'^[0-9]{4}$');

  Future<bool> hasPinConfigured() async {
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null;
  }

  Future<void> savePin(String pin) async {
    _assertFourDigits(pin);
    await _storage.write(key: _pinHashKey, value: _hash(pin));
  }

  Future<bool> verifyPin(String pin) async {
    _assertFourDigits(pin);
    final storedHash = await _storage.read(key: _pinHashKey);
    return storedHash != null && storedHash == _hash(pin);
  }

  Future<bool> readBiometricPreference() async {
    final raw = await _storage.read(key: _biometricPreferenceKey);
    return raw == 'true';
  }

  Future<void> writeBiometricPreference(bool enabled) =>
      _storage.write(key: _biometricPreferenceKey, value: enabled.toString());

  void _assertFourDigits(String pin) {
    if (!_fourDigits.hasMatch(pin)) {
      throw ArgumentError.value(
        pin,
        'pin',
        'must be exactly 4 digits, each 0-9',
      );
    }
  }

  String _hash(String pin) => sha256.convert(utf8.encode(pin)).toString();
}

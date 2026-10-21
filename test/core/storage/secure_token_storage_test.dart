import 'dart:convert';

import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.fake-signature';
}

void main() {
  late MockFlutterSecureStorage storage;
  late SecureTokenStorage tokenStorage;

  setUp(() {
    storage = MockFlutterSecureStorage();
    tokenStorage = SecureTokenStorage(storage: storage);
  });

  group('readAccountEmail', () {
    test('decodes the "email" claim out of the stored access token', () async {
      final jwt = _fakeJwt({'sub': 'u1', 'email': 'wagner@example.com'});
      when(() => storage.read(key: 'accessToken')).thenAnswer((_) async => jwt);

      expect(await tokenStorage.readAccountEmail(), 'wagner@example.com');
    });

    test('no stored access token -> null', () async {
      when(() => storage.read(key: 'accessToken')).thenAnswer((_) async => null);

      expect(await tokenStorage.readAccountEmail(), isNull);
    });

    test('a token that is not a 3-part JWT -> null, never throws', () async {
      when(() => storage.read(key: 'accessToken')).thenAnswer((_) async => 'not-a-jwt');

      expect(await tokenStorage.readAccountEmail(), isNull);
    });

    test('a JWT payload with no "email" claim -> null', () async {
      final jwt = _fakeJwt({'sub': 'u1'});
      when(() => storage.read(key: 'accessToken')).thenAnswer((_) async => jwt);

      expect(await tokenStorage.readAccountEmail(), isNull);
    });

    test('a JWT whose payload segment is not valid base64/JSON -> null, never throws', () async {
      when(() => storage.read(key: 'accessToken')).thenAnswer((_) async => 'a.not-base64-json.c');

      expect(await tokenStorage.readAccountEmail(), isNull);
    });
  });
}

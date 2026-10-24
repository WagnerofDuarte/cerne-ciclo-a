import 'dart:typed_data';

import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockDio extends Mock implements Dio {}

class MockSecureTokenStorage extends Mock implements SecureTokenStorage {}

void main() {
  late MockDio dio;
  late MockSecureTokenStorage tokenStorage;
  late ApiClient client;

  const anonKey = 'anon-key';
  const baseUrl = 'https://example.supabase.co/functions/v1';
  const location = 'https://storage.example.com/signed/export.pdf?token=abc';

  setUpAll(() {
    dotenv.loadFromString(envString: 'FUNCTIONS_BASE_URL=$baseUrl');
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = MockDio();
    tokenStorage = MockSecureTokenStorage();
    when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => 'default-token');
    client = ApiClient(dio: dio, tokenStorage: tokenStorage, anonKey: anonKey);
  });

  void stubRedirect({int statusCode = 302, String? locationHeader = location}) {
    when(
      () => dio.request<void>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: ''),
        statusCode: statusCode,
        headers: Headers.fromMap(
          locationHeader == null ? {} : {'location': [locationHeader]},
        ),
      ),
    );
  }

  void stubRedirectThrows(DioException exception) {
    when(
      () => dio.request<void>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenThrow(exception);
  }

  void stubFileFetch(List<int> bytes) {
    when(
      () => dio.request<List<int>>(any(), options: any(named: 'options')),
    ).thenAnswer(
      (_) async => Response<List<int>>(
        requestOptions: RequestOptions(path: ''),
        statusCode: 200,
        data: bytes,
      ),
    );
  }

  void stubFileFetchThrows(DioException exception) {
    when(
      () => dio.request<List<int>>(any(), options: any(named: 'options')),
    ).thenThrow(exception);
  }

  test('scenario 1: 302 + location, then 200 + bytes -> Right(Uint8List) '
      'with exactly those bytes', () async {
    stubRedirect();
    stubFileFetch([1, 2, 3]);

    final result = await client.downloadFile('export-download-get', pathSegments: ['job-1']);

    expect(result.isRight(), isTrue);
    expect(result.getRight().toNullable(), Uint8List.fromList([1, 2, 3]));
  });

  test('scenario 2: leg 1 returns 200 (no redirect) -> ValidationFailure', () async {
    stubRedirect(statusCode: 200, locationHeader: null);

    final result = await client.downloadFile('export-download-get', pathSegments: ['job-1']);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('scenario 3: 302 with no location header -> ValidationFailure', () async {
    stubRedirect(locationHeader: null);

    final result = await client.downloadFile('export-download-get', pathSegments: ['job-1']);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('scenario 4: leg 1 throws a DioException with {code: AUTH_EXPIRED} -> '
      'AuthExpiredFailure, identical mapping to call()\'s own handling', () async {
    stubRedirectThrows(
      DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.badResponse,
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: ''),
          statusCode: 401,
          data: {'code': 'AUTH_EXPIRED', 'message': 'expired', 'retryable': false, 'requestId': 'r1'},
        ),
      ),
    );

    final result = await client.downloadFile('export-download-get', pathSegments: ['job-1']);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<AuthExpiredFailure>());
  });

  test('scenario 5: leg 1 ok; leg 2 throws connectionTimeout -> '
      'NetworkTimeoutFailure (the storage-leg failure)', () async {
    stubRedirect();
    stubFileFetchThrows(
      DioException(requestOptions: RequestOptions(path: ''), type: DioExceptionType.connectionTimeout),
    );

    final result = await client.downloadFile('export-download-get', pathSegments: ['job-1']);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<NetworkTimeoutFailure>());
  });

  test('scenario 6: leg 1 ok; leg 2 throws with no response at all -> '
      'NetworkOfflineFailure', () async {
    stubRedirect();
    stubFileFetchThrows(
      DioException(requestOptions: RequestOptions(path: ''), type: DioExceptionType.connectionError),
    );

    final result = await client.downloadFile('export-download-get', pathSegments: ['job-1']);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<NetworkOfflineFailure>());
  });

  test('scenario 7: queryParameters reach leg 1\'s request verbatim', () async {
    stubRedirect();
    stubFileFetch([1]);

    await client.downloadFile(
      'export-download-get',
      pathSegments: ['job-1'],
      queryParameters: {'format': 'raw'},
    );

    verify(
      () => dio.request<void>(
        '$baseUrl/export-download-get/job-1',
        queryParameters: {'format': 'raw'},
        options: any(named: 'options'),
      ),
    ).called(1);
  });
}

import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/core/storage/secure_token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fpdart/fpdart.dart';
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

  void stubRequestSuccess(dynamic responseData, {int statusCode = 200}) {
    when(
      () => dio.request<Map<String, dynamic>>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: ''),
        statusCode: statusCode,
        data: responseData as Map<String, dynamic>?,
      ),
    );
  }

  void stubRequestThrows(DioException exception) {
    when(
      () => dio.request<Map<String, dynamic>>(
        any(),
        data: any(named: 'data'),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenThrow(exception);
  }

  group('URL construction', () {
    test('builds {FUNCTIONS_BASE_URL}/<function>', () async {
      stubRequestSuccess({'data': <String, dynamic>{}});

      await client.call('auth-login', method: 'POST');

      verify(
        () => dio.request<Map<String, dynamic>>(
          '$baseUrl/auth-login',
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('appends pathSegments in order', () async {
      stubRequestSuccess({'data': <String, dynamic>{}});

      await client.call(
        'records',
        method: 'GET',
        pathSegments: ['123', 'items'],
      );

      verify(
        () => dio.request<Map<String, dynamic>>(
          '$baseUrl/records/123/items',
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('passes queryParameters straight through to Dio.request() when provided', () async {
      stubRequestSuccess({'data': <String, dynamic>{}});

      await client.call(
        'entries-list',
        method: 'GET',
        queryParameters: {'cursor': 'abc'},
      );

      verify(
        () => dio.request<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          queryParameters: {'cursor': 'abc'},
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('omits queryParameters (sends null) when not provided', () async {
      stubRequestSuccess({'data': <String, dynamic>{}});

      await client.call('entries-list', method: 'GET');

      verify(
        () => dio.request<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          queryParameters: null,
          options: any(named: 'options'),
        ),
      ).called(1);
    });
  });

  group('headers and AuthMode', () {
    test('every call carries apikey: <anonKey>', () async {
      stubRequestSuccess({'data': <String, dynamic>{}});

      await client.call('auth-login', method: 'POST', authMode: AuthMode.anonKey);

      final captured = verify(
        () => dio.request<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: captureAny(named: 'options'),
        ),
      ).captured;
      final options = captured.single as Options;
      expect(options.headers?['apikey'], anonKey);
    });

    test('AuthMode.anonKey sends Authorization: Bearer <anonKey>', () async {
      stubRequestSuccess({'data': <String, dynamic>{}});

      await client.call('auth-login', method: 'POST', authMode: AuthMode.anonKey);

      final captured = verify(
        () => dio.request<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: captureAny(named: 'options'),
        ),
      ).captured;
      final options = captured.single as Options;
      expect(options.headers?['Authorization'], 'Bearer $anonKey');
      verifyNever(() => tokenStorage.readAccessToken());
    });

    test('AuthMode.userSession sends Authorization: Bearer <stored accessToken>', () async {
      when(() => tokenStorage.readAccessToken()).thenAnswer((_) async => 'stored-token');
      stubRequestSuccess({'data': <String, dynamic>{}});

      await client.call('auth-session', method: 'GET', authMode: AuthMode.userSession);

      final captured = verify(
        () => dio.request<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: captureAny(named: 'options'),
        ),
      ).captured;
      final options = captured.single as Options;
      expect(options.headers?['Authorization'], 'Bearer stored-token');
    });
  });

  group('success envelope', () {
    test('returns Right(data), discarding meta', () async {
      stubRequestSuccess({
        'data': {'id': '1'},
        'meta': {'ignored': true},
      });

      final result = await client.call('auth-login', method: 'POST');

      expect(result.isRight(), isTrue);
      expect(result.getRight().toNullable(), equals({'id': '1'}));
    });

    test('a "data" field that is present but not a JSON object maps to a Failure '
        'instead of throwing', () async {
      stubRequestSuccess({'data': 'not-an-object'});

      final result = await client.call('auth-login', method: 'POST');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a "data" field that is a list also maps to a Failure instead of throwing', () async {
      stubRequestSuccess({'data': [1, 2, 3]});

      final result = await client.call('auth-login', method: 'POST');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a missing "data" field returns Right({})', () async {
      stubRequestSuccess({'meta': {}});

      final result = await client.call('auth-login', method: 'POST');

      expect(result.isRight(), isTrue);
      expect(result.getRight().toNullable(), equals(<String, dynamic>{}));
    });

    test('unwrapData: false returns the full decoded body verbatim, including '
        'a list-shaped "data" and "meta"', () async {
      stubRequestSuccess({
        'data': [
          {'id': '1'},
        ],
        'meta': {'nextCursor': 'xyz'},
      });

      final result = await client.call('entries-list', method: 'GET', unwrapData: false);

      expect(result.isRight(), isTrue);
      expect(
        result.getRight().toNullable(),
        equals({
          'data': [
            {'id': '1'},
          ],
          'meta': {'nextCursor': 'xyz'},
        }),
      );
    });
  });

  group('failure mapping', () {
    test('non-2xx with {code,message,retryable,requestId} body maps via ErrorMapper', () async {
      stubRequestThrows(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: ''),
            statusCode: 401,
            data: {
              'code': 'AUTH_INVALID',
              'message': 'wrong credentials',
              'retryable': false,
              'requestId': 'req-1',
            },
          ),
        ),
      );

      final result = await client.call('auth-login', method: 'POST');

      expect(
        result,
        const Left<Failure, Map<String, dynamic>>(
          AuthInvalidFailure(message: 'wrong credentials', requestId: 'req-1'),
        ),
      );
    });

    test('a connection error with no response maps to NetworkOfflineFailure', () async {
      stubRequestThrows(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ),
      );

      final result = await client.call('auth-login', method: 'POST');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<NetworkOfflineFailure>());
    });

    test('a timeout maps to NetworkTimeoutFailure', () async {
      stubRequestThrows(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await client.call('auth-login', method: 'POST');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<NetworkTimeoutFailure>());
    });

    test('never throws past the ApiClient boundary for any DioException', () async {
      stubRequestThrows(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.unknown,
        ),
      );

      await expectLater(client.call('auth-login', method: 'POST'), completes);
    });
  });
}

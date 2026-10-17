import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/data/entries_remote_data_source.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient apiClient;
  late EntriesRemoteDataSource dataSource;

  final validData = {
    'id': 'entry-1',
    'content': 'hello',
    'source': 'manual',
    'chatMessageId': null,
    'occurredAt': '2026-01-01T00:00:00.000Z',
    'tags': <dynamic>[],
    'piiStatus': 'pending',
    'piiSpans': <dynamic>[],
    'embeddingStatus': 'pending',
    'mediaDurationSeconds': null,
    'serverRevision': 1,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
  };

  setUpAll(() {
    registerFallbackValue(AuthMode.userSession);
  });

  setUp(() {
    apiClient = MockApiClient();
    dataSource = EntriesRemoteDataSource(apiClient);
  });

  void stubCall(Either<Failure, Map<String, dynamic>> result) {
    when(
      () => apiClient.call(
        'entries-create',
        method: any(named: 'method'),
        body: any(named: 'body'),
        pathSegments: any(named: 'pathSegments'),
        authMode: any(named: 'authMode'),
      ),
    ).thenAnswer((_) async => result);
  }

  test('calls apiClient.call(entries-create, ...) with content/source', () async {
    stubCall(Right(validData));

    await dataSource.create(content: 'hello', source: EntrySource.manual);

    verify(
      () => apiClient.call(
        'entries-create',
        method: 'POST',
        body: {'content': 'hello', 'source': 'manual'},
      ),
    ).called(1);
  });

  test('parses a valid success body into Entry', () async {
    stubCall(Right(validData));

    final result = await dataSource.create(content: 'hello', source: EntrySource.manual);

    expect(result.isRight(), isTrue);
    final entry = result.toNullable()!;
    expect(entry.id, 'entry-1');
    expect(entry.content, 'hello');
    expect(entry.source, EntrySource.manual);
    expect(entry.chatMessageId, isNull);
    expect(entry.tags, isEmpty);
    expect(entry.piiStatus, PiiStatus.pending);
    expect(entry.embeddingStatus, EmbeddingStatus.pending);
    expect(entry.mediaDurationSeconds, isNull);
    expect(entry.serverRevision, 1);
  });

  test('NetworkTimeoutFailure passes through unchanged', () async {
    const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
    stubCall(const Left(failure));

    final result = await dataSource.create(content: 'hello', source: EntrySource.manual);

    expect(result, const Left<Failure, Entry>(failure));
  });

  test('NetworkOfflineFailure passes through unchanged', () async {
    const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
    stubCall(const Left(failure));

    final result = await dataSource.create(content: 'hello', source: EntrySource.manual);

    expect(result, const Left<Failure, Entry>(failure));
  });

  test('a malformed success body becomes ValidationFailure', () async {
    stubCall(const Right({'unexpected': true}));

    final result = await dataSource.create(content: 'hello', source: EntrySource.manual);

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ValidationFailure>());
  });

  group('list()', () {
    void stubListCall(Either<Failure, Map<String, dynamic>> result) {
      when(
        () => apiClient.call(
          'entries-list',
          method: any(named: 'method'),
          body: any(named: 'body'),
          pathSegments: any(named: 'pathSegments'),
          queryParameters: any(named: 'queryParameters'),
          authMode: any(named: 'authMode'),
          unwrapData: any(named: 'unwrapData'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('list(cursor: "abc") sends queryParameters: {cursor: "abc"}', () async {
      stubListCall(Right({'data': <dynamic>[], 'meta': {'nextCursor': null}}));

      await dataSource.list(cursor: 'abc');

      verify(
        () => apiClient.call(
          'entries-list',
          method: 'GET',
          queryParameters: {'cursor': 'abc'},
          unwrapData: false,
        ),
      ).called(1);
    });

    test('list() with no cursor sends queryParameters: null', () async {
      stubListCall(Right({'data': <dynamic>[], 'meta': {'nextCursor': null}}));

      await dataSource.list();

      verify(
        () => apiClient.call(
          'entries-list',
          method: 'GET',
          queryParameters: null,
          unwrapData: false,
        ),
      ).called(1);
    });

    test('parses data + meta.nextCursor into an EntriesPage', () async {
      stubListCall(Right({
        'data': [validData],
        'meta': {'nextCursor': 'next-1'},
      }));

      final result = await dataSource.list();

      expect(result.isRight(), isTrue);
      final page = result.toNullable()!;
      expect(page.entries, hasLength(1));
      expect(page.entries.single.id, 'entry-1');
      expect(page.nextCursor, 'next-1');
    });

    test('a null meta.nextCursor means the last page', () async {
      stubListCall(Right({'data': <dynamic>[], 'meta': {'nextCursor': null}}));

      final result = await dataSource.list();

      expect(result.toNullable()!.nextCursor, isNull);
    });

    test('a response containing a chat-sourced entry parses to EntrySource.chat '
        'without throwing', () async {
      final chatEntry = {...validData, 'source': 'chat'};
      stubListCall(Right({
        'data': [chatEntry],
        'meta': {'nextCursor': null},
      }));

      final result = await dataSource.list();

      expect(result.isRight(), isTrue);
      expect(result.toNullable()!.entries.single.source, EntrySource.chat);
    });

    test('a malformed response maps to ValidationFailure', () async {
      stubListCall(const Right({'unexpected': true}));

      final result = await dataSource.list();

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a non-auth failure passes through unchanged', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
      stubListCall(const Left(failure));

      final result = await dataSource.list();

      expect(result, const Left<Failure, dynamic>(failure));
    });
  });

  group('getById()', () {
    void stubGetByIdCall(Either<Failure, Map<String, dynamic>> result) {
      when(
        () => apiClient.call(
          'entries-get',
          method: any(named: 'method'),
          body: any(named: 'body'),
          pathSegments: any(named: 'pathSegments'),
          authMode: any(named: 'authMode'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('calls apiClient.call(entries-get, ..., pathSegments: [id])', () async {
      stubGetByIdCall(Right(validData));

      await dataSource.getById('entry-1');

      verify(
        () => apiClient.call(
          'entries-get',
          method: 'GET',
          pathSegments: ['entry-1'],
        ),
      ).called(1);
    });

    test('parses a valid success body into Entry', () async {
      stubGetByIdCall(Right(validData));

      final result = await dataSource.getById('entry-1');

      expect(result.isRight(), isTrue);
      expect(result.toNullable()!.id, 'entry-1');
    });

    test('a malformed response maps to ValidationFailure', () async {
      stubGetByIdCall(const Right({'unexpected': true}));

      final result = await dataSource.getById('entry-1');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a non-auth failure passes through unchanged', () async {
      const failure = NetworkOfflineFailure(message: 'no connection', requestId: 'r2');
      stubGetByIdCall(const Left(failure));

      final result = await dataSource.getById('entry-1');

      expect(result, const Left<Failure, Entry>(failure));
    });
  });
}

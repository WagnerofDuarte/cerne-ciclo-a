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

  group('chat extension (P-RF10)', () {
    test('chatMessageId + occurredAt both present and correctly formatted '
        'in the body', () async {
      stubCall(Right(validData));
      final occurredAt = DateTime.utc(2026, 1, 1, 9);

      await dataSource.create(
        content: 'hi',
        source: EntrySource.chat,
        chatMessageId: 'msg-1',
        occurredAt: occurredAt,
      );

      verify(
        () => apiClient.call(
          'entries-create',
          method: 'POST',
          body: {
            'content': 'hi',
            'source': 'chat',
            'chatMessageId': 'msg-1',
            'occurredAt': occurredAt.toUtc().toIso8601String(),
          },
        ),
      ).called(1);
    });

    test('chatMessageId only -> no occurredAt key present', () async {
      stubCall(Right(validData));

      await dataSource.create(
        content: 'hi',
        source: EntrySource.chat,
        chatMessageId: 'msg-1',
      );

      verify(
        () => apiClient.call(
          'entries-create',
          method: 'POST',
          body: {'content': 'hi', 'source': 'chat', 'chatMessageId': 'msg-1'},
        ),
      ).called(1);
    });

    test('a 200 response whose chatMessageId matches a value already saved '
        'once parses to Right(Entry) with no special handling '
        '(idempotent-retry path)', () async {
      stubCall(Right({...validData, 'chatMessageId': 'msg-1'}));

      final result = await dataSource.create(
        content: 'hi',
        source: EntrySource.chat,
        chatMessageId: 'msg-1',
      );

      expect(result.isRight(), isTrue);
      expect(result.toNullable()!.chatMessageId, 'msg-1');
    });
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

    test('list(source: EntrySource.audio) sends queryParameters: {source: '
        '"audio"}, no dateFrom/dateTo/limit keys', () async {
      stubListCall(Right({'data': <dynamic>[], 'meta': {'nextCursor': null}}));

      await dataSource.list(source: EntrySource.audio);

      verify(
        () => apiClient.call(
          'entries-list',
          method: 'GET',
          queryParameters: {'source': 'audio'},
          unwrapData: false,
        ),
      ).called(1);
    });

    test('list(dateFrom:, dateTo:) sends both as UTC ISO-8601 strings', () async {
      stubListCall(Right({'data': <dynamic>[], 'meta': {'nextCursor': null}}));
      final from = DateTime.utc(2026, 10, 1);
      final to = DateTime.utc(2026, 10, 15);

      await dataSource.list(dateFrom: from, dateTo: to);

      verify(
        () => apiClient.call(
          'entries-list',
          method: 'GET',
          queryParameters: {
            'dateFrom': from.toUtc().toIso8601String(),
            'dateTo': to.toUtc().toIso8601String(),
          },
          unwrapData: false,
        ),
      ).called(1);
    });

    test('list() with every new param omitted sends queryParameters: null '
        '(no regression from RF07\'s original call shape)', () async {
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

    test('a response including a similarity value parses into a non-null '
        'Entry.similarity', () async {
      stubListCall(Right({
        'data': [
          {...validData, 'similarity': 0.87},
        ],
        'meta': {'nextCursor': null},
      }));

      final result = await dataSource.list();

      expect(result.toNullable()!.entries.single.similarity, 0.87);
    });

    test('a response omitting similarity parses to Entry.similarity == null', () async {
      stubListCall(Right({
        'data': [validData],
        'meta': {'nextCursor': null},
      }));

      final result = await dataSource.list();

      expect(result.toNullable()!.entries.single.similarity, isNull);
    });
  });

  group('search()', () {
    void stubSearchCall(Either<Failure, Map<String, dynamic>> result) {
      when(
        () => apiClient.call(
          'entries-search',
          method: any(named: 'method'),
          body: any(named: 'body'),
          pathSegments: any(named: 'pathSegments'),
          queryParameters: any(named: 'queryParameters'),
          authMode: any(named: 'authMode'),
          unwrapData: any(named: 'unwrapData'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('search(q: "ansiedade") sends q and the default limit: 50, no '
        'source/dateFrom/dateTo', () async {
      stubSearchCall(Right({'data': <dynamic>[]}));

      await dataSource.search(q: 'ansiedade');

      verify(
        () => apiClient.call(
          'entries-search',
          method: 'GET',
          queryParameters: {'q': 'ansiedade', 'limit': '50'},
          unwrapData: false,
        ),
      ).called(1);
    });

    test('a response similarity value parses into a non-null Entry.similarity', () async {
      stubSearchCall(Right({
        'data': [
          {...validData, 'similarity': 0.42},
        ],
      }));

      final result = await dataSource.search(q: 'ansiedade');

      expect(result.toNullable()!.single.similarity, 0.42);
    });

    test('a response omitting similarity parses to Entry.similarity == null', () async {
      stubSearchCall(Right({'data': [validData]}));

      final result = await dataSource.search(q: 'ansiedade');

      expect(result.toNullable()!.single.similarity, isNull);
    });

    test('an empty q string omits the q key entirely (never sends q=)', () async {
      stubSearchCall(Right({'data': <dynamic>[]}));

      await dataSource.search(q: '');

      verify(
        () => apiClient.call(
          'entries-search',
          method: 'GET',
          queryParameters: {'limit': '50'},
          unwrapData: false,
        ),
      ).called(1);
    });

    test('a malformed entries-search response maps to ValidationFailure, not '
        'a thrown exception', () async {
      stubSearchCall(const Right({'unexpected': true}));

      final result = await dataSource.search(q: 'ansiedade');

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
    });

    test('a non-auth failure passes through unchanged', () async {
      const failure = NetworkTimeoutFailure(message: 'timed out', requestId: 'r1');
      stubSearchCall(const Left(failure));

      final result = await dataSource.search(q: 'ansiedade');

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

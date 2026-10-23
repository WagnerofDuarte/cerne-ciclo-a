import 'package:cerne/features/chat/data/chat_local_cache.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage storage;
  late ChatLocalCache cache;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    storage = MockFlutterSecureStorage();
    cache = ChatLocalCache(storage: storage);
  });

  group('readSavedMessageEntryIds()/writeSavedMessageEntryIds()', () {
    test('readSavedMessageEntryIds() returns {} when nothing has been written yet', () async {
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => null);

      expect(await cache.readSavedMessageEntryIds(), isEmpty);
    });

    test('writeSavedMessageEntryIds({"m1": "e1"}) then read round-trips', () async {
      String? stored;
      when(
        () => storage.write(key: any(named: 'key'), value: any(named: 'value')),
      ).thenAnswer((invocation) async {
        stored = invocation.namedArguments[#value] as String;
      });
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => stored);

      await cache.writeSavedMessageEntryIds({'m1': 'e1'});

      expect(await cache.readSavedMessageEntryIds(), {'m1': 'e1'});
    });

    test('readSavedMessageEntryIds() over corrupted/non-JSON data returns {}, no throw', () async {
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => 'not json');

      expect(await cache.readSavedMessageEntryIds(), isEmpty);
    });
  });
}

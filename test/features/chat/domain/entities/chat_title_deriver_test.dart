import 'package:cerne/features/chat/domain/entities/chat_title_deriver.dart';
import 'package:test/test.dart';

void main() {
  group('ChatTitleDeriver.derive', () {
    test('collapses internal whitespace/newlines to single spaces and trims', () {
      expect(
        ChatTitleDeriver.derive('  Como lidar  \n com\tansiedade  '),
        'Como lidar com ansiedade',
      );
    });

    test('returns the input unchanged at or under 48 characters', () {
      final input = 'a' * 48;
      expect(ChatTitleDeriver.derive(input), input);
    });

    test('truncates to exactly 48 characters + "…" when longer', () {
      final input = 'a' * 60;
      final result = ChatTitleDeriver.derive(input);
      expect(result, '${'a' * 48}…');
      expect(result.length, 49);
    });

    test('never returns an empty string for any non-empty input', () {
      expect(ChatTitleDeriver.derive('a'), isNotEmpty);
      expect(ChatTitleDeriver.derive('   a   '), isNotEmpty);
    });
  });
}

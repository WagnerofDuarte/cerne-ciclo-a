import 'package:cerne/features/settings/domain/entities/account_profile.dart';
import 'package:test/test.dart';

void main() {
  group('AccountProfile.defaultDisplayNameFromEmail', () {
    test('splits the local part on ._- and title-cases each word', () {
      expect(
        AccountProfile.defaultDisplayNameFromEmail('wagner.duarte@x.com'),
        'Wagner Duarte',
      );
    });

    test('falls back to the email itself when the local part is empty', () {
      expect(
        AccountProfile.defaultDisplayNameFromEmail('@x.com'),
        '@x.com',
      );
    });
  });

  group('AccountProfile.initials', () {
    test('two-word name returns both initials', () {
      const profile = AccountProfile(displayName: 'Wagner Duarte', email: '');
      expect(profile.initials, 'WD');
    });

    test('one-word name returns a single initial', () {
      const profile = AccountProfile(displayName: 'Wagner', email: '');
      expect(profile.initials, 'W');
    });

    test('empty displayName returns "?"', () {
      const profile = AccountProfile(displayName: '', email: '');
      expect(profile.initials, '?');
    });
  });

  group('AccountProfile.isValidDisplayName', () {
    test('empty string is invalid', () {
      expect(AccountProfile.isValidDisplayName(''), isFalse);
    });

    test('exactly 80 chars is valid', () {
      expect(AccountProfile.isValidDisplayName('a' * 80), isTrue);
    });

    test('81 chars is invalid', () {
      expect(AccountProfile.isValidDisplayName('a' * 81), isFalse);
    });

    test('whitespace-only is invalid', () {
      expect(AccountProfile.isValidDisplayName('   '), isFalse);
    });
  });
}

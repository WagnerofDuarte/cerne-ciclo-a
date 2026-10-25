import 'package:equatable/equatable.dart';

/// The screen's single source of truth for both the name field and avatar
/// initials (data-model.md). [email] is read-only in this unit (FR-009),
/// sourced from `SessionRepository`'s already-resolved `Account.email`.
class AccountProfile extends Equatable {
  const AccountProfile({required this.displayName, required this.email});

  final String displayName;
  final String email;

  /// Splits the email's local part on `._-`, title-cases each word, joins
  /// with a space (`"wagner.duarte@x.com"` -> `"Wagner Duarte"`); `email`
  /// itself if the local part is empty. Relocated byte-for-byte from
  /// `app_drawer.dart`'s own `_displayNameFromEmail`/`_emailNameWords`
  /// (research.md R13, contracts/app-drawer-display-name-extension.md).
  static String defaultDisplayNameFromEmail(String email) {
    final words = _emailNameWords(email);
    if (words.isEmpty) return email;
    return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  static List<String> _emailNameWords(String email) => email
      .split('@')
      .first
      .split(RegExp(r'[._-]+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// 1–2 uppercase letters from [displayName]'s whitespace-split words
  /// (first letter of the first word, plus first letter of the second word
  /// if one exists); `"?"` if [displayName] is empty.
  String get initials {
    final words = displayName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }

  /// FR-011: `1 <= value.trim().length <= 80`.
  static bool isValidDisplayName(String value) =>
      value.trim().isNotEmpty && value.trim().length <= 80;

  @override
  List<Object?> get props => [displayName, email];
}

/// Derives a side-menu preview title from a conversation's first message
/// (FR-010, research.md R6). Pure, total; no `package:flutter` import, no
/// I/O (Principle V).
class ChatTitleDeriver {
  const ChatTitleDeriver._();

  static const _maxLength = 48;

  /// Collapses internal whitespace/newlines to single spaces, trims, and
  /// caps the result at 48 characters (appending `'…'` when truncated).
  /// Never returns an empty string for non-empty input.
  static String derive(String firstMessageText) {
    final collapsed = firstMessageText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= _maxLength) return collapsed;
    return '${collapsed.substring(0, _maxLength)}…';
  }
}

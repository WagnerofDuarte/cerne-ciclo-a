import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/domain/entities/bookmark_status.dart';
import 'package:flutter/material.dart';

/// Renders one icon/spinner per [BookmarkStatus] (research.md R7/R8). The
/// `GestureDetector` is omitted entirely (not merely disabled) for
/// `saving`/`saved` — FR-003's literal "carries no tap handler".
class BookmarkButton extends StatelessWidget {
  const BookmarkButton({required this.status, this.onTap, super.key});

  final BookmarkStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (status) {
      BookmarkStatus.idle => const Icon(
        Icons.bookmark_border,
        size: DesignTokens.sizeBookmarkIcon,
        color: DesignTokens.colorTextSecondary,
      ),
      BookmarkStatus.saving => const _BookmarkSpinner(),
      BookmarkStatus.saved => const Icon(
        Icons.check,
        size: DesignTokens.sizeBookmarkIcon,
        color: DesignTokens.colorAccent,
      ),
      BookmarkStatus.error => const Icon(
        Icons.error_outline,
        size: DesignTokens.sizeBookmarkIcon,
        color: DesignTokens.colorError,
      ),
    };

    switch (status) {
      case BookmarkStatus.saving:
      case BookmarkStatus.saved:
        return icon;
      case BookmarkStatus.idle:
      case BookmarkStatus.error:
        return GestureDetector(onTap: onTap, child: icon);
    }
  }
}

/// `CaptureLoadingIndicator`'s rotating-arc technique, resized to
/// [DesignTokens.sizeBookmarkIcon].
class _BookmarkSpinner extends StatefulWidget {
  const _BookmarkSpinner();

  @override
  State<_BookmarkSpinner> createState() => _BookmarkSpinnerState();
}

class _BookmarkSpinnerState extends State<_BookmarkSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DesignTokens.sizeBookmarkIcon,
      height: DesignTokens.sizeBookmarkIcon,
      child: RotationTransition(
        turns: _controller,
        child: const CircularProgressIndicator(
          strokeWidth: DesignTokens.strokeWidthLoadingIndicator,
          value: DesignTokens.valueLoadingIndicatorArc,
          color: DesignTokens.colorTextSecondary,
        ),
      ),
    );
  }
}

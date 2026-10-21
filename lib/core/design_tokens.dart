import 'package:flutter/widgets.dart';

/// Single source of truth for every color, type style, spacing, radius, and
/// elevation value used anywhere in the app (Constitution Principle IV; RNF08).
/// Transcribed verbatim from docs/input/prototype/prototype-extract.md §3.
class DesignTokens {
  const DesignTokens._();

  // Colors
  static const Color colorPrimary = Color(0xFF1F3D34);
  static const Color colorPrimaryPressed = Color(0xFF16281F);
  static const Color colorOnPrimary = Color(0xFFF5F1E8);
  static const Color colorAccent = Color(0xFFC98A3E);
  static const Color colorOnAccent = Color(0xFF241C0D);
  static const Color colorSecondary = Color(0xFF7C8B6F);
  static const Color colorSurfaceBg = Color(0xFFF2EFE7);
  static const Color colorSurfaceElevated = Color(0xFFFBF9F4);
  static const Color colorBorder = Color(0xFFE1DACB);
  static const Color colorTextPrimary = Color(0xFF241F19);
  static const Color colorTextSecondary = Color(0xFF6B6255);
  static const Color colorError = Color(0xFFB3402A);
  static const Color colorSuccess = Color(0xFF4C6B4F);
  static const Color colorWarningSync = Color(0xFFC98A3E);
  static const Color colorInfoOffline = Color(0xFF5C7A93);
  static const Color colorChatBubbleUser = Color(0xFFD9DFD3);

  // Typography
  static const String _fontFraunces = 'Fraunces';
  static const String _fontKarla = 'Karla';
  static const String _fontMono = 'IBM Plex Mono';

  static const TextStyle textDisplayLg = TextStyle(
    fontFamily: _fontFraunces,
    fontWeight: FontWeight.w600,
    fontSize: 32,
    height: 38 / 32,
    color: colorTextPrimary,
  );

  static const TextStyle textHeadlineMd = TextStyle(
    fontFamily: _fontFraunces,
    fontWeight: FontWeight.w600,
    fontSize: 24,
    height: 30 / 24,
    color: colorTextPrimary,
  );

  static const TextStyle textTitleLg = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 26 / 20,
    color: colorTextPrimary,
  );

  static const TextStyle textTitleSm = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    height: 22 / 16,
    color: colorTextPrimary,
  );

  static const TextStyle textBodyLg = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 24 / 16,
    color: colorTextPrimary,
  );

  static const TextStyle textBodyMd = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 20 / 14,
    color: colorTextPrimary,
  );

  static const TextStyle textLabelMd = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 18 / 13,
    color: colorTextPrimary,
  );

  static const TextStyle textMonoCaption = TextStyle(
    fontFamily: _fontMono,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.2,
    color: colorTextPrimary,
  );

  // Spacing (4 dp grid)
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacing2xl = 48;

  // Radii
  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 24;
  static const double radiusFull = 999;

  // Sizes
  static const double sizeLoadingDot = 8;
  static const double sizeLoadingIndicator = 20;
  static const double strokeWidthLoadingIndicator = 2;
  // The fixed sweep fraction of `CaptureLoadingIndicator`'s rotating ring —
  // kept constant (only the whole ring rotates) so it never collapses into
  // a short dash the way Material's default pulsing-arc animation does.
  static const double valueLoadingIndicatorArc = 0.75;
  static const double dividerThickness = 1;
  static const double borderWidthFocused = 1.5;
  static const double sizeKeypadTapTarget = 56;
  static const double sizeProgressDot = 10;
  static const double sizeBiometricIconContainer = 96;
  static const double sizeBiometricIcon = 44;
  static const double sizeAudioRecordButton = 72;
  static const double sizeAudioRecordIcon = 30;
  static const double sizePhotoTileIcon = 26;
  static const double sizePhotoThumbnail = 56;
  static const double sizePhotoThumbnailWideWidth = 96;
  static const double sizePhotoThumbnailWideHeight = 72;
  static const double sizeStatusIcon = 32;
  static const double sizeAvatarMenu = 40;

  // Elevation
  static const List<BoxShadow> elevation1 = [
    BoxShadow(
      color: Color.fromRGBO(36, 31, 25, 0.08),
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ];

  static const List<BoxShadow> elevation2 = [
    BoxShadow(
      color: Color.fromRGBO(36, 31, 25, 0.14),
      offset: Offset(0, 4),
      blurRadius: 16,
    ),
  ];
}

import 'package:cerne/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// The app's single [ThemeData], built solely from [DesignTokens] constants.
/// No literal color/size value belongs in this file (RNF08/Principle IV).
class AppTheme {
  const AppTheme._();

  static ThemeData get theme {
    final colorScheme = ColorScheme.light(
      primary: DesignTokens.colorPrimary,
      onPrimary: DesignTokens.colorOnPrimary,
      secondary: DesignTokens.colorSecondary,
      onSecondary: DesignTokens.colorOnPrimary,
      surface: DesignTokens.colorSurfaceElevated,
      onSurface: DesignTokens.colorTextPrimary,
      error: DesignTokens.colorError,
      onError: DesignTokens.colorOnPrimary,
      outline: DesignTokens.colorBorder,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignTokens.colorSurfaceBg,
      textTheme: const TextTheme(
        displayLarge: DesignTokens.textDisplayLg,
        headlineMedium: DesignTokens.textHeadlineMd,
        titleLarge: DesignTokens.textTitleLg,
        titleSmall: DesignTokens.textTitleSm,
        bodyLarge: DesignTokens.textBodyLg,
        bodyMedium: DesignTokens.textBodyMd,
        labelMedium: DesignTokens.textLabelMd,
        bodySmall: DesignTokens.textMonoCaption,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: DesignTokens.colorPrimary,
        foregroundColor: DesignTokens.colorOnPrimary,
        elevation: 0,
        titleTextStyle: DesignTokens.textTitleLg.copyWith(
          color: DesignTokens.colorOnPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignTokens.colorPrimary,
          foregroundColor: DesignTokens.colorOnPrimary,
          disabledBackgroundColor: DesignTokens.colorBorder,
          disabledForegroundColor: DesignTokens.colorTextSecondary,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: DesignTokens.spacingMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          textStyle: DesignTokens.textLabelMd,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? DesignTokens.colorPrimaryPressed
                : null,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignTokens.colorPrimary,
          side: const BorderSide(color: DesignTokens.colorPrimary),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: DesignTokens.spacingMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          ),
          textStyle: DesignTokens.textLabelMd,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DesignTokens.colorPrimary,
          textStyle: DesignTokens.textLabelMd,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignTokens.colorSurfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
          vertical: DesignTokens.spacingMd,
        ),
        labelStyle: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorTextSecondary,
        ),
        hintStyle: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorTextSecondary,
        ),
        errorStyle: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorError,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          borderSide: const BorderSide(color: DesignTokens.colorBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          borderSide: const BorderSide(color: DesignTokens.colorBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          borderSide: const BorderSide(
            color: DesignTokens.colorPrimary,
            width: DesignTokens.borderWidthFocused,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          borderSide: const BorderSide(color: DesignTokens.colorError),
        ),
      ),
      dividerTheme: const DividerThemeData(color: DesignTokens.colorBorder),
      drawerTheme: const DrawerThemeData(
        backgroundColor: DesignTokens.colorSurfaceElevated,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DesignTokens.colorSurfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
        titleTextStyle: DesignTokens.textHeadlineMd,
        contentTextStyle: DesignTokens.textBodyMd,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Ethereal Glass — dark-first, OLED base, IPN guinda as accent.
/// Display: Space Grotesk · Body/UI: Plus Jakarta Sans.
class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final TextTheme base = _buildTextTheme(Brightness.dark);
    final ColorScheme scheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentDeep,
      onSecondary: Colors.white,
      surface: AppColors.surface0,
      onSurface: Colors.white,
      surfaceContainerHighest: AppColors.surface2,
      error: AppColors.danger,
      onError: Colors.white,
      outline: Color(0x1FFFFFFF),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base,
      primaryTextTheme: base,
      iconTheme: IconThemeData(color: AppColors.textSecondary, size: 18),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: base.titleMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.accent),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: const WidgetStatePropertyAll(
            StadiumBorder(),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          ),
          textStyle: WidgetStatePropertyAll(
            base.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.white10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.textSecondary),
          overlayColor: const WidgetStatePropertyAll(Colors.white10),
          textStyle: WidgetStatePropertyAll(
            base.labelMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: base.bodyMedium?.copyWith(color: AppColors.textTertiary),
        labelStyle: base.bodyMedium?.copyWith(color: AppColors.textSecondary),
        floatingLabelStyle:
            base.labelMedium?.copyWith(color: AppColors.textPrimary),
        prefixIconColor: AppColors.textTertiary,
        suffixIconColor: AppColors.textTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.hairline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.hairlineStrong, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        errorStyle:
            base.bodySmall?.copyWith(color: AppColors.danger, height: 1.4),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.hairline,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface1,
        contentTextStyle: base.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.hairline),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.hairline),
        ),
        textStyle: base.bodySmall,
      ),
    );
  }

  /// Light mode kept simple — we design dark-first for the jurado experience.
  /// Judges usually evaluate under stage lighting where dark mode is easier.
  static ThemeData light() => dark();

  static TextTheme _buildTextTheme(Brightness brightness) {
    final Color primary = AppColors.textPrimary;
    final Color secondary = AppColors.textSecondary;

    final TextTheme display = GoogleFonts.spaceGroteskTextTheme();
    final TextTheme body = GoogleFonts.plusJakartaSansTextTheme();

    return TextTheme(
      displayLarge: display.displayLarge?.copyWith(
        fontSize: 88,
        fontWeight: FontWeight.w500,
        letterSpacing: -3.2,
        height: 0.98,
        color: primary,
      ),
      displayMedium: display.displayMedium?.copyWith(
        fontSize: 64,
        fontWeight: FontWeight.w500,
        letterSpacing: -2.4,
        height: 1.0,
        color: primary,
      ),
      displaySmall: display.displaySmall?.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w500,
        letterSpacing: -1.6,
        height: 1.05,
        color: primary,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w500,
        letterSpacing: -1.1,
        color: primary,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.6,
        color: primary,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleLarge: body.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleMedium: body.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: primary,
      ),
      titleSmall: body.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: primary,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: primary,
      ),
      bodySmall: body.bodySmall?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: secondary,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: primary,
      ),
      labelMedium: body.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: secondary,
      ),
      labelSmall: body.labelSmall?.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.4,
        color: secondary,
      ),
    );
  }
}

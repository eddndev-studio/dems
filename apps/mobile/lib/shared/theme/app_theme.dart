import 'package:flutter/material.dart';

class AppTheme {
  // Colores institucionales IPN (guinda).
  static const Color _ipnGuinda = Color(0xFF7B1532);
  static const Color _ipnGuindaDark = Color(0xFF5A0E25);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _ipnGuinda,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _ipnGuinda,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _ipnGuindaDark,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(elevation: 0),
    );
  }
}

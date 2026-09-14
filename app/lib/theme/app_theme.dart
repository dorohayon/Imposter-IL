import 'package:flutter/material.dart';

abstract final class AppColors {
  static const night = Color(0xFF14132B);
  static const nightSoft = Color(0xFF25233D);
  static const yellow = Color(0xFFFFD447);
  static const turquoise = Color(0xFF2DD4BF);
  static const coral = Color(0xFFFF6B6B);
  static const purple = Color(0xFF8B5CF6);
  static const cream = Color(0xFFFFF8E7);
  static const muted = Color(0xFFAAA7B4);
}

abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.yellow,
      onPrimary: AppColors.night,
      secondary: AppColors.turquoise,
      onSecondary: AppColors.night,
      error: AppColors.coral,
      onError: AppColors.night,
      surface: AppColors.nightSoft,
      onSurface: AppColors.cream,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.night,
      fontFamily: 'Rubik',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Secular One',
          fontSize: 44,
          height: 1.05,
          fontWeight: FontWeight.w700,
          color: AppColors.cream,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Secular One',
          fontSize: 32,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: AppColors.cream,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Secular One',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.cream,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.cream,
        ),
        bodyLarge: TextStyle(fontSize: 17, color: AppColors.cream),
        bodyMedium: TextStyle(fontSize: 15, color: AppColors.cream),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cream,
        hintStyle: const TextStyle(color: Color(0xFF777386)),
        counterStyle: const TextStyle(color: AppColors.muted),
        errorStyle: const TextStyle(
          color: AppColors.coral,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.nightSoft,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF4A4860), width: 1.5),
        ),
      ),
    );
  }
}

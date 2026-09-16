import 'package:flutter/material.dart';

abstract final class AppColors {
  static const night = Color(0xFF14132B);
  static const nightRaised = Color(0xFF201E39);
  static const nightSoft = Color(0xFF25233D);
  static const yellow = Color(0xFFFFD447);
  static const turquoise = Color(0xFF2DD4BF);
  static const coral = Color(0xFFFF6B6B);
  static const purple = Color(0xFF8B5CF6);
  static const cream = Color(0xFFFFF8E7);
  static const muted = Color(0xFFAAA7B4);
  static const border = Color(0xFF4A4860);
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
          fontWeight: FontWeight.w400, // the only weight Secular One has
          color: AppColors.cream,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Secular One',
          fontSize: 30,
          height: 1.13,
          fontWeight: FontWeight.w400,
          color: AppColors.cream,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Secular One',
          fontSize: 25,
          height: 1.15,
          fontWeight: FontWeight.w400,
          color: AppColors.cream,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Secular One',
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: AppColors.cream,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: AppColors.cream),
        bodyMedium:
            TextStyle(fontSize: 14, height: 1.5, color: AppColors.cream),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cream,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: const TextStyle(color: Color(0xFF777386)),
        counterStyle: const TextStyle(color: AppColors.muted),
        errorStyle: const TextStyle(
          color: Color(0xFFFFD9D9),
          fontWeight: FontWeight.w600,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.purple, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.coral, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.coral, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cream.withValues(alpha: .07),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.cream.withValues(alpha: .10)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.cream,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Secular One',
          fontSize: 26,
          color: AppColors.cream,
        ),
      ),
      dividerColor: AppColors.cream.withValues(alpha: .12),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.nightRaised,
        contentTextStyle: const TextStyle(
          color: AppColors.cream,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.cream,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          minimumSize: const Size(48, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.cream,
          backgroundColor: AppColors.cream.withValues(alpha: .10),
          minimumSize: const Size(46, 46),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.turquoise
              : AppColors.cream.withValues(alpha: .16),
        ),
        thumbColor: WidgetStatePropertyAll(AppColors.cream),
      ),
    );
  }
}

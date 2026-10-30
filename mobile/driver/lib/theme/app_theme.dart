import 'package:flutter/material.dart';

class AppColors {
  static const white = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF1F1F1);
  static const ink = Color(0xFF17281E);
  static const accent = Color(0xFFEA4227);
  static const muted = Color(0xFF68736C);
  static const mapRoad = Color(0xFFD7D9D8);
}

class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.white,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      surface: AppColors.white,
    ).copyWith(primary: AppColors.accent, onSurface: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.ink,
      surfaceTintColor: AppColors.white,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppColors.ink),
      bodyMedium: TextStyle(color: AppColors.ink),
      titleLarge: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
    ),
  );
}

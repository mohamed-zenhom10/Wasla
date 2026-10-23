import 'package:flutter/material.dart';

class AppColors {
  static const light = Color(0xFFF1F1F1);
  static const darkGreen = Color(0xFF17281E);
  static const accent = Color(0xFFEA4227);
  static const white = Colors.white;
}

class AppTheme {
  static final lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.white,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      surface: AppColors.white,
    ).copyWith(primary: AppColors.accent),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.darkGreen,
      surfaceTintColor: AppColors.white,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const light = Color(0xFFF1F1F1);
  static const darkGreen = Color(0xFF17281E);
  static const accent = Color(0xFFEA4227);
  static const white = Colors.white;
  static const gray = Color(0xFFA7A8AC);
  static const borderLight = Color(0xFFE4E6E3);
  static const success = Color(0xFFEAF4EC);
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const sm = 4.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const full = 16777200.0;
}

class AppShadows {
  static const card = BoxShadow(
    color: Color(0x1417281E),
    blurRadius: 16,
    offset: Offset(0, 4),
  );
  static const sheet = BoxShadow(
    color: Color(0x1417281E),
    blurRadius: 16,
    offset: Offset(0, 4),
  );
}

class AppTypography {
  static final TextStyle display = GoogleFonts.poppins(
    fontWeight: FontWeight.w700,
    fontSize: 36,
    height: 1.25,
    color: AppColors.darkGreen,
  );

  static final TextStyle headingLg = GoogleFonts.poppins(
    fontWeight: FontWeight.w700,
    fontSize: 32,
    height: 1.45,
    color: AppColors.darkGreen,
  );

  static final TextStyle headingMd = GoogleFonts.poppins(
    fontWeight: FontWeight.w700,
    fontSize: 26,
    height: 1.15,
    color: AppColors.darkGreen,
  );

  static final TextStyle headingSm = GoogleFonts.poppins(
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 1.45,
    color: AppColors.darkGreen,
  );

  static final TextStyle bodyLg = GoogleFonts.poppins(
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 1.45,
    color: AppColors.darkGreen,
  );

  static final TextStyle bodyMd = GoogleFonts.poppins(
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.45,
    color: AppColors.darkGreen,
  );

  static final TextStyle bodySm = GoogleFonts.poppins(
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.45,
    color: AppColors.darkGreen,
  );

  static final TextStyle bodyXs = GoogleFonts.poppins(
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 1.45,
    color: AppColors.darkGreen,
  );

  static final TextStyle labelMd = GoogleFonts.poppins(
    fontWeight: FontWeight.w500,
    fontSize: 12,
    color: AppColors.darkGreen,
  );

  static final TextStyle labelSm = GoogleFonts.poppins(
    fontWeight: FontWeight.w500,
    fontSize: 11,
    color: AppColors.darkGreen,
  );

  static final TextStyle labelXs = GoogleFonts.poppins(
    fontWeight: FontWeight.w500,
    fontSize: 10,
    color: AppColors.darkGreen,
  );

  static final TextStyle eyebrow = GoogleFonts.poppins(
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1,
    color: AppColors.darkGreen,
  );

  static final TextStyle buttonLabel = GoogleFonts.poppins(
    fontWeight: FontWeight.w500,
    fontSize: 15,
    color: AppColors.white,
  );

  static final TextStyle arabicBody = GoogleFonts.notoSansArabic(
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.45,
    color: AppColors.darkGreen,
  );
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
    textTheme: TextTheme(
      displayLarge: AppTypography.display,
      headlineMedium: AppTypography.headingLg,
      headlineSmall: AppTypography.headingMd,
      titleMedium: AppTypography.headingSm,
      bodyLarge: AppTypography.bodyLg,
      bodyMedium: AppTypography.bodyMd,
      bodySmall: AppTypography.bodySm,
      labelLarge: AppTypography.labelMd,
      labelMedium: AppTypography.labelSm,
      labelSmall: AppTypography.labelXs,
    ),
  );
}
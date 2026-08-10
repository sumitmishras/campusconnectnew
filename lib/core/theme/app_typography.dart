import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  /// Text theme for the given brightness. Built without a BuildContext so it
  /// can be composed directly inside [ThemeData].
  static TextTheme textTheme({required bool isDark}) {
    final Color textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final Color subtleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final base = isDark
        ? Typography.material2021().white
        : Typography.material2021().black;

    return GoogleFonts.interTextTheme(base).copyWith(
      displayLarge: GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: textColor,
        letterSpacing: -1,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: textColor,
        letterSpacing: -0.5,
      ),
      displaySmall: GoogleFonts.outfit(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: textColor,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: textColor,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: subtleColor,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    );
  }
}

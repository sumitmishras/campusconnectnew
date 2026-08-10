import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  static ThemeData get lightTheme => _build(isDark: false);
  static ThemeData get darkTheme => _build(isDark: true);

  static ThemeData _build({required bool isDark}) {
    final background =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final textTheme = AppTypography.textTheme(isDark: isDark);

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      dividerColor: textSecondary.withValues(alpha: 0.25),
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primaryLight,
        surface: surface,
        onSurface: textPrimary,
        error: AppColors.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.bodyMedium,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: textSecondary.withValues(alpha: 0.25),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: textTheme.titleMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: textSecondary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: AppColors.primary.withValues(alpha: 0.12),
        checkmarkColor: AppColors.primary,
        labelStyle: textTheme.bodyMedium,
        side: BorderSide(color: textSecondary.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        border: border(textSecondary.withValues(alpha: 0.2)),
        enabledBorder: border(textSecondary.withValues(alpha: 0.2)),
        focusedBorder: border(AppColors.primary, 2),
        errorBorder: border(AppColors.error),
        focusedErrorBorder: border(AppColors.error, 2),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary.withValues(alpha: 0.4)
              : null,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'attra_colors.dart';

/// Tema premium de Attra (claro y oscuro). Los NEUTROS (fondo/superficie/texto)
/// salen de [AttraColors] (cambian con el modo) y se registran como
/// ThemeExtension; los colores de MARCA (attraRed, coral, gold…) viven en
/// [AppColors] y son iguales en ambos modos. Las pantallas que usan
/// `Theme.of(context)` o `context.colors` se adaptan solas.
class AppTheme {
  const AppTheme._();

  static ThemeData get dark =>
      _build(AttraColors.dark, Brightness.dark, Typography.whiteMountainView);

  static ThemeData get light =>
      _build(AttraColors.light, Brightness.light, Typography.blackMountainView);

  static ThemeData _build(AttraColors c, Brightness brightness, TextTheme base) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.attraRed,
      onPrimary: Colors.white,
      secondary: AppColors.coral,
      onSecondary: brightness == Brightness.dark ? AppColors.black : Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceHigh,
      outline: c.surfaceLine,
      outlineVariant: c.surfaceLine,
      error: AppColors.danger,
      onError: Colors.white,
    );

    final TextTheme text = _textTheme(base, c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      textTheme: text,
      primaryColor: AppColors.attraRed,
      dividerColor: c.surfaceLine,
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[c],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: c.textPrimary,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: c.surfaceLine),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.attraRed,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.surfaceHigh,
          foregroundColor: c.textPrimary,
          elevation: 0,
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(64, 52),
          side: BorderSide(color: c.surfaceLine),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.attraRed,
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
      ),
      iconTheme: IconThemeData(color: c.textSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        hintStyle: TextStyle(color: c.textMuted),
        labelStyle: TextStyle(color: c.textSecondary),
        border: _inputBorder(c.surfaceLine),
        enabledBorder: _inputBorder(c.surfaceLine),
        focusedBorder: _inputBorder(AppColors.attraRed, width: 1.6),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceHigh,
        selectedColor: AppColors.attraRed,
        side: BorderSide(color: c.surfaceLine),
        labelStyle: TextStyle(color: c.textPrimary, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: c.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.attraRed.withValues(alpha: 0.16),
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? c.textPrimary
                : c.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.attraRed
                : c.textMuted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceHigh,
        contentTextStyle: TextStyle(color: c.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected)
                ? AppColors.attraRed
                : c.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected)
                ? AppColors.attraRed.withValues(alpha: 0.35)
                : c.surfaceHigh),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.attraRed,
      ),
      dividerTheme: DividerThemeData(
        color: c.surfaceLine,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(TextTheme base, AttraColors c) {
    TextStyle p(TextStyle? s, {Color? color}) =>
        (s ?? const TextStyle()).copyWith(color: color ?? c.textPrimary);
    return base.copyWith(
      displayLarge: p(base.displayLarge),
      displayMedium: p(base.displayMedium),
      headlineLarge:
          p(base.headlineLarge).copyWith(fontWeight: FontWeight.w800),
      headlineMedium:
          p(base.headlineMedium).copyWith(fontWeight: FontWeight.w800),
      headlineSmall:
          p(base.headlineSmall).copyWith(fontWeight: FontWeight.w700),
      titleLarge: p(base.titleLarge).copyWith(fontWeight: FontWeight.w700),
      titleMedium: p(base.titleMedium).copyWith(fontWeight: FontWeight.w600),
      titleSmall: p(base.titleSmall),
      bodyLarge: p(base.bodyLarge),
      bodyMedium: p(base.bodyMedium, color: c.textSecondary),
      bodySmall: p(base.bodySmall, color: c.textMuted),
      labelLarge: p(base.labelLarge).copyWith(fontWeight: FontWeight.w700),
    );
  }
}

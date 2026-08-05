import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'attra_colors.dart';

/// Tema editorial de Attra.
///
/// Blanco editorial en claro, tinta sobria en oscuro y un acento acromático.
/// El rojo queda reservado a errores y acciones destructivas.
class AppTheme {
  const AppTheme._();

  static ThemeData get dark =>
      _build(AttraColors.dark, Brightness.dark, Typography.whiteMountainView);

  static ThemeData get light =>
      _build(AttraColors.light, Brightness.light, Typography.blackMountainView);

  static ThemeData _build(
    AttraColors c,
    Brightness brightness,
    TextTheme base,
  ) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accentDeep,
      onSecondary: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceHigh,
      outline: c.surfaceLine,
      outlineVariant: c.surfaceLine,
      error: AppColors.danger,
      onError: Colors.white,
    );

    final TextTheme text = _textTheme(base, c);
    final BorderRadius controlRadius =
        BorderRadius.circular(AppSpacing.radiusMd);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      textTheme: text,
      primaryColor: c.accent,
      dividerColor: c.surfaceLine,
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[c],
      focusColor: c.accentSoft,
      hoverColor: c.accentSoft.withValues(alpha: 0.7),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
        foregroundColor: c.textPrimary,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 21,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
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
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.surfaceHigh,
          disabledForegroundColor: c.textMuted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.surfaceHigh,
          foregroundColor: c.textPrimary,
          disabledBackgroundColor: c.surfaceHigh.withValues(alpha: 0.6),
          disabledForegroundColor: c.textMuted,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          side: BorderSide(color: c.surfaceLine),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          side: BorderSide(color: c.surfaceLine),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
        ),
      ),
      iconTheme: IconThemeData(color: c.textSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(color: c.textMuted),
        labelStyle: TextStyle(color: c.textSecondary),
        floatingLabelStyle:
            TextStyle(color: c.accent, fontWeight: FontWeight.w600),
        border: _inputBorder(c.surfaceLine),
        enabledBorder: _inputBorder(c.surfaceLine),
        focusedBorder: _inputBorder(c.accent, width: 1.8),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.8),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceHigh,
        selectedColor: c.accentSoft,
        side: BorderSide(color: c.surfaceLine),
        labelStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: brightness == Brightness.dark ? c.accent : c.accentDeep,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: c.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            height: 1.1,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? c.textPrimary
                : c.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            size: 24,
            color:
                states.contains(WidgetState.selected) ? c.accent : c.textMuted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.surfaceLine,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: c.surfaceLine),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.textPrimary,
        contentTextStyle: TextStyle(color: c.bg),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? c.onAccent
              : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? c.accent : c.surfaceHigh,
        ),
        trackOutlineColor: WidgetStatePropertyAll<Color>(c.surfaceLine),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
      dividerTheme: DividerThemeData(
        color: c.surfaceLine,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.textPrimary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: TextStyle(color: c.bg, fontSize: 12),
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
    TextStyle withColor(TextStyle? style, Color color) =>
        (style ?? const TextStyle()).copyWith(color: color);

    return base.copyWith(
      displayLarge: withColor(base.displayLarge, c.textPrimary).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        height: 1.05,
      ),
      displayMedium: withColor(base.displayMedium, c.textPrimary).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        height: 1.08,
      ),
      headlineLarge: withColor(base.headlineLarge, c.textPrimary).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        height: 1.12,
      ),
      headlineMedium: withColor(base.headlineMedium, c.textPrimary).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.55,
        height: 1.16,
      ),
      headlineSmall: withColor(base.headlineSmall, c.textPrimary).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        height: 1.2,
      ),
      titleLarge: withColor(base.titleLarge, c.textPrimary).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: withColor(base.titleMedium, c.textPrimary).copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleSmall: withColor(base.titleSmall, c.textPrimary).copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge:
          withColor(base.bodyLarge, c.textPrimary).copyWith(height: 1.45),
      bodyMedium:
          withColor(base.bodyMedium, c.textSecondary).copyWith(height: 1.42),
      bodySmall: withColor(base.bodySmall, c.textMuted).copyWith(height: 1.35),
      labelLarge: withColor(base.labelLarge, c.textPrimary).copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: withColor(base.labelMedium, c.textSecondary).copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelSmall: withColor(base.labelSmall, c.textMuted).copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

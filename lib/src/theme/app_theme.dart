import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
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

  static ThemeData get dark => _build(AttraColors.dark, Brightness.dark);

  static ThemeData get light => _build(AttraColors.light, Brightness.light);

  static ThemeData _build(
    AttraColors c,
    Brightness brightness,
  ) {
    // Controls and reading text keep the platform font. Brand typography is
    // reserved for names, personal responses and content headings.
    final Typography typography =
        Typography.material2021(platform: defaultTargetPlatform);
    final TextTheme base =
        brightness == Brightness.dark ? typography.white : typography.black;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accentDeep,
      onSecondary: brightness == Brightness.dark ? c.bg : Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      primaryContainer: c.surfaceHigh,
      onPrimaryContainer: c.textPrimary,
      secondaryContainer: c.surfaceHigh,
      onSecondaryContainer: c.textPrimary,
      surfaceContainerLow: c.bg,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceHigh,
      surfaceContainerHighest: c.surfaceHigh,
      outline: c.surfaceLine,
      outlineVariant: c.surfaceLine,
      error: brightness == Brightness.dark
          ? AppColors.dangerOnDark
          : AppColors.dangerOnLight,
      onError: brightness == Brightness.dark ? c.bg : Colors.white,
    );

    final TextTheme text = _textTheme(base, c);
    final BorderRadius controlRadius =
        BorderRadius.circular(AppSpacing.radiusMd);
    final RoundedRectangleBorder actionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      textTheme: text,
      primaryColor: c.accent,
      dividerColor: c.surfaceLine,
      // InkSplash en vez del InkRipple de serie: un halo fijo que se
      // desvanece en el sitio, no un círculo que viaja desde el dedo hasta
      // cubrir todo el control. Es la firma visual más reconocible de un
      // Material por defecto sin pulir; aquí se nota en TODO lo que todavía
      // no lleva el escalado de AttraPressFeedback (ese además la apaga del
      // todo, ver attra_motion.dart) con un solo cambio, sin tocar pantalla
      // por pantalla.
      splashFactory: InkSplash.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[c],
      focusColor: c.accentSoft,
      hoverColor: c.accentSoft.withValues(alpha: 0.7),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: defaultTargetPlatform == TargetPlatform.iOS,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
                .copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark
                .copyWith(statusBarColor: Colors.transparent),
        foregroundColor: c.textPrimary,
        titleTextStyle: text.titleMedium,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
          shape: actionShape,
          textStyle: text.labelLarge,
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
          shape: actionShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          side: BorderSide(color: c.surfaceLine),
          shape: actionShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: text.labelLarge,
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
        side: BorderSide.none,
        labelStyle: text.labelMedium?.copyWith(
          color: c.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: text.labelMedium?.copyWith(
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
        constraints: const BoxConstraints(maxWidth: AppSpacing.readingWidth),
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.textMuted,
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
      tabBarTheme: TabBarThemeData(
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textMuted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicatorColor: c.accent,
        dividerColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: text.bodyLarge,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
      ),
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

    TextStyle display(TextStyle? style, double size) =>
        withColor(style, c.textPrimary).copyWith(
          fontFamily: 'Manrope',
          fontSize: size,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          height: 1.2,
        );

    return base.copyWith(
      displayLarge: display(base.displayLarge, 40),
      displayMedium: display(base.displayMedium, 32),
      displaySmall: display(base.displaySmall, 32),
      headlineLarge: display(base.headlineLarge, 32),
      headlineMedium: display(base.headlineMedium, 32),
      headlineSmall: display(base.headlineSmall, 24),
      titleLarge: display(base.titleLarge, 24),
      titleMedium: withColor(base.titleMedium, c.textPrimary).copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleSmall: withColor(base.titleSmall, c.textPrimary).copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      bodyLarge: withColor(base.bodyLarge, c.textPrimary).copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodyMedium: withColor(base.bodyMedium, c.textSecondary).copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodySmall: withColor(base.bodySmall, c.textMuted).copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: withColor(base.labelLarge, c.textPrimary).copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: withColor(base.labelMedium, c.textSecondary).copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: withColor(base.labelSmall, c.textMuted).copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

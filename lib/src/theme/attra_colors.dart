import 'package:flutter/material.dart';

/// Neutros y acento adaptativos de Attra.
///
/// Uso: `context.colors.bg`, `context.colors.surface`, etc. Se registra como
/// [ThemeExtension] en los temas claro y oscuro.
@immutable
class AttraColors extends ThemeExtension<AttraColors> {
  const AttraColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceLine,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentDeep,
    required this.accentSoft,
  });

  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceLine;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Acento neutral adaptado para conservar contraste en claro y oscuro.
  final Color accent;
  final Color accentDeep;
  final Color accentSoft;

  /// Color con mayor contraste para colocar sobre [accent].
  Color get onAccent {
    const Color ink = Color(0xFF171717);
    return _contrast(accent, Colors.white) >= _contrast(accent, ink)
        ? Colors.white
        : ink;
  }

  /// Paleta oscura sobria y acromática.
  static const AttraColors dark = AttraColors(
    bg: Color(0xFF111111),
    surface: Color(0xFF1D1D1D),
    surfaceHigh: Color(0xFF2A2A2A),
    surfaceLine: Color(0xFF404040),
    textPrimary: Color(0xFFFAFAFA),
    textSecondary: Color(0xFFC8C8C8),
    textMuted: Color(0xFF999999),
    accent: Color(0xFFF4F4F4),
    accentDeep: Color(0xFFB8B8B8),
    accentSoft: Color(0xFF303030),
  );

  /// Paleta clara: blanco, tinta y grises editoriales.
  static const AttraColors light = AttraColors(
    bg: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1F1F1),
    surfaceLine: Color(0xFFDEDEDE),
    textPrimary: Color(0xFF171717),
    textSecondary: Color(0xFF555555),
    textMuted: Color(0xFF777777),
    accent: Color(0xFF171717),
    accentDeep: Color(0xFF000000),
    accentSoft: Color(0xFFECECEC),
  );

  @override
  AttraColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceLine,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentDeep,
    Color? accentSoft,
  }) {
    return AttraColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceLine: surfaceLine ?? this.surfaceLine,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentSoft: accentSoft ?? this.accentSoft,
    );
  }

  @override
  AttraColors lerp(ThemeExtension<AttraColors>? other, double t) {
    if (other is! AttraColors) return this;
    return AttraColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      surfaceLine: Color.lerp(surfaceLine, other.surfaceLine, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }

  static double _contrast(Color a, Color b) {
    final double aLum = a.computeLuminance();
    final double bLum = b.computeLuminance();
    final double high = aLum > bLum ? aLum : bLum;
    final double low = aLum > bLum ? bLum : aLum;
    return (high + 0.05) / (low + 0.05);
  }
}

extension AttraColorsX on BuildContext {
  AttraColors get colors =>
      Theme.of(this).extension<AttraColors>() ?? AttraColors.dark;
}

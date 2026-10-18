import 'package:attra/src/theme/app_colors.dart';
import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/theme/attra_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('texto y controles conservan contraste en todas las superficies', () {
    for (final AttraColors colors in <AttraColors>[
      AttraColors.dark,
      AttraColors.light
    ]) {
      for (final Color foreground in <Color>[
        colors.textPrimary,
        colors.textSecondary,
        colors.textMuted
      ]) {
        for (final Color background in <Color>[
          colors.bg,
          colors.surface,
          colors.surfaceHigh
        ]) {
          expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
          _contrast(colors.onAccent, colors.accent), greaterThanOrEqualTo(4.5));
    }
  });

  test('los acentos y aliases de marca son acromaticos', () {
    final Map<String, Color> colors = <String, Color>{
      'dark.accent': AttraColors.dark.accent,
      'dark.accentDeep': AttraColors.dark.accentDeep,
      'dark.accentSoft': AttraColors.dark.accentSoft,
      'light.accent': AttraColors.light.accent,
      'light.accentDeep': AttraColors.light.accentDeep,
      'light.accentSoft': AttraColors.light.accentSoft,
      'AppColors.attraRed': AppColors.attraRed,
      'AppColors.attraRedDeep': AppColors.attraRedDeep,
      'AppColors.coral': AppColors.coral,
      'AppColors.wineRed': AppColors.wineRed,
      'AppColors.wine': AppColors.wine,
    };

    for (final MapEntry<String, Color> entry in colors.entries) {
      expect(
        _isAchromatic(entry.value),
        isTrue,
        reason: '${entry.key} debe pertenecer a la paleta carbon/gris',
      );
    }

    expect(AppColors.attraRed, AppColors.brandNeutral);
    expect(AppColors.attraRedDeep, AppColors.brandInk);
    expect(AppColors.coral, AppColors.brandSilver);
    expect(AppColors.wineRed, AppColors.brandGraphite);
    expect(AppColors.wine, AppColors.black);

    final Map<String, List<Color>> neutralGradients = <String, List<Color>>{
      'brandBackground': AppColors.brandBackground,
      'action': AppColors.action,
      'match': AppColors.match,
      'pro': AppColors.pro,
    };
    for (final MapEntry<String, List<Color>> entry
        in neutralGradients.entries) {
      expect(
        entry.value.every(_isAchromatic),
        isTrue,
        reason: '${entry.key} no debe recuperar un degradado rojo',
      );
    }
  });

  test('los temas usan primary neutral y reservan el rojo para danger', () {
    final Map<String, ({ThemeData theme, AttraColors colors})> themes =
        <String, ({ThemeData theme, AttraColors colors})>{
      'light': (theme: AppTheme.light, colors: AttraColors.light),
      'dark': (theme: AppTheme.dark, colors: AttraColors.dark),
    };

    for (final MapEntry<String, ({ThemeData theme, AttraColors colors})> entry
        in themes.entries) {
      final ThemeData theme = entry.value.theme;
      final AttraColors colors = entry.value.colors;
      expect(
          _contrast(theme.colorScheme.onSecondary, theme.colorScheme.secondary),
          greaterThanOrEqualTo(4.5));

      expect(
        theme.colorScheme.primary,
        colors.accent,
        reason: '${entry.key}.primary debe proceder del acento adaptativo',
      );
      expect(
        _isAchromatic(theme.colorScheme.primary),
        isTrue,
        reason: '${entry.key}.primary no debe recuperar un tinte rojo',
      );
      expect(theme.primaryColor, colors.accent);
      expect(
          theme.colorScheme.error,
          entry.key == 'dark'
              ? AppColors.dangerOnDark
              : AppColors.dangerOnLight);

      final InputBorder? errorBorder = theme.inputDecorationTheme.errorBorder;
      final InputBorder? focusedErrorBorder =
          theme.inputDecorationTheme.focusedErrorBorder;
      expect(errorBorder, isA<OutlineInputBorder>());
      expect(focusedErrorBorder, isA<OutlineInputBorder>());
      expect(
        (errorBorder! as OutlineInputBorder).borderSide.color,
        AppColors.danger,
      );
      expect(
        (focusedErrorBorder! as OutlineInputBorder).borderSide.color,
        AppColors.danger,
      );
    }

    expect(_isRedDominant(AppColors.danger), isTrue);
    expect(AppColors.danger, isNot(AppColors.attraRed));
    expect(AppColors.danger, isNot(AttraColors.light.accent));
    expect(AppColors.danger, isNot(AttraColors.dark.accent));
    expect(AppColors.loginVideoTint, const Color(0xFFB4375D));
  });

  test('el error y su foreground mantienen contraste AA en ambos temas', () {
    for (final ThemeData theme in <ThemeData>[AppTheme.dark, AppTheme.light]) {
      final AttraColors colors = theme.extension<AttraColors>()!;
      for (final Color background in <Color>[
        colors.bg,
        colors.surface,
        colors.surfaceHigh,
      ]) {
        expect(_contrast(theme.colorScheme.error, background),
            greaterThanOrEqualTo(4.5));
      }
      expect(_contrast(theme.colorScheme.onError, theme.colorScheme.error),
          greaterThanOrEqualTo(4.5));
    }
  });
}

double _contrast(Color a, Color b) {
  final double first = a.computeLuminance();
  final double second = b.computeLuminance();
  final double high = first > second ? first : second;
  final double low = first > second ? second : first;
  return (high + 0.05) / (low + 0.05);
}

bool _isAchromatic(Color color) {
  final int value = color.toARGB32();
  final int red = (value >> 16) & 0xFF;
  final int green = (value >> 8) & 0xFF;
  final int blue = value & 0xFF;
  return red == green && green == blue;
}

bool _isRedDominant(Color color) {
  final int value = color.toARGB32();
  final int red = (value >> 16) & 0xFF;
  final int green = (value >> 8) & 0xFF;
  final int blue = value & 0xFF;
  return red >= green + 32 && red >= blue + 24;
}

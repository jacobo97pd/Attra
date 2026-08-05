import 'package:flutter/material.dart';

import '../../core/config/legal_links.dart';

/// Fila de enlaces legales FUNCIONALES (EULA + privacidad).
///
/// Se usa en el login (antes de registrarse) y en el paywall de suscripciones,
/// donde App Store exige enlaces que abran realmente los documentos
/// (Guidelines 1.2 y 3.1.2(c)). Si el dispositivo no puede abrir el enlace se
/// avisa con un SnackBar en lugar de fallar en silencio.
class AttraLegalLinksRow extends StatelessWidget {
  const AttraLegalLinksRow({
    super.key,
    this.color,
    this.fontSize = 12.5,
    this.alignment = WrapAlignment.center,
    this.showChildSafety = false,
  });

  /// Color del texto. Por defecto, el color de acento del tema.
  final Color? color;
  final double fontSize;
  final WrapAlignment alignment;

  /// Añade el enlace a los estándares de seguridad infantil.
  final bool showChildSafety;

  static Future<void> openOrWarn(BuildContext context, String url) async {
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    final bool opened = await LegalLinks.open(url);
    if (opened || messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo abrir el enlace: $url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color linkColor = color ?? Theme.of(context).colorScheme.primary;
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: <Widget>[
        _LegalLink(
          key: const ValueKey<String>('legal-link-terms'),
          label: 'Condiciones de uso (EULA)',
          url: LegalLinks.termsUrl,
          color: linkColor,
          fontSize: fontSize,
        ),
        _Separator(color: linkColor, fontSize: fontSize),
        _LegalLink(
          key: const ValueKey<String>('legal-link-privacy'),
          label: 'Política de privacidad',
          url: LegalLinks.privacyUrl,
          color: linkColor,
          fontSize: fontSize,
        ),
        if (showChildSafety) ...<Widget>[
          _Separator(color: linkColor, fontSize: fontSize),
          _LegalLink(
            key: const ValueKey<String>('legal-link-child-safety'),
            label: 'Seguridad infantil',
            url: LegalLinks.childSafetyUrl,
            color: linkColor,
            fontSize: fontSize,
          ),
        ],
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color, required this.fontSize});

  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      '·',
      style: TextStyle(
        color: color.withValues(alpha: 0.7),
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    super.key,
    required this.label,
    required this.url,
    required this.color,
    required this.fontSize,
  });

  final String label;
  final String url;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => AttraLegalLinksRow.openOrWarn(context, url),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              height: 1.35,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

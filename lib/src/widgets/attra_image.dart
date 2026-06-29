import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/attra_colors.dart';

/// Imagen de red con CACHÉ EN DISCO + memoria, downscaling y transición suave.
///
/// Sustituye a `Image.network` en toda la app para que las fotos no se
/// re-descarguen al hacer scroll o al reentrar en una pantalla. Mantiene la
/// misma semántica de `BoxFit.cover` por defecto y un placeholder/fallback
/// coherente con el tema oscuro.
class AttraImage extends StatelessWidget {
  const AttraImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallbackInitial,
    this.borderRadius,
    this.memCacheWidth,
  });

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Inicial a mostrar si no hay imagen o falla la carga.
  final String? fallbackInitial;

  /// Si se indica, recorta la imagen (y el placeholder/fallback) con este radio.
  final BorderRadius? borderRadius;

  /// Ancho máximo en píxeles para decodificar en memoria (downscaling). Si es
  /// null se usa una estimación razonable según el ancho lógico del widget.
  final int? memCacheWidth;

  /// Precalienta la caché (disco + memoria) de [url] para que aparezca al
  /// instante cuando se muestre. Best-effort: ignora errores de red.
  static Future<void> precache(BuildContext context, String? url) {
    final String clean = (url ?? '').trim();
    if (clean.isEmpty) return Future<void>.value();
    return precacheImage(CachedNetworkImageProvider(clean), context)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final String clean = (url ?? '').trim();
    Widget child;
    if (clean.isEmpty) {
      child = _fallback(context);
    } else {
      final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
      final int? decodeWidth = memCacheWidth ??
          (width != null && width!.isFinite ? (width! * dpr).round() : null);
      child = CachedNetworkImage(
        imageUrl: clean,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: decodeWidth,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 120),
        placeholder: (BuildContext ctx, __) => _placeholder(ctx),
        errorWidget: (BuildContext ctx, __, ___) => _fallback(ctx),
      );
    }
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: context.colors.surfaceHigh,
    );
  }

  Widget _fallback(BuildContext context) {
    final String initial = (fallbackInitial ?? '').trim();
    return Container(
      width: width,
      height: height,
      color: context.colors.surfaceHigh,
      alignment: Alignment.center,
      child: initial.isEmpty
          ? Icon(Icons.person_rounded,
              color: context.colors.textMuted, size: 40)
          : Text(
              initial[0].toUpperCase(),
              style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 40,
                  fontWeight: FontWeight.w700),
            ),
    );
  }
}

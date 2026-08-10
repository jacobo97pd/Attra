import 'package:flutter/material.dart';

import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_image.dart';
import '../domain/story.dart';

/// Hojas que se pintan DETRÁS de la portada de la pila.
///
/// 1 historia = 0 hojas (la tarjeta se ve plana); 5 historias = 4 hojas (pila
/// claramente visible). El tope es [StoryStackCard.maxSheets] porque el backend
/// no admite más de 5 historias vivas por persona (MAX_ACTIVE_STORIES en
/// functions/src/stories.ts): sin tope, un dato corrupto pintaría una escalera.
int storyStackSheets(int liveStories) {
  if (liveStories <= 1) return 0;
  final int sheets = liveStories - 1;
  return sheets > StoryStackCard.maxSheets ? StoryStackCard.maxSheets : sheets;
}

/// Qué historia pone la CARA de la pila.
///
/// Antes era `stories.first` y el grupo llega ordenado de más antigua a más
/// reciente (`StoryRepository.groupWallStories`), así que la portada era siempre
/// la MÁS VIEJA. Dos motivos para darle la vuelta:
///
/// 1. El muro va de lo que la gente está contando AHORA. Con tres historias
///    vivas, la cara tiene que ser la última publicada, no la de hace dos días
///    a punto de caducar (y es lo que espera quien acaba de publicar: ve su
///    pila y no reconoce lo que sale).
/// 2. La portada no puede depender de una posición: en un vídeo `previewUrl` es
///    la MINIATURA, y generarla es best-effort (`VideoCompress.getByteThumbnail`
///    va en su propio try en story_service.dart, y en web no se genera nunca).
///    Con la miniatura fallida la tarjeta caía al recuadro con la inicial del
///    nombre teniendo, ahí mismo y sin usar, dos fotos perfectamente válidas.
///
/// El orden ENTRE personas no se toca: eso lo decide el pipeline del feed
/// (ranking orgánico, Boost PAGADO, modo viaje). Esto es solo qué se pinta
/// dentro de la tarjeta.
Story storyStackCover(List<Story> stories) {
  for (int i = stories.length - 1; i >= 0; i--) {
    if (storyCoverUrl(stories[i]).isNotEmpty) return stories[i];
  }
  // Ninguna tiene vista previa utilizable: da igual cuál, se pintará el
  // recuadro con la inicial. Se devuelve la más reciente por coherencia.
  return stories.last;
}

/// Lo que se puede pintar de una historia sin abrirla: la miniatura del vídeo o
/// la propia foto. `imageUrl` se mantiene como último recurso para un documento
/// que traiga foto y marca de vídeo a la vez.
String storyCoverUrl(Story story) =>
    story.previewUrl.isNotEmpty ? story.previewUrl : story.imageUrl;

/// Dónde va la hoja [index] (1 = la pegada a la portada) de una pila de
/// [sheets] hojas: inserción en píxeles desde cada borde de la tarjeta.
///
/// El borde INFERIOR se escalona al revés que los otros tres. Con todas las
/// hojas llegando al fondo, cada una quedaba íntegramente dentro de la de
/// delante —que se pinta después y es opaca—, así que solo asomaba UNA banda:
/// 2, 3, 4 y 5 historias se veían igual y lo único que cambiaba era el grosor de
/// esa banda única.
EdgeInsets storyStackSheetInsets({required int index, required int sheets}) {
  const double step = StoryStackCard.sheetStep;
  return EdgeInsets.fromLTRB(
    index * step,
    index * step,
    index * step,
    (sheets - index) * step,
  );
}

/// Tarjeta del muro de Discover: una PILA cuyo grosor depende del NÚMERO de
/// historias vivas de esa persona.
///
/// El grosor es SOLO visual. No reordena nada: el orden del muro lo pone el
/// pipeline del feed (filtros, ranking, Boost pagado, viaje, Slow Dating). Si la
/// pila reordenara, quien ha PAGADO un Boost lo perdería frente a quien
/// simplemente publica más.
///
/// De la persona solo se enseña NOMBRE y EDAD: el resto es la recompensa del
/// match.
class StoryStackCard extends StatelessWidget {
  const StoryStackCard({
    super.key,
    required this.stories,
    required this.displayName,
    required this.age,
    required this.onTap,
    this.likedMe = false,
    this.allSeen = false,
  });

  /// Máximo de hojas dibujadas (5 historias = portada + 4 hojas).
  static const int maxSheets = 4;

  /// Separación entre hojas. Lo justo para que 4 hojas se distingan sin comerse
  /// la portada en pantallas pequeñas.
  static const double sheetStep = 9;

  final List<Story> stories;
  final String displayName;
  final int? age;
  final VoidCallback onTap;

  /// Realce de "te dio like" (Plus/Pro). Es la misma señal que en la tarjeta de
  /// perfil: no dice nada de la persona, solo de su interés.
  final bool likedMe;

  /// Todas sus historias ya vistas en esta sesión: la portada se atenúa.
  final bool allSeen;

  String get _label {
    final int? a = age;
    if (a == null || a <= 0) return displayName;
    return '$displayName, $a';
  }

  @override
  Widget build(BuildContext context) {
    final AttraColors colors = context.colors;
    final int sheets = storyStackSheets(stories.length);
    final double stackDepth = sheets * sheetStep;

    return Stack(
      children: <Widget>[
        // Hojas de atrás hacia delante: asoman por abajo y son más estrechas,
        // que es como se lee "aquí hay más". La colocación vive en
        // [storyStackSheetInsets] para poder fijarla con un test.
        for (int i = sheets; i >= 1; i--) _sheet(colors, i, sheets),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: stackDepth,
          child: _cover(context, colors, sheets),
        ),
      ],
    );
  }

  /// Una hoja de la pila. Va vacía a propósito: ver [_cover].
  Widget _sheet(AttraColors colors, int index, int sheets) {
    final EdgeInsets insets =
        storyStackSheetInsets(index: index, sheets: sheets);
    return Positioned(
      left: insets.left,
      right: insets.right,
      top: insets.top,
      bottom: insets.bottom,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(
            colors.surfaceHigh,
            colors.bg,
            index / (maxSheets + 1),
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.surfaceLine, width: 1),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, AttraColors colors, int sheets) {
    // Las hojas de atrás son chapa: no llevan imagen a propósito. Asoman 9 px,
    // y meter ahí la vista previa de cada historia serían hasta cuatro
    // descargas y decodificaciones más por tarjeta —en la pantalla que se
    // recorre a swipes— para una banda que no se distingue. Que hay más
    // historias lo dicen el grosor de la pila y la pastilla del contador, y
    // verlas todas es lo que hace el visor al tocar.
    final Story cover = storyStackCover(stories);
    final String url = storyCoverUrl(cover);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: likedMe ? Border.all(color: colors.accent, width: 2) : null,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Material(
          color: colors.surface,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Opacity(
                  opacity: allSeen ? 0.72 : 1,
                  child: AttraImage(
                    url: url,
                    fit: BoxFit.cover,
                    fallbackInitial: displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                  ),
                ),
                // Degradado inferior: el nombre tiene que leerse sobre
                // cualquier foto sin taparla.
                const _BottomScrim(),
                Positioned(
                  top: 14,
                  left: 14,
                  child: _StoryCountPill(
                    count: stories.length,
                    sheets: sheets,
                    dimmed: allSeen,
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 22,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          shadows: <Shadow>[
                            Shadow(blurRadius: 10, color: Colors.black87),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Toca para verle a ciegas',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          shadows: const <Shadow>[
                            Shadow(blurRadius: 8, color: Colors.black87),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastilla con el número de historias. Repite en texto lo que dice el grosor
/// de la pila: el grosor solo no es accesible (lector de pantalla, daltonismo).
class _StoryCountPill extends StatelessWidget {
  const _StoryCountPill({
    required this.count,
    required this.sheets,
    required this.dimmed,
  });

  final int count;
  final int sheets;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final String text = count == 1 ? '1 historia' : '$count historias';
    return Semantics(
      label: sheets == 0 ? text : '$text (pila)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: dimmed ? 0.35 : 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_stories_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: dimmed ? 0.7 : 1),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: dimmed ? 0.7 : 1),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.72),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

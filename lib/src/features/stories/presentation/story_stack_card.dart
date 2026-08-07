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
  static const double _sheetStep = 9;

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
    final double stackDepth = sheets * _sheetStep;

    return Stack(
      children: <Widget>[
        // Hojas de atrás hacia delante: asoman por abajo y son más estrechas,
        // que es como se lee "aquí hay más".
        for (int i = sheets; i >= 1; i--)
          Positioned(
            left: i * _sheetStep,
            right: i * _sheetStep,
            top: i * _sheetStep,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(
                  colors.surfaceHigh,
                  colors.bg,
                  i / (maxSheets + 1),
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: colors.surfaceLine, width: 1),
              ),
            ),
          ),
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

  Widget _cover(BuildContext context, AttraColors colors, int sheets) {
    final Story cover = stories.first;
    final String url =
        cover.previewUrl.isNotEmpty ? cover.previewUrl : cover.imageUrl;
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

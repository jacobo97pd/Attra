import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_buttons.dart';
import 'demo_challenge_screen.dart';
import 'lab_widgets.dart';

/// Hub "Juegos": catálogo de los juegos de conversación de Attra + el Reto Demo
/// jugable sin match.
///
/// Qué fallaba: esta pantalla existía pero NINGÚN sitio la abría (la entrada se
/// perdió al reordenar la navegación), así que los juegos parecían no existir.
/// Ahora se abre desde Chats (cabecera y estado vacío) y desde el menú de juegos
/// de cualquier chat, y cada tarjeta explica DÓNDE se juega en vez de ser un
/// listado decorativo sin acción.
class ConversationGamesScreen extends StatelessWidget {
  const ConversationGamesScreen({
    super.key,
    this.onDiscover,
    this.onOpenChats,
  });

  /// Abre el feed de descubrimiento para encontrar con quién jugar.
  final VoidCallback? onDiscover;

  /// Vuelve a la lista de chats (los juegos reales se lanzan dentro de un chat).
  final VoidCallback? onOpenChats;

  static const List<_Game> _games = <_Game>[
    _Game(
      icon: Icons.psychology_alt_rounded,
      title: 'Romper el hielo',
      body:
          'Aperturas guiadas por IA para arrancar una conversación de verdad.',
      where: 'Botón 🎮 del chat · "Pregunta rápida"',
      accent: AppColors.aiViolet,
    ),
    _Game(
      icon: Icons.emoji_events_rounded,
      title: 'Duelo de Química · 5 min',
      body:
          'Retáis a hablar 5 minutos y la IA dicta el resultado: química, mejor '
          'momento y plan sugerido.',
      where: 'Botón 🎮 del chat · "Duelo de Química"',
      accent: AppColors.attraRed,
    ),
    _Game(
      icon: Icons.compare_arrows_rounded,
      title: 'Esto o aquello',
      body: 'Rondas rápidas de elegir una opción para ver vuestro rollo.',
      where: 'Botón 🎮 del chat · "Esto o aquello"',
      accent: AppColors.gold,
    ),
    _Game(
      icon: Icons.workspace_premium_rounded,
      title: 'Dos verdades y una mentira',
      body: 'Escribes tres frases y tu match adivina cuál es la mentira.',
      where: 'Botón 🎮 del chat · límite diario en el plan Free',
      accent: AppColors.success,
    ),
    _Game(
      icon: Icons.question_answer_rounded,
      title: 'Doble respuesta',
      body:
          'Los dos respondéis a la misma pregunta a ciegas y se revela a la vez.',
      where: 'Botón 🎮 del chat · límite diario en el plan Free',
      accent: AppColors.nightBlue,
    ),
    _Game(
      icon: Icons.local_fire_department_rounded,
      title: 'Attra Spark',
      body: 'Partida en vivo de 5 minutos justo después de hacer match.',
      where: 'Pantalla de match, Likes recibidos y botón 🎮 del chat',
      accent: AppColors.coral,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(title: const Text('Juegos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const LabAiChip(label: 'Juegos de conversación'),
          const SizedBox(height: 12),
          Text('Juegos que convierten un match en una conversación',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Attra va de jugar y hablar, no solo de deslizar. Prueba un reto '
            'guiado ahora mismo, sin necesidad de match.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 16),
          // Pruébalo ya.
          LabCard(
            accent: AppColors.aiViolet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome, color: AppColors.aiViolet),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Prueba el Reto Demo',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Vive el flujo de conversación guiada por IA de principio a '
                  'fin, ahora mismo.',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
                const SizedBox(height: 12),
                AttraPrimaryButton(
                  label: 'Empezar Reto Demo',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DemoChallengeScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Todos los juegos de conversación',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Se lanzan desde el botón 🎮 dentro de cualquier chat con un match.',
            style:
                TextStyle(color: context.colors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          ..._games.map((_Game g) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LabCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: g.accent.withValues(alpha: 0.18),
                        ),
                        child: Icon(g.icon, color: g.accent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(g.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(g.body,
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 12.5,
                                    height: 1.3)),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(Icons.place_rounded,
                                    size: 13, color: g.accent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(g.where,
                                      style: TextStyle(
                                          color: g.accent,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          height: 1.25)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 6),
          if (onOpenChats != null) ...<Widget>[
            AttraPrimaryButton(
              label: 'Ir a mis chats y jugar',
              icon: Icons.forum_rounded,
              onPressed: onOpenChats,
            ),
            const SizedBox(height: 10),
          ],
          if (onDiscover != null)
            AttraGhostButton(
              label: 'Buscar con quién jugar',
              onPressed: onDiscover,
            ),
        ],
      ),
    );
  }
}

class _Game {
  const _Game({
    required this.icon,
    required this.title,
    required this.body,
    required this.where,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;

  /// Desde dónde se lanza este juego (evita que el listado sea decorativo).
  final String where;
  final Color accent;
}

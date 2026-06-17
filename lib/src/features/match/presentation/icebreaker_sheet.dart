import 'dart:math';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Catálogo LOCAL de icebreakers (Fase 3). Aperturas seguras, ligeras y
/// humanas (sin temas sensibles). Extensible; pensado para migrar a remoto.
class IcebreakerCatalog {
  const IcebreakerCatalog._();

  /// Preguntas rápidas para abrir conversación.
  static const List<String> quickQuestions = <String>[
    '¿Plan perfecto de domingo?',
    '¿Qué fue lo último que te hizo reír de verdad?',
    '¿Café, paseo o algo de picar para una primera quedada?',
    '¿Qué canción pondrías ahora mismo?',
    '¿Eres más de planear o de improvisar?',
    '¿Qué te hace sentir cómodo/a en una primera cita?',
    '¿Mar o montaña para desconectar?',
    '¿Qué serie o peli puedes ver mil veces?',
  ];

  /// "Esto o aquello" como apertura (una sola línea).
  static const List<String> thisOrThat = <String>[
    'Esto o aquello: ¿playa o montaña? 🏖️⛰️',
    'Esto o aquello: ¿café o copa? ☕🍷',
    'Esto o aquello: ¿plan tranquilo o improvisado? 🛋️✨',
    'Esto o aquello: ¿madrugar o trasnochar? 🌅🌙',
    'Esto o aquello: ¿museo o concierto? 🖼️🎶',
    'Esto o aquello: ¿perro o gato? 🐶🐱',
  ];

  /// Plantilla para "Dos verdades y una mentira".
  static const String twoTruthsTemplate =
      'Dos verdades y una mentira sobre mí:\n1. \n2. \n3. \n¿Cuál crees que es la mentira?';

  static String randomQuick([Random? rng]) =>
      quickQuestions[(rng ?? Random()).nextInt(quickQuestions.length)];

  static String randomThisOrThat([Random? rng]) =>
      thisOrThat[(rng ?? Random()).nextInt(thisOrThat.length)];
}

/// Opciones del icebreaker. 1-3 PREFILLAN el input del chat (el usuario confirma
/// y envía: nunca enviamos por él). 4-5 disparan acciones (plan / Spark).
Future<void> showIcebreakerSheet(
  BuildContext context, {
  required void Function(String starter) onPrefill,
  VoidCallback? onProposePlan,
  VoidCallback? onSpark,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      Widget tile(IconData icon, String title, String sub, VoidCallback onTap) {
        return ListTile(
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          },
          leading: CircleAvatar(
            backgroundColor: AppColors.attraRed.withValues(alpha: 0.16),
            child: Icon(icon, color: AppColors.attraRed, size: 20),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: theme.textTheme.bodySmall),
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 12),
            Text('Romped el hielo',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Elige una apertura. Podrás editarla antes de enviar.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            tile(Icons.bolt_rounded, 'Pregunta rápida',
                'Una pregunta para empezar',
                () => onPrefill(IcebreakerCatalog.randomQuick())),
            tile(Icons.swap_horiz_rounded, 'Esto o aquello',
                'Una elección divertida',
                () => onPrefill(IcebreakerCatalog.randomThisOrThat())),
            tile(Icons.psychology_alt_rounded, 'Dos verdades y una mentira',
                'A ver si lo adivina',
                () => onPrefill(IcebreakerCatalog.twoTruthsTemplate)),
            if (onProposePlan != null)
              tile(Icons.calendar_today_rounded, 'Crear un plan juntos',
                  'Proponed una cita', onProposePlan),
            if (onSpark != null)
              tile(Icons.local_fire_department_rounded, 'Attra Spark',
                  'El juego de 5 minutos', onSpark),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      );
    },
  );
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Catalogo local de aperturas. El usuario siempre revisa antes de enviar.
class IcebreakerCatalog {
  const IcebreakerCatalog._();

  static const List<String> quickQuestions = <String>[
    'Plan perfecto de domingo?',
    'Que fue lo ultimo que te hizo reir de verdad?',
    'Cafe, paseo o algo de picar para una primera quedada?',
    'Que cancion pondrias ahora mismo?',
    'Eres mas de planear o de improvisar?',
    'Que te hace sentir comodo/a en una primera cita?',
    'Mar o montana para desconectar?',
    'Que serie o peli puedes ver mil veces?',
  ];

  static const List<String> thisOrThat = <String>[
    'Esto o aquello: playa o montana?',
    'Esto o aquello: cafe o copa?',
    'Esto o aquello: plan tranquilo o improvisado?',
    'Esto o aquello: madrugar o trasnochar?',
    'Esto o aquello: museo o concierto?',
  ];

  static const String twoTruthsTemplate =
      'Dos verdades y una mentira sobre mi:\n1. \n2. \n3. \nCual crees que es la mentira?';

  static const List<String> doubleAnswerQuestions = <String>[
    'Que plan te apetece mas para una primera quedada?',
    'Que detalle hace que una conversacion te enganche?',
    'Cual seria una escapada perfecta de fin de semana?',
    'Que cancion pondrias para empezar bien la noche?',
    'Que te da mas confianza al conocer a alguien?',
  ];

  static String randomQuick([Random? rng]) =>
      quickQuestions[(rng ?? Random()).nextInt(quickQuestions.length)];

  static String randomThisOrThat([Random? rng]) =>
      thisOrThat[(rng ?? Random()).nextInt(thisOrThat.length)];

  static String randomDoubleAnswer([Random? rng]) => doubleAnswerQuestions[
      (rng ?? Random()).nextInt(doubleAnswerQuestions.length)];
}

Future<void> showIcebreakerSheet(
  BuildContext context, {
  required void Function(String starter) onPrefill,
  VoidCallback? onProposePlan,
  VoidCallback? onSpark,
  VoidCallback? onDoubleAnswer,
  VoidCallback? onTwoTruths,
  bool showQuickQuestion = true,
  bool showThisOrThat = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: theme.textTheme.bodySmall),
        );
      }

      final MediaQueryData media = MediaQuery.of(context);
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: AppSpacing.md + media.viewPadding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Romped el hielo',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Elige una apertura. Podras editarla antes de enviar.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 8),
                if (showQuickQuestion)
                  tile(
                      Icons.bolt_rounded,
                      'Pregunta rapida',
                      'Una pregunta para empezar',
                      () => onPrefill(IcebreakerCatalog.randomQuick())),
                if (showThisOrThat)
                  tile(
                      Icons.swap_horiz_rounded,
                      'Esto o aquello',
                      'Una eleccion ligera',
                      () => onPrefill(IcebreakerCatalog.randomThisOrThat())),
                if (onDoubleAnswer != null)
                  tile(Icons.question_answer_rounded, 'Doble respuesta',
                      'Responded sin veros hasta el reveal', onDoubleAnswer),
                if (onTwoTruths != null)
                  tile(
                      Icons.psychology_alt_rounded,
                      'Dos verdades y una mentira',
                      'Crea el juego con respuesta oculta',
                      onTwoTruths)
                else
                  tile(
                      Icons.psychology_alt_rounded,
                      'Dos verdades y una mentira',
                      'Plantilla editable',
                      () => onPrefill(IcebreakerCatalog.twoTruthsTemplate)),
                if (onProposePlan != null)
                  tile(Icons.calendar_today_rounded, 'Crear un plan juntos',
                      'Proponed una cita', onProposePlan),
                if (onSpark != null)
                  tile(Icons.local_fire_department_rounded, 'Attra Spark',
                      'El juego de 5 minutos', onSpark),
              ],
            ),
          ),
        ),
      );
    },
  );
}

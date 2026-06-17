import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../domain/spark_summary.dart';

/// Hoja de resumen al terminar Attra Spark: coincidencias, diferencias
/// divertidas, temas y 1-2 preguntas sugeridas para abrir conversación.
///
/// Las preguntas NO se envían solas: se copian / se pasan al input del chat
/// mediante [onUseQuestion] para que el usuario confirme antes de mandarlas.
Future<void> showSparkSummarySheet(
  BuildContext context, {
  required Map<String, dynamic> summary,
  required VoidCallback onOpenChat,
  void Function(String question)? onUseQuestion,
}) {
  final SparkSummary s = SparkSummary.fromMap(summary);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext context) => _SparkSummaryBody(
      summary: s,
      onOpenChat: onOpenChat,
      onUseQuestion: onUseQuestion,
    ),
  );
}

class _SparkSummaryBody extends StatelessWidget {
  const _SparkSummaryBody({
    required this.summary,
    required this.onOpenChat,
    this.onUseQuestion,
  });

  final SparkSummary summary;
  final VoidCallback onOpenChat;
  final void Function(String question)? onUseQuestion;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Icon(Icons.celebration_rounded,
                color: AppColors.attraRed, size: 40),
            const SizedBox(height: 8),
            Text('¡Habéis completado Attra Spark!',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(summary.chatLine,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 18),

            if (summary.coincidences.isNotEmpty)
              _section(
                theme,
                icon: Icons.favorite_rounded,
                title: 'Coincidencias',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: summary.coincidences
                      .map((String c) => _chip(c, AppColors.attraRed))
                      .toList(growable: false),
                ),
              ),

            if (summary.funnyDifferences.isNotEmpty)
              _section(
                theme,
                icon: Icons.sentiment_satisfied_rounded,
                title: 'Diferencias con gracia',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: summary.funnyDifferences
                      .map((String d) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• $d',
                                style: theme.textTheme.bodyMedium),
                          ))
                      .toList(growable: false),
                ),
              ),

            if (summary.suggestedQuestions.isNotEmpty)
              _section(
                theme,
                icon: Icons.tips_and_updates_rounded,
                title: 'Para empezar a hablar',
                child: Column(
                  children: summary.suggestedQuestions
                      .map((String q) => _QuestionTile(
                            question: q,
                            onUse: () {
                              onUseQuestion?.call(q);
                              Clipboard.setData(ClipboardData(text: q));
                              Navigator.of(context).pop();
                              onOpenChat();
                            },
                          ))
                      .toList(growable: false),
                ),
              ),

            const SizedBox(height: 16),
            AttraPrimaryButton(
              label: 'Abrir chat',
              icon: Icons.chat_bubble_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                onOpenChat();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme,
      {required IconData icon, required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: AppColors.attraRed),
              const SizedBox(width: 6),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.question, required this.onUse});

  final String question;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(question,
                style: const TextStyle(color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: onUse,
            child: const Text('Usar'),
          ),
        ],
      ),
    );
  }
}

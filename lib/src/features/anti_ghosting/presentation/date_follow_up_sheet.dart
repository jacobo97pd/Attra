import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

/// Respuesta al follow-up post-cita (Attra Clear §6). El `wire` coincide con el
/// backend `answerDateFollowUp`.
enum DateFollowUpAnswer {
  keepTalking('keep_talking', 'Quiero seguir hablando'),
  noConnection('no_connection', 'No hubo conexión'),
  preferEnd('prefer_end', 'Prefiero dejarlo aquí'),
  uncomfortable('uncomfortable', 'Me sentí incómodo/a'),
  report('report', 'Reportar');

  const DateFollowUpAnswer(this.wire, this.label);
  final String wire;
  final String label;
}

/// Bottom sheet "¿Cómo fue la cita?" tras una cita aceptada (Attra Clear §6).
class DateFollowUpSheet extends StatelessWidget {
  const DateFollowUpSheet({super.key});

  static Future<DateFollowUpAnswer?> show(BuildContext context) {
    return showModalBottomSheet<DateFollowUpAnswer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DateFollowUpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceLine,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text('¿Cómo fue la cita?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              for (final DateFollowUpAnswer a in DateFollowUpAnswer.values)
                _Option(
                  answer: a,
                  onTap: () => Navigator.of(context).pop(a),
                ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.answer, required this.onTap});
  final DateFollowUpAnswer answer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool danger = answer == DateFollowUpAnswer.uncomfortable ||
        answer == DateFollowUpAnswer.report;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.colors.surfaceLine),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(answer.label,
                      style: TextStyle(
                        color: danger
                            ? AppColors.coral
                            : context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      )),
                ),
                Icon(Icons.chevron_right,
                    color: context.colors.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

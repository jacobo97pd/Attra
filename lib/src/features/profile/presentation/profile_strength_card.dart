import 'package:flutter/material.dart';

import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_editorial.dart';

/// Tarjeta de "fuerza del perfil": muestra el score de completitud y anima a
/// completar (gratis). No penaliza por campos sensibles (los calcula el
/// ProfileCompletionCalculator, que no los pondera).
class ProfileStrengthCard extends StatelessWidget {
  const ProfileStrengthCard({
    super.key,
    required this.percent,
    required this.onEdit,
    this.pendingTasks = const <String>[],
  });

  final int percent;
  final VoidCallback onEdit;

  /// Todas las tareas pendientes, con el mismo criterio de completitud.
  final List<String> pendingTasks;

  String get _label {
    if (percent >= 90) return 'Excelente';
    if (percent >= 70) return 'Muy bueno';
    if (percent >= 40) return 'En camino';
    return 'Empieza aquí';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AttraSectionHeading(title: 'Fuerza del perfil'),
        const SizedBox(height: 8),
        Text('$percent% · $_label', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 6,
            semanticsLabel: 'Completitud del perfil',
            semanticsValue: '$percent',
            backgroundColor: context.colors.surfaceHigh,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Cuanto más completo esté tu perfil, más confianza y visibilidad '
          'tendrá. Completar tu perfil es gratis.',
          style: theme.textTheme.bodyMedium,
        ),
        if (pendingTasks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text('Para llegar al 100% te falta:',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          ...pendingTasks.map((String t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(Icons.radio_button_unchecked,
                          size: 18, color: context.colors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              )),
        ] else if (percent < 100) ...<Widget>[
          const SizedBox(height: 12),
          Text('No tienes tareas pendientes.',
              style: theme.textTheme.bodyMedium),
        ],
        if (percent >= 100) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Icon(Icons.verified, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('Perfil completo al 100%',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.primary))),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: onEdit,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Completar perfil'),
          ),
        ),
      ],
    );
  }
}

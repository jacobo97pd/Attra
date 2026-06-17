import 'package:flutter/material.dart';

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

  /// Tareas que faltan para el 100% (criterio explícito). Se muestran las más
  /// relevantes para que el camino al 100% sea claro.
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
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Fuerza del perfil', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('$percent%  ·  $_label',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Cuanto más completo esté tu perfil, más confianza y visibilidad '
              'tendrá. Completar tu perfil es gratis.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (percent < 100 && pendingTasks.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('Para llegar al 100% te falta:',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              ...pendingTasks.take(4).map((String t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.radio_button_unchecked,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(t, style: theme.textTheme.bodySmall)),
                      ],
                    ),
                  )),
              if (pendingTasks.length > 4)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('y ${pendingTasks.length - 4} más…',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
            ],
            if (percent >= 100) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.verified,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('Perfil completo al 100%',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Completar perfil'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

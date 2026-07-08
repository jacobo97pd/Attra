import 'package:flutter/material.dart';

import '../domain/intent_mode.dart';

/// Metadatos visuales de cada modo (etiqueta + icono). Centralizado para que
/// badge y selector usen lo mismo.
class IntentModeVisual {
  const IntentModeVisual(this.label, this.icon);
  final String label;
  final IconData icon;

  static IntentModeVisual of(IntentMode mode) {
    switch (mode) {
      case IntentMode.dating:
        return const IntentModeVisual('Citas', Icons.favorite_rounded);
      case IntentMode.friends:
        return const IntentModeVisual('Amistad', Icons.handshake_rounded);
      case IntentMode.both:
        return const IntentModeVisual('Ambas', Icons.auto_awesome_rounded);
      case IntentMode.groups:
        return const IntentModeVisual('Planes en grupo', Icons.groups_rounded);
    }
  }
}

/// Badge del modo de intención (Modo Amigos). Se muestra en el perfil.
/// Para `dating` puede ocultarse (es el comportamiento por defecto) pasando
/// [hideDating] = true.
class IntentBadge extends StatelessWidget {
  const IntentBadge({super.key, required this.mode, this.hideDating = false});

  final IntentMode mode;
  final bool hideDating;

  @override
  Widget build(BuildContext context) {
    if (hideDating && mode.isDating) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final IntentModeVisual v = IntentModeVisual.of(mode);
    final Color accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(v.icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            v.label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

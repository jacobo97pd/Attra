import 'package:flutter/material.dart';

import '../domain/intent_mode.dart';
import '../domain/social_copy.dart';
import 'intent_badge.dart';

/// Sheet para elegir el modo de intención (Modo Amigos). Autónomo: recibe el
/// modo actual y devuelve el elegido (o null si se cancela). Muestra un ejemplo
/// del copy que se usará (Like→Conectar, etc.).
class IntentModeSelector extends StatefulWidget {
  const IntentModeSelector({super.key, required this.current});

  final IntentMode current;

  static Future<IntentMode?> show(BuildContext context, IntentMode current) {
    return showModalBottomSheet<IntentMode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => IntentModeSelector(current: current),
    );
  }

  @override
  State<IntentModeSelector> createState() => _IntentModeSelectorState();
}

class _IntentModeSelectorState extends State<IntentModeSelector> {
  late IntentMode _selected = widget.current;

  static const Map<IntentMode, String> _subtitles = <IntentMode, String>{
    IntentMode.dating: 'Conocer gente para citas.',
    IntentMode.friends: 'Hacer amigos y conexiones sin presión romántica.',
    IntentMode.both: 'Abierto a citas y a amistad.',
    IntentMode.groups: 'Unirte a planes y grupos por intereses.',
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SocialCopy copy = SocialCopy.of(_selected);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('¿Qué buscas en Attra?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Puedes cambiarlo cuando quieras. Ajusta a quién ves y el tono de la app.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          for (final IntentMode mode in IntentMode.values)
            _OptionTile(
              mode: mode,
              subtitle: _subtitles[mode] ?? '',
              selected: _selected == mode,
              onTap: () => setState(() => _selected = mode),
            ),
          const SizedBox(height: 8),
          // Vista previa del copy que se aplicará.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'En este modo: “${copy.likeVerb}”, ${copy.matchNoun}, ${copy.dateNoun}, ${copy.compatibilityLabel}.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.mode,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IntentMode mode;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final IntentModeVisual v = IntentModeVisual.of(mode);
    final Color accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent
                  : theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(v.icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(v.label,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

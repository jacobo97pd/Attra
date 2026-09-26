import 'package:flutter/material.dart';

import '../../onboarding/presentation/interested_in_picker.dart';

/// Hoja "Me interesan": edita `preferences.interestedIn` con el mismo selector
/// del onboarding. Devuelve la selección (nunca vacía) o null si se cierra sin
/// guardar.
///
/// "Guardar" no se activa sin al menos una casilla: guardar la lista vacía es
/// justo lo que dejaba a alguien emparejando con todos los géneros en los dos
/// sentidos (ver InterestedIn).
class InterestedInSheet extends StatefulWidget {
  const InterestedInSheet({
    super.key,
    required this.initial,
    this.message,
  });

  final List<String> initial;

  /// Explicación opcional encima del selector (p. ej. por qué se pide al pasar
  /// a citas).
  final String? message;

  static Future<List<String>?> show(
    BuildContext context, {
    List<String> initial = const <String>[],
    String? message,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InterestedInSheet(initial: initial, message: message),
    );
  }

  @override
  State<InterestedInSheet> createState() => _InterestedInSheetState();
}

class _InterestedInSheetState extends State<InterestedInSheet> {
  late List<String> _selected = List<String>.from(widget.initial);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? message = widget.message;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('¿A quién quieres conocer?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            message ??
                'Solo lo usamos para citas: verás a estas personas y te verán '
                    'quienes también te buscan a ti.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          InterestedInPicker(
            title: 'Me interesan',
            selected: _selected,
            onChanged: (List<String> values) =>
                setState(() => _selected = values),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey<String>('interested-in-save'),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context)
                    .pop(List<String>.unmodifiable(_selected)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

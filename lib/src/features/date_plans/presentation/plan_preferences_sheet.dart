import 'package:flutter/material.dart';

/// Preferencias rápidas devueltas por el sheet (Estado 2 de la UX de Attra
/// Plans). Todo opcional: si el usuario no toca nada, el backend decide.
class PlanPreferences {
  const PlanPreferences({
    this.zone = '',
    this.dateRange = '',
    this.timeWindow = 'flexible',
    this.budget = '',
    this.planType = '',
  });

  final String zone;
  final String dateRange; // '' | 'this_week' | 'weekend'
  final String timeWindow; // 'afternoon' | 'evening' | 'flexible'
  final String budget; // '' | 'bajo' | 'medio' | 'alto'
  final String planType; // '' | 'cafe' | 'comida' | 'paseo' | 'cultura' | ...
}

/// Resultado del sheet: o generar con estas preferencias, o pasar a modo manual.
class PlanPreferencesResult {
  const PlanPreferencesResult({required this.preferences, this.manual = false});
  final PlanPreferences preferences;
  final bool manual;
}

/// Bottom sheet "Antes de buscar, dime qué prefieres". Elige zona/día/hora/
/// presupuesto/tipo y genera, o cambia a escribir el plan a mano.
class PlanPreferencesSheet extends StatefulWidget {
  const PlanPreferencesSheet({super.key});

  static Future<PlanPreferencesResult?> show(BuildContext context) {
    return showModalBottomSheet<PlanPreferencesResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const PlanPreferencesSheet(),
    );
  }

  @override
  State<PlanPreferencesSheet> createState() => _PlanPreferencesSheetState();
}

class _PlanPreferencesSheetState extends State<PlanPreferencesSheet> {
  final TextEditingController _zone = TextEditingController();
  String _dateRange = '';
  String _timeWindow = 'flexible';
  String _budget = '';
  String _planType = '';

  @override
  void dispose() {
    _zone.dispose();
    super.dispose();
  }

  PlanPreferences get _prefs => PlanPreferences(
        zone: _zone.text.trim(),
        dateRange: _dateRange,
        timeWindow: _timeWindow,
        budget: _budget,
        planType: _planType,
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Antes de buscar, dime qué prefieres',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Attra buscará sitios reales según intereses comunes. No '
              'compartiremos tu ubicación exacta con tu match.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _zone,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Zona (opcional)',
                hintText: 'Centro, Chamberí, Retiro, Malasaña…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _Group(
              label: 'Día',
              children: <Widget>[
                _choice('Esta semana', _dateRange == 'this_week',
                    () => setState(() => _dateRange = 'this_week')),
                _choice('Fin de semana', _dateRange == 'weekend',
                    () => setState(() => _dateRange = 'weekend')),
              ],
            ),
            _Group(
              label: 'Hora',
              children: <Widget>[
                _choice('Tarde', _timeWindow == 'afternoon',
                    () => setState(() => _timeWindow = 'afternoon')),
                _choice('Noche', _timeWindow == 'evening',
                    () => setState(() => _timeWindow = 'evening')),
                _choice('Flexible', _timeWindow == 'flexible',
                    () => setState(() => _timeWindow = 'flexible')),
              ],
            ),
            _Group(
              label: 'Presupuesto',
              children: <Widget>[
                _choice('Bajo', _budget == 'bajo',
                    () => setState(() => _budget = 'bajo')),
                _choice('Medio', _budget == 'medio',
                    () => setState(() => _budget = 'medio')),
                _choice('Alto', _budget == 'alto',
                    () => setState(() => _budget = 'alto')),
              ],
            ),
            _Group(
              label: 'Tipo',
              children: <Widget>[
                _choice('Café', _planType == 'cafe',
                    () => setState(() => _planType = 'cafe')),
                _choice('Cena casual', _planType == 'comida',
                    () => setState(() => _planType = 'comida')),
                _choice('Paseo', _planType == 'paseo',
                    () => setState(() => _planType = 'paseo')),
                _choice('Cultura', _planType == 'cultura',
                    () => setState(() => _planType = 'cultura')),
                _choice('Sorpresa', _planType == '',
                    () => setState(() => _planType = '')),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                PlanPreferencesResult(preferences: _prefs),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Buscar planes'),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(
                  PlanPreferencesResult(preferences: _prefs, manual: true),
                ),
                child: const Text('Prefiero escribirlo yo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

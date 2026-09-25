import 'package:flutter/material.dart';

import '../../../theme/attra_colors.dart';
import '../domain/feed_filters.dart';
import 'filters_screen.dart';

/// Editores rápidos de UN filtro, abiertos desde su chip en la cabecera del
/// feed (como en Hinge: tocar "Edad" edita la edad, sin pasar por la pantalla
/// entera de filtros).
///
/// Escriben sobre los mismos [FeedFilters] que [FiltersScreen] y con sus mismas
/// reglas —qué es "no negociable" por defecto, la distancia siempre dura—, para
/// que dé igual por dónde se ponga un filtro.
///
/// Devuelven los filtros nuevos, o `null` si se cierra sin aplicar.
class QuickFilterSheet {
  const QuickFilterSheet._();

  static Future<FeedFilters?> age(BuildContext context, FeedFilters current) =>
      _show(context, _AgeSheet(current: current));

  static Future<FeedFilters?> distance(
          BuildContext context, FeedFilters current) =>
      _show(context, _DistanceSheet(current: current));

  static Future<FeedFilters?> height(
          BuildContext context, FeedFilters current) =>
      _show(context, _HeightSheet(current: current));

  static Future<FeedFilters?> goal(BuildContext context, FeedFilters current) =>
      _show(context, _GoalSheet(current: current));

  static Future<FeedFilters?> _show(BuildContext context, Widget sheet) {
    return showModalBottomSheet<FeedFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => sheet,
    );
  }
}

Set<String> _withKey(Set<String> keys, String key, bool on) =>
    on ? <String>{...keys, key} : (<String>{...keys}..remove(key));

/// Armazón común: título, "Quitar" (vuelve el filtro a su valor neutro),
/// resumen del valor, el control y "Aplicar".
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.summary,
    required this.onClear,
    required this.onApply,
    required this.children,
  });

  final String title;
  final String summary;
  final VoidCallback onClear;
  final VoidCallback onApply;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  key: const ValueKey<String>('quick-filter-clear'),
                  onPressed: onClear,
                  child: const Text('Quitar'),
                ),
              ],
            ),
            Text(
              summary,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 8),
            ...children,
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey<String>('quick-filter-apply'),
              onPressed: onApply,
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "No negociable": sin él, el filtro es una preferencia que no deja a nadie
/// fuera. Se explica aquí porque es justo lo que confunde ("puse 25-35 y me
/// salen de 40").
class _DealbreakerSwitch extends StatelessWidget {
  const _DealbreakerSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const ValueKey<String>('quick-filter-dealbreaker'),
      contentPadding: EdgeInsets.zero,
      title: const Text('No negociable'),
      subtitle: const Text('Si lo dejas apagado, es una preferencia: no deja '
          'a nadie fuera.'),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _AgeSheet extends StatefulWidget {
  const _AgeSheet({required this.current});

  final FeedFilters current;

  @override
  State<_AgeSheet> createState() => _AgeSheetState();
}

class _AgeSheetState extends State<_AgeSheet> {
  late RangeValues _age = RangeValues(
    widget.current.minAge.toDouble(),
    widget.current.maxAge.toDouble(),
  );
  late bool _db = widget.current.isDealbreaker(FeedFilters.kAge);

  @override
  Widget build(BuildContext context) {
    final FeedFilters f = widget.current;
    return _SheetFrame(
      title: 'Edad',
      summary: '${_age.start.round()} – ${_age.end.round()} años',
      onClear: () => Navigator.of(context).pop(f.copyWith(
        minAge: FeedFilters.ageFloor,
        maxAge: FeedFilters.ageCeil,
        dealbreakers: _withKey(f.dealbreakers, FeedFilters.kAge, false),
      )),
      onApply: () => Navigator.of(context).pop(f.copyWith(
        minAge: _age.start.round(),
        maxAge: _age.end.round(),
        dealbreakers: _withKey(f.dealbreakers, FeedFilters.kAge, _db),
      )),
      children: <Widget>[
        RangeSlider(
          values: _age,
          min: FeedFilters.ageFloor.toDouble(),
          max: FeedFilters.ageCeil.toDouble(),
          divisions: FeedFilters.ageCeil - FeedFilters.ageFloor,
          labels: RangeLabels('${_age.start.round()}', '${_age.end.round()}'),
          onChanged: (RangeValues v) => setState(() => _age = v),
        ),
        _DealbreakerSwitch(
          value: _db,
          onChanged: (bool v) => setState(() => _db = v),
        ),
      ],
    );
  }
}

class _DistanceSheet extends StatefulWidget {
  const _DistanceSheet({required this.current});

  final FeedFilters current;

  @override
  State<_DistanceSheet> createState() => _DistanceSheetState();
}

class _DistanceSheetState extends State<_DistanceSheet> {
  // 100 km de partida, como en la pantalla completa.
  late double _km = (widget.current.maxDistanceKm ?? 100).toDouble();

  @override
  Widget build(BuildContext context) {
    final FeedFilters f = widget.current;
    // La distancia es siempre dura: poner un máximo y que siga saliendo gente
    // de más lejos no tiene lectura posible.
    return _SheetFrame(
      title: 'Distancia',
      summary: 'Hasta ${_km.round()} km',
      onClear: () => Navigator.of(context).pop(f.copyWith(
        clearDistance: true,
        dealbreakers: _withKey(f.dealbreakers, FeedFilters.kDistance, false),
      )),
      onApply: () => Navigator.of(context).pop(f.copyWith(
        maxDistanceKm: _km.round(),
        dealbreakers: _withKey(f.dealbreakers, FeedFilters.kDistance, true),
      )),
      children: <Widget>[
        Slider(
          value: _km,
          min: 1,
          max: 200,
          divisions: 199,
          label: '${_km.round()} km',
          onChanged: (double v) => setState(() => _km = v),
        ),
      ],
    );
  }
}

class _HeightSheet extends StatefulWidget {
  const _HeightSheet({required this.current});

  final FeedFilters current;

  @override
  State<_HeightSheet> createState() => _HeightSheetState();
}

class _HeightSheetState extends State<_HeightSheet> {
  late RangeValues _height = RangeValues(
    widget.current.minHeight.toDouble(),
    widget.current.maxHeight.toDouble(),
  );
  late bool _db = widget.current.isDealbreaker(FeedFilters.kHeight);

  @override
  Widget build(BuildContext context) {
    final FeedFilters f = widget.current;
    return _SheetFrame(
      title: 'Altura',
      summary: '${_height.start.round()} – ${_height.end.round()} cm',
      onClear: () => Navigator.of(context).pop(f.copyWith(
        minHeight: FeedFilters.heightFloor,
        maxHeight: FeedFilters.heightCeil,
        dealbreakers: _withKey(f.dealbreakers, FeedFilters.kHeight, false),
      )),
      onApply: () => Navigator.of(context).pop(f.copyWith(
        minHeight: _height.start.round(),
        maxHeight: _height.end.round(),
        dealbreakers: _withKey(f.dealbreakers, FeedFilters.kHeight, _db),
      )),
      children: <Widget>[
        RangeSlider(
          values: _height,
          min: FeedFilters.heightFloor.toDouble(),
          max: FeedFilters.heightCeil.toDouble(),
          divisions: FeedFilters.heightCeil - FeedFilters.heightFloor,
          labels:
              RangeLabels('${_height.start.round()}', '${_height.end.round()}'),
          onChanged: (RangeValues v) => setState(() => _height = v),
        ),
        _DealbreakerSwitch(
          value: _db,
          onChanged: (bool v) => setState(() => _db = v),
        ),
      ],
    );
  }
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.current});

  final FeedFilters current;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late String? _goal = widget.current.relationshipGoal;
  late bool _db = widget.current.isDealbreaker(FeedFilters.kGoal);

  String get _summary {
    for (final FilterOption o in FiltersScreen.goalOptions) {
      if (o.value == _goal) return o.label;
    }
    return 'Cualquiera';
  }

  @override
  Widget build(BuildContext context) {
    final FeedFilters f = widget.current;
    FeedFilters cleared() => f.copyWith(
          clearGoal: true,
          dealbreakers: _withKey(f.dealbreakers, FeedFilters.kGoal, false),
        );
    return _SheetFrame(
      title: 'Qué busca',
      summary: _summary,
      onClear: () => Navigator.of(context).pop(cleared()),
      onApply: () {
        final String? goal = _goal;
        Navigator.of(context).pop(goal == null
            ? cleared()
            : f.copyWith(
                relationshipGoal: goal,
                dealbreakers: _withKey(f.dealbreakers, FeedFilters.kGoal, _db),
              ));
      },
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Cualquiera'),
              selected: _goal == null,
              onSelected: (_) => setState(() => _goal = null),
            ),
            for (final FilterOption o in FiltersScreen.goalOptions)
              ChoiceChip(
                label: Text(o.label),
                selected: _goal == o.value,
                // Al elegir, no negociable por defecto: igual que en la
                // pantalla completa de filtros.
                onSelected: (_) => setState(() {
                  _goal = o.value;
                  _db = true;
                }),
              ),
          ],
        ),
        if (_goal != null)
          _DealbreakerSwitch(
            value: _db,
            onChanged: (bool v) => setState(() => _db = v),
          ),
      ],
    );
  }
}

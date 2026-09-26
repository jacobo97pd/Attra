import 'package:flutter/material.dart';

import '../domain/feed_filter.dart';
import '../domain/feed_filters.dart';

/// Opción de un filtro de selección única: valor que se guarda y etiqueta.
typedef FilterOption = ({String value, String label});

/// Filtros del feed (estilo Hinge). Básicos (gratis): edad, géneros, foto,
/// distancia. Avanzados (Plus): qué busca, hábitos, estudios, altura,
/// etnicidad, religión, verificación. Cada filtro relevante puede marcarse
/// "No negociable" (excluye duro) o dejarse como preferencia blanda. Siempre
/// duros: edad (recíproca), géneros, foto, distancia y verificación.
class FiltersScreen extends StatefulWidget {
  const FiltersScreen({
    super.key,
    required this.initial,
    required this.isPlus,
    this.canVisualMatch = false,
    this.radiusKm = FeedFilter.defaultRadiusKm,
  });

  final FeedFilters initial;
  final bool isPlus;

  /// Radio que el feed está aplicando ahora (el guardado o el por defecto):
  /// la distancia arranca ahí. Antes la pantalla enseñaba "Distancia máxima"
  /// APAGADA —que se lee como "sin límite"— mientras el feed cortaba en el
  /// radio del onboarding.
  final int radiusKm;

  /// Pro con referencia + consentimiento: muestra "ordenar por parecido".
  final bool canVisualMatch;

  /// Público porque el chip rápido "Qué busca" del feed ofrece las mismas
  /// opciones: dos listas escritas a mano acabarían diciendo cosas distintas.
  static const List<FilterOption> goalOptions = <FilterOption>[
    (value: 'serious_relationship', label: 'Relación seria'),
    (value: 'meet_people', label: 'Conocer gente'),
    (value: 'casual', label: 'Algo casual'),
    (value: 'open_to_see', label: 'Abierto'),
  ];

  static Future<FeedFilters?> show(
    BuildContext context, {
    required FeedFilters initial,
    required bool isPlus,
    bool canVisualMatch = false,
    int radiusKm = FeedFilter.defaultRadiusKm,
  }) {
    return Navigator.of(context)
        .push<FeedFilters>(MaterialPageRoute<FeedFilters>(
      builder: (_) => FiltersScreen(
        initial: initial,
        isPlus: isPlus,
        canVisualMatch: canVisualMatch,
        radiusKm: radiusKm,
      ),
    ));
  }

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  late RangeValues _age;
  late Set<String> _genders;
  late bool _onlyWithPhoto;
  late double _distance;
  String? _goal;
  String? _smoking;
  String? _drinking;
  String? _education;
  String? _ethnicity;
  String? _religion;
  bool _verifiedOnly = false;
  bool _sortByRef = false;
  final TextEditingController _promptController = TextEditingController();
  late RangeValues _height;
  late Set<String> _db; // deal-breakers

  static const List<FilterOption> _genderOptions = <FilterOption>[
    (value: 'female', label: 'Mujeres'),
    (value: 'male', label: 'Hombres'),
    (value: 'non_binary', label: 'No binario'),
  ];
  static const List<FilterOption> _smokingOptions = <FilterOption>[
    (value: 'never', label: 'No fuma'),
    (value: 'occasionally', label: 'Ocasional'),
  ];
  static const List<FilterOption> _drinkingOptions = <FilterOption>[
    (value: 'never', label: 'No bebe'),
    (value: 'socially', label: 'Socialmente'),
  ];
  static const List<FilterOption> _educationOptions = <FilterOption>[
    (value: 'high_school', label: 'Bachillerato'),
    (value: 'vocational', label: 'FP'),
    (value: 'bachelor', label: 'Grado'),
    (value: 'master', label: 'Máster'),
    (value: 'phd', label: 'Doctorado'),
  ];
  static const List<FilterOption> _ethnicityOptions = <FilterOption>[
    (value: 'white_caucasian', label: 'Blanca/caucásica'),
    (value: 'hispanic_latino', label: 'Hispana/latina'),
    (value: 'black_afro', label: 'Negra/afro'),
    (value: 'east_asian', label: 'Asiática oriental'),
    (value: 'south_asian', label: 'Asiática del sur'),
    (value: 'middle_eastern_north_african', label: 'MENA'),
    (value: 'multiracial', label: 'Multirracial'),
  ];
  static const List<FilterOption> _religionOptions = <FilterOption>[
    (value: 'christian', label: 'Cristiana'),
    (value: 'catholic', label: 'Católica'),
    (value: 'muslim', label: 'Musulmana'),
    (value: 'jewish', label: 'Judía'),
    (value: 'hindu', label: 'Hindú'),
    (value: 'buddhist', label: 'Budista'),
    (value: 'spiritual', label: 'Espiritual'),
    (value: 'none', label: 'Ninguna'),
  ];

  @override
  void initState() {
    super.initState();
    final FeedFilters f = widget.initial;
    _age = RangeValues(f.minAge.toDouble(), f.maxAge.toDouble());
    _genders = <String>{...f.showGenders};
    _onlyWithPhoto = f.onlyWithPhoto;
    _distance = (f.maxDistanceKm ?? widget.radiusKm)
        .clamp(FeedFilters.distanceFloor, FeedFilters.distanceCeil)
        .toDouble();
    _height = RangeValues(f.minHeight.toDouble(), f.maxHeight.toDouble());
    _db = <String>{...f.dealbreakers};
    _sortByRef = f.sortByVisualReference;
    _promptController.text = f.promptQuery;
    if (widget.isPlus) {
      _goal = f.relationshipGoal;
      _smoking = f.smoking;
      _drinking = f.drinking;
      _education = f.educationLevel;
      _ethnicity = f.ethnicity;
      _religion = f.religion;
      _verifiedOnly = f.verifiedOnly;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _apply() {
    final FeedFilters initial = widget.initial;
    final bool plus = widget.isPlus;
    // Sin Plus los avanzados ni se ven ni se aplican (el feed los quita al
    // aplicar), pero lo que había guardado SE CONSERVA tal cual: si vuelve a
    // Plus, vuelven sus filtros. Antes se borraban aquí.
    final Set<String> db = <String>{
      ..._db.difference(FeedFilters.plusKeys),
      ...(plus ? _db : initial.dealbreakers).intersection(FeedFilters.plusKeys),
      FeedFilters.kDistance, // distancia siempre dura
    };
    final int km = _distance.round();
    Navigator.of(context).pop(FeedFilters(
      minAge: _age.start.round(),
      maxAge: _age.end.round(),
      showGenders: _genders,
      onlyWithPhoto: _onlyWithPhoto,
      // Sin radio guardado y sin tocar el slider, se sigue sin guardar uno:
      // el feed usa el de por defecto igual.
      maxDistanceKm:
          (initial.maxDistanceKm == null && km == widget.radiusKm) ? null : km,
      relationshipGoal: plus ? _goal : initial.relationshipGoal,
      smoking: plus ? _smoking : initial.smoking,
      drinking: plus ? _drinking : initial.drinking,
      educationLevel: plus ? _education : initial.educationLevel,
      ethnicity: plus ? _ethnicity : initial.ethnicity,
      religion: plus ? _religion : initial.religion,
      verifiedOnly: plus ? _verifiedOnly : initial.verifiedOnly,
      minHeight: plus ? _height.start.round() : initial.minHeight,
      maxHeight: plus ? _height.end.round() : initial.maxHeight,
      dealbreakers: db,
      sortByVisualReference: plus && _sortByRef,
      promptQuery: widget.canVisualMatch ? _promptController.text.trim() : '',
    ));
  }

  void _reset() => setState(() {
        _age = const RangeValues(
            FeedFilters.ageFloor + 0.0, FeedFilters.ageCeil + 0.0);
        _genders = <String>{};
        _onlyWithPhoto = false;
        _distance = FeedFilter.defaultRadiusKm.toDouble();
        _goal =
            _smoking = _drinking = _education = _ethnicity = _religion = null;
        _verifiedOnly = false;
        _sortByRef = false;
        _promptController.clear();
        _height = const RangeValues(
            FeedFilters.heightFloor + 0.0, FeedFilters.heightCeil + 0.0);
        _db = <String>{};
      });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferencias de citas'),
        actions: <Widget>[
          TextButton(onPressed: _reset, child: const Text('Restablecer')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Básicos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          // Edad.
          Text('Edad: ${_age.start.round()} – ${_age.end.round()}',
              style: theme.textTheme.bodyMedium),
          RangeSlider(
            values: _age,
            min: FeedFilters.ageFloor.toDouble(),
            max: FeedFilters.ageCeil.toDouble(),
            divisions: FeedFilters.ageCeil - FeedFilters.ageFloor,
            labels: RangeLabels('${_age.start.round()}', '${_age.end.round()}'),
            onChanged: (RangeValues v) => setState(() => _age = v),
          ),
          // Sin "No negociable": la edad es siempre dura y recíproca (el
          // mismo rango del onboarding y del directo).
          Text(
            'Es recíproco: ves a quien está en tu rango y además te incluye '
            'en el suyo.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Text('Mostrarme', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final FilterOption o in _genderOptions)
                FilterChip(
                  label: Text(o.label),
                  selected: _genders.contains(o.value),
                  onSelected: (_) => setState(() => _genders.contains(o.value)
                      ? _genders.remove(o.value)
                      : _genders.add(o.value)),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Solo perfiles con foto'),
            value: _onlyWithPhoto,
            onChanged: (bool v) => setState(() => _onlyWithPhoto = v),
          ),
          // Distancia: siempre hay un radio (el guardado o el por defecto), así
          // que no hay interruptor. Mismo tope que el onboarding (500 km).
          Text('Distancia máxima: ${_distance.round()} km',
              key: const ValueKey<String>('filters-distance-label'),
              style: theme.textTheme.bodyMedium),
          Slider(
            key: const ValueKey<String>('filters-distance-slider'),
            value: _distance,
            min: FeedFilters.distanceFloor.toDouble(),
            max: FeedFilters.distanceCeil.toDouble(),
            divisions: FeedFilters.distanceCeil - FeedFilters.distanceFloor,
            label: '${_distance.round()} km',
            onChanged: (double v) => setState(() => _distance = v),
          ),
          const Divider(height: 32),

          // Avanzados (Plus).
          Row(children: <Widget>[
            Text('Avanzados', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            if (!widget.isPlus) const _PlusChip(),
          ]),
          const SizedBox(height: 8),
          if (!widget.isPlus)
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Filtros avanzados'),
                subtitle: Text(
                    'Qué busca, hábitos, estudios, altura, etnicidad, religión y verificación con Attra Plus.'),
              ),
            )
          else ...<Widget>[
            _single('Qué busca', FiltersScreen.goalOptions, _goal,
                FeedFilters.kGoal, (String? v) => setState(() => _goal = v)),
            _single('Tabaco', _smokingOptions, _smoking, FeedFilters.kSmoking,
                (String? v) => setState(() => _smoking = v)),
            _single(
                'Alcohol',
                _drinkingOptions,
                _drinking,
                FeedFilters.kDrinking,
                (String? v) => setState(() => _drinking = v)),
            _single(
                'Estudios',
                _educationOptions,
                _education,
                FeedFilters.kEducation,
                (String? v) => setState(() => _education = v)),
            _single(
                'Etnicidad',
                _ethnicityOptions,
                _ethnicity,
                FeedFilters.kEthnicity,
                (String? v) => setState(() => _ethnicity = v),
                note: 'Solo cruza con quien consintió usarlo en filtros.'),
            _single(
                'Religión',
                _religionOptions,
                _religion,
                FeedFilters.kReligion,
                (String? v) => setState(() => _religion = v),
                note: 'Solo cruza con quien consintió usarlo en filtros.'),
            // Siempre duro, como "Solo perfiles con foto": antes había que
            // marcar además "No negociable" (apagado por defecto) y, si no,
            // el filtro activo no dejaba fuera a ningún no verificado.
            SwitchListTile(
              key: const ValueKey<String>('filters-verified-only'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo verificados'),
              value: _verifiedOnly,
              onChanged: (bool v) => setState(() => _verifiedOnly = v),
            ),
            if (widget.canVisualMatch)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(Icons.auto_awesome,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Solo parecidos a mi referencia'),
                subtitle: const Text(
                    'Filtro IA visual de Pro: muestra únicamente perfiles que se parecen a tu foto de referencia'),
                value: _sortByRef,
                onChanged: (bool v) => setState(() => _sortByRef = v),
              ),
            if (widget.canVisualMatch) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(Icons.search,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Buscar por descripción',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _promptController,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'Ej: chico alto, ojos azules, moreno, aventurero y que le guste viajar',
                  border: OutlineInputBorder(),
                  helperText:
                      'IA de Pro: analiza fotos + datos y muestra solo los que encajan',
                  helperMaxLines: 2,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('Altura: ${_height.start.round()} – ${_height.end.round()} cm',
                style: theme.textTheme.bodyMedium),
            RangeSlider(
              values: _height,
              min: FeedFilters.heightFloor.toDouble(),
              max: FeedFilters.heightCeil.toDouble(),
              divisions: FeedFilters.heightCeil - FeedFilters.heightFloor,
              labels: RangeLabels(
                  '${_height.start.round()}', '${_height.end.round()}'),
              onChanged: (RangeValues v) => setState(() => _height = v),
            ),
            _dbSwitch(FeedFilters.kHeight),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _apply, child: const Text('Aplicar filtros')),
        ],
      ),
    );
  }

  /// Toggle "No negociable" para un filtro.
  Widget _dbSwitch(String key) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: <Widget>[
          const Text('No negociable', style: TextStyle(fontSize: 13)),
          const Spacer(),
          Switch(
            value: _db.contains(key),
            onChanged: (bool v) =>
                setState(() => v ? _db.add(key) : _db.remove(key)),
          ),
        ],
      ),
    );
  }

  /// Selección única con opción "Cualquiera" (null) + deal-breaker si hay valor.
  Widget _single(String title, List<FilterOption> options, String? current,
      String key, ValueChanged<String?> onChanged,
      {String? note}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.bodyMedium),
        if (note != null)
          Text(note,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Cualquiera'),
              selected: current == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final FilterOption o in options)
              ChoiceChip(
                label: Text(o.label),
                selected: current == o.value,
                onSelected: (_) {
                  onChanged(o.value);
                  setState(() => _db.add(key)); // por defecto, no negociable
                },
              ),
          ],
        ),
        if (current != null) _dbSwitch(key),
      ],
    );
  }
}

class _PlusChip extends StatelessWidget {
  const _PlusChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFB8860B).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('Plus',
          style: TextStyle(
              color: Color(0xFFB8860B),
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }
}

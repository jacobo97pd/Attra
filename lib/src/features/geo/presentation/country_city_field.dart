import 'dart:async';

import 'package:flutter/material.dart';

import '../data/geo_repository.dart';

/// Selección de país + ciudad validada contra el dataset offline.
///
/// Garantiza que el país es real (lista ISO) y que la ciudad existe de verdad
/// en ese país (no se puede escribir "TONTO"). Notifica al padre con el ISO2,
/// el nombre del país y el nombre canónico de la ciudad.
class CountryCityField extends StatefulWidget {
  const CountryCityField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialCountryIso2,
    this.initialCountryName,
    this.initialCity,
  });

  final String label;
  final String? initialCountryIso2;
  final String? initialCountryName;
  final String? initialCity;
  final void Function({
    required String? iso2,
    required String? countryName,
    required String? city,
    required bool cityIsValid,
  }) onChanged;

  @override
  State<CountryCityField> createState() => _CountryCityFieldState();
}

class _CountryCityFieldState extends State<CountryCityField> {
  final GeoRepository _geo = GeoRepository.instance;
  final TextEditingController _cityController = TextEditingController();
  final FocusNode _cityFocus = FocusNode();

  Country? _country;
  List<String> _suggestions = const <String>[];
  bool _cityValid = false;
  Timer? _debounce;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _cityController.text = widget.initialCity ?? '';
    _cityFocus.addListener(() {
      if (!_cityFocus.hasFocus) {
        setState(() => _suggestions = const <String>[]);
      }
    });
    _restoreInitialCountry();
  }

  Future<void> _restoreInitialCountry() async {
    final String? iso2 = widget.initialCountryIso2;
    if (iso2 != null && iso2.isNotEmpty) {
      final Country? c = await _geo.countryByIso2(iso2);
      if (!mounted || c == null) {
        return;
      }
      setState(() => _country = c);
      if ((widget.initialCity ?? '').isNotEmpty) {
        final bool valid = await _geo.isValidCity(iso2, widget.initialCity!);
        if (mounted) {
          setState(() => _cityValid = valid);
        }
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cityController.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(
      iso2: _country?.iso2,
      countryName: _country?.name,
      city: _cityController.text.trim(),
      cityIsValid: _country != null && _cityValid,
    );
  }

  Future<void> _pickCountry() async {
    final List<Country> countries = await _geo.loadCountries();
    if (!mounted) {
      return;
    }
    final Country? selected = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) =>
          _CountryPickerSheet(countries: countries),
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _country = selected;
      _cityController.clear();
      _suggestions = const <String>[];
      _cityValid = false;
    });
    _notify();
  }

  void _onCityChanged(String value) {
    _debounce?.cancel();
    final Country? country = _country;
    if (country == null) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      final int token = ++_searchToken;
      final List<String> results =
          await _geo.searchCities(country.iso2, value, limit: 8);
      final bool valid = await _geo.isValidCity(country.iso2, value);
      if (!mounted || token != _searchToken) {
        return;
      }
      setState(() {
        _suggestions = results;
        _cityValid = valid;
      });
      _notify();
    });
  }

  void _selectSuggestion(String city) {
    _cityController.text = city;
    _cityController.selection = TextSelection.fromPosition(
      TextPosition(offset: city.length),
    );
    setState(() {
      _suggestions = const <String>[];
      _cityValid = true;
    });
    _cityFocus.unfocus();
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Country? country = _country;
    final bool showInvalid = country != null &&
        _cityController.text.trim().isNotEmpty &&
        !_cityValid &&
        _suggestions.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(widget.label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickCountry,
          icon: Text(
            country?.emoji.isNotEmpty == true ? country!.emoji : '🌍',
            style: const TextStyle(fontSize: 18),
          ),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(country?.name ?? 'Selecciona país *'),
          ),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _cityController,
          focusNode: _cityFocus,
          enabled: country != null,
          onChanged: _onCityChanged,
          decoration: InputDecoration(
            labelText: 'Ciudad *',
            hintText: country == null
                ? 'Primero elige país'
                : 'Escribe y elige de la lista',
            border: const OutlineInputBorder(),
            suffixIcon: _cityValid
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            errorText: showInvalid
                ? 'Esa ciudad no existe en ${country.name}. Elige una de la lista.'
                : null,
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: _suggestions
                  .map((String city) => ListTile(
                        dense: true,
                        title: Text(city),
                        onTap: () => _selectSuggestion(city),
                      ))
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.countries});

  final List<Country> countries;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  late List<Country> _filtered = widget.countries;

  void _filter(String query) {
    final String q = GeoRepository.normalize(query);
    setState(() {
      _filtered = q.isEmpty
          ? widget.countries
          : widget.countries
              .where((Country c) => GeoRepository.normalize(c.name).contains(q))
              .toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.of(context).size.height * 0.8;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  autofocus: true,
                  onChanged: _filter,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar país',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Country c = _filtered[index];
                    return ListTile(
                      leading: Text(
                        c.emoji.isNotEmpty ? c.emoji : '🌍',
                        style: const TextStyle(fontSize: 22),
                      ),
                      title: Text(c.name),
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

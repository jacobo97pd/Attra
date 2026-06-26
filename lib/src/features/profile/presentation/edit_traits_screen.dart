import 'package:flutter/material.dart';

import '../domain/profile_trait.dart';
import '../domain/profile_traits_catalog.dart';
import '../domain/profile_visibility.dart';

/// Editor de perfil enriquecido dirigido por [ProfileTraitsCatalog]. Cada rasgo
/// se puede completar/editar/borrar; los sensibles muestran consentimiento
/// separado (mostrar / matching / filtros) y quedan OPT-IN.
class EditTraitsScreen extends StatefulWidget {
  const EditTraitsScreen({
    super.key,
    required this.loadData,
    required this.onSetTrait,
    required this.onSetVisibility,
  });

  final Future<Map<String, dynamic>> Function() loadData;
  final Future<void> Function(ProfileTraitDefinition def, Object? value)
      onSetTrait;
  final Future<void> Function(
    String traitKey, {
    required bool visibleInProfile,
    required bool useForMatching,
    required bool useForFilters,
  }) onSetVisibility;

  @override
  State<EditTraitsScreen> createState() => _EditTraitsScreenState();
}

class _EditTraitsScreenState extends State<EditTraitsScreen> {
  Map<String, dynamic> _data = <String, dynamic>{};
  ProfileVisibility _visibility = const ProfileVisibility();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final Map<String, dynamic> data = await widget.loadData();
    if (!mounted) return;
    setState(() {
      _data = data;
      _visibility = ProfileVisibility.fromUserData(data);
      _loading = false;
    });
  }

  Map<String, dynamic> _group(String group) {
    final dynamic g = _data[group];
    if (g is Map) {
      return g.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  Object? _value(ProfileTraitDefinition def) => _group(def.group)[def.field];

  String _displayValue(ProfileTraitDefinition def) {
    final Object? v = _value(def);
    if (v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty)) {
      return 'Añadir';
    }
    String label(String code) {
      for (final TraitOption o in def.options) {
        if (o.value == code) return o.label;
      }
      return code;
    }

    if (v is List) {
      return v.whereType<String>().map(label).join(', ');
    }
    if (v is String) return def.isSelect ? label(v) : v;
    return '$v';
  }

  Future<void> _save(ProfileTraitDefinition def, Object? value) async {
    await widget.onSetTrait(def, value);
    await _reload();
  }

  Future<void> _edit(ProfileTraitDefinition def) async {
    switch (def.type) {
      case TraitType.singleSelect:
        await _editSingle(def);
        break;
      case TraitType.multiSelect:
        if (def.options.isEmpty) {
          await _editFreeList(def);
        } else {
          await _editMulti(def);
        }
        break;
      case TraitType.text:
        await _editText(def, number: false);
        break;
      case TraitType.number:
        await _editText(def, number: true);
        break;
    }
  }

  Future<void> _editSingle(ProfileTraitDefinition def) async {
    final Object? current = _value(def);
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Quitar / borrar'),
              onTap: () => Navigator.of(context).pop('__clear__'),
            ),
            const Divider(height: 1),
            for (final TraitOption o in def.options)
              ListTile(
                title: Text(o.label),
                trailing: current == o.value ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(o.value),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _save(def, picked == '__clear__' ? null : picked);
  }

  Future<void> _editMulti(ProfileTraitDefinition def) async {
    final Set<String> selected = <String>{
      ...(_value(def) is List
          ? (_value(def)! as List).whereType<String>()
          : const <String>[]),
    };
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder:
            (BuildContext context, void Function(void Function()) setLocal) {
          return AlertDialog(
            title: Text(def.label),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final TraitOption o in def.options)
                    CheckboxListTile(
                      value: selected.contains(o.value),
                      title: Text(o.label),
                      onChanged: (bool? v) => setLocal(() {
                        if (v == true) {
                          selected.add(o.value);
                        } else {
                          selected.remove(o.value);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Guardar')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    await _save(def, selected.toList(growable: false));
  }

  Future<void> _editFreeList(ProfileTraitDefinition def) async {
    final Object? v = _value(def);
    final TextEditingController c = TextEditingController(
        text: v is List ? v.whereType<String>().join(', ') : '');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(def.label),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
              helperText: 'Separa con comas', border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final List<String> list = c.text
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    await _save(def, list);
  }

  Future<void> _editText(ProfileTraitDefinition def,
      {required bool number}) async {
    final Object? v = _value(def);
    final TextEditingController c =
        TextEditingController(text: v == null ? '' : '$v');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(def.label),
        content: TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final String text = c.text.trim();
    if (number) {
      await _save(def, text.isEmpty ? null : int.tryParse(text));
    } else {
      await _save(def, text.isEmpty ? null : text);
    }
  }

  Future<void> _setVis(ProfileTraitDefinition def, FieldVisibility v) async {
    await widget.onSetVisibility(
      def.key,
      visibleInProfile: v.visibleInProfile,
      useForMatching: v.useForMatching,
      useForFilters: v.useForFilters,
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Completar perfil')),
      body: ListView(
        children: <Widget>[
          for (final ProfileSection section in ProfileTraitsCatalog.sections)
            _sectionTile(section),
        ],
      ),
    );
  }

  Widget _sectionTile(ProfileSection section) {
    return ExpansionTile(
      title: Text(section.title),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: <Widget>[
        for (final ProfileTraitDefinition def in section.definitions)
          _traitTile(def),
      ],
    );
  }

  Widget _traitTile(ProfileTraitDefinition def) {
    final ThemeData theme = Theme.of(context);
    final FieldVisibility vis = _visibility.effectiveFor(def);
    final bool isSet = _displayValue(def) != 'Añadir';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          title: Row(
            children: <Widget>[
              Flexible(child: Text(def.label)),
              if (def.sensitive)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.lock_outline,
                      size: 15, color: theme.colorScheme.outline),
                ),
            ],
          ),
          subtitle: Text(_displayValue(def),
              style: TextStyle(
                  color: isSet
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _edit(def),
        ),
        if (def.sensitive && isSet)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: <Widget>[
                _visSwitch(
                    'Mostrar en mi perfil',
                    vis.visibleInProfile,
                    (bool b) =>
                        _setVis(def, vis.copyWith(visibleInProfile: b))),
                _visSwitch('Usar en recomendaciones', vis.useForMatching,
                    (bool b) => _setVis(def, vis.copyWith(useForMatching: b))),
                _visSwitch('Usar en filtros', vis.useForFilters,
                    (bool b) => _setVis(def, vis.copyWith(useForFilters: b))),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _visSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      onChanged: onChanged,
    );
  }
}

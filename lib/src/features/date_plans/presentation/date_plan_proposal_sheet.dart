import 'package:flutter/material.dart';

import '../domain/date_plan.dart';

/// Resultado del sheet: opciones + zona/privacidad para crear una propuesta.
class DatePlanProposalInput {
  const DatePlanProposalInput({
    required this.options,
    this.city = '',
    this.zone = '',
    this.privacyMode = DatePlanPrivacyMode.city,
  });

  final List<DatePlanOption> options;
  final String city;
  final String zone;
  final DatePlanPrivacyMode privacyMode;
}

/// Attra Plans — Fase 1: sheet de creación MANUAL de una propuesta de plan.
///
/// Sin IA ni Places: el usuario compone 1-3 opciones. Se pide una zona (nunca la
/// ubicación exacta) y se muestra el copy de consentimiento/privacidad. La
/// generación con lugares reales llega en fases posteriores.
class DatePlanProposalSheet extends StatefulWidget {
  const DatePlanProposalSheet({super.key, this.initialCity = ''});

  final String initialCity;

  static Future<DatePlanProposalInput?> show(
    BuildContext context, {
    String initialCity = '',
  }) {
    return showModalBottomSheet<DatePlanProposalInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DatePlanProposalSheet(initialCity: initialCity),
    );
  }

  @override
  State<DatePlanProposalSheet> createState() => _DatePlanProposalSheetState();
}

class _DatePlanProposalSheetState extends State<DatePlanProposalSheet> {
  static const int _maxOptions = 3;
  final TextEditingController _zone = TextEditingController();
  final List<_OptionDraft> _drafts = <_OptionDraft>[_OptionDraft()];
  bool _triedSubmit = false;

  @override
  void dispose() {
    _zone.dispose();
    for (final _OptionDraft d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_drafts.length >= _maxOptions) return;
    setState(() => _drafts.add(_OptionDraft()));
  }

  void _removeOption(int i) {
    if (_drafts.length <= 1) return;
    setState(() {
      _drafts.removeAt(i).dispose();
    });
  }

  void _submit() {
    setState(() => _triedSubmit = true);
    final List<DatePlanOption> options = <DatePlanOption>[];
    for (int i = 0; i < _drafts.length; i++) {
      final _OptionDraft d = _drafts[i];
      final String title = d.title.text.trim();
      if (title.isEmpty) return; // hay una opción sin título → bloquea
      options.add(DatePlanOption(
        id: 'opt_${i + 1}',
        title: title,
        placeName: d.place.text.trim(),
        description: d.description.text.trim(),
        whyItFits: d.why.text.trim(),
        suggestedDateTime: d.dateTime,
        sourceApi: 'manual',
      ));
    }
    if (options.isEmpty) return;
    Navigator.of(context).pop(DatePlanProposalInput(
      options: options,
      zone: _zone.text.trim(),
      privacyMode: _zone.text.trim().isEmpty
          ? DatePlanPrivacyMode.city
          : DatePlanPrivacyMode.zone,
    ));
  }

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
            Text('Proponer un plan', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Comparte 1-3 ideas de plan. Vuestro match podrá elegir la que más '
              'le guste.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 14),
            _ConsentBanner(theme: theme),
            const SizedBox(height: 14),
            TextField(
              controller: _zone,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Zona (opcional)',
                hintText: 'Centro, Chamberí, Retiro, Malasaña…',
                helperText: 'No compartimos tu ubicación exacta, solo la zona.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < _drafts.length; i++) ...<Widget>[
              _OptionEditor(
                index: i,
                draft: _drafts[i],
                showError: _triedSubmit && _drafts[i].title.text.trim().isEmpty,
                canRemove: _drafts.length > 1,
                onRemove: () => _removeOption(i),
                onPickDateTime: () => _pickDateTime(i),
              ),
              const SizedBox(height: 12),
            ],
            if (_drafts.length < _maxOptions)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Añadir otra opción'),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send),
              label: const Text('Enviar propuesta'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime(int i) async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _drafts[i].dateTime ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 30),
    );
    if (!mounted) return;
    setState(() {
      _drafts[i].dateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 19,
        time?.minute ?? 30,
      );
    });
  }
}

class _ConsentBanner extends StatelessWidget {
  const _ConsentBanner({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Attra puede sugerir planes según intereses comunes. No '
              'compartiremos tu ubicación exacta con tu match.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    required this.index,
    required this.draft,
    required this.showError,
    required this.canRemove,
    required this.onRemove,
    required this.onPickDateTime,
  });

  final int index;
  final _OptionDraft draft;
  final bool showError;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onPickDateTime;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String dtLabel = draft.dateTime == null
        ? 'Día y hora (opcional)'
        : _fmt(draft.dateTime!);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Opción ${index + 1}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Quitar',
                ),
            ],
          ),
          TextField(
            controller: draft.title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Título del plan',
              hintText: 'Café tranquilo, paseo, exposición…',
              border: const OutlineInputBorder(),
              errorText: showError ? 'Ponle un título' : null,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: draft.place,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Lugar o idea (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPickDateTime,
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(dtLabel, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} · '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _OptionDraft {
  final TextEditingController title = TextEditingController();
  final TextEditingController place = TextEditingController();
  final TextEditingController description = TextEditingController();
  final TextEditingController why = TextEditingController();
  DateTime? dateTime;

  void dispose() {
    title.dispose();
    place.dispose();
    description.dispose();
    why.dispose();
  }
}

import 'package:flutter/material.dart';

/// Datos que devuelve el sheet de propuesta de cita.
class DateProposalInput {
  const DateProposalInput({
    required this.date,
    required this.time,
    required this.placeName,
    this.placeAddress = '',
    this.note = '',
  });

  final DateTime date;
  final TimeOfDay time;
  final String placeName;
  final String placeAddress;
  final String note;

  String get dateIso => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String get timeHm => '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// Bottom sheet "Proponer cita": fecha, hora, lugar, dirección y nota opcional.
/// Devuelve [DateProposalInput] o null si se cancela.
class DateProposalSheet extends StatefulWidget {
  const DateProposalSheet({
    super.key,
    this.initialPlaceName = '',
    this.initialNote = '',
  });

  /// Prefill opcional (lo usa el Date Builder). El usuario puede editarlo antes
  /// de enviar.
  final String initialPlaceName;
  final String initialNote;

  static Future<DateProposalInput?> show(
    BuildContext context, {
    String initialPlaceName = '',
    String initialNote = '',
  }) {
    return showModalBottomSheet<DateProposalInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DateProposalSheet(
        initialPlaceName: initialPlaceName,
        initialNote: initialNote,
      ),
    );
  }

  @override
  State<DateProposalSheet> createState() => _DateProposalSheetState();
}

class _DateProposalSheetState extends State<DateProposalSheet> {
  static const int _maxNote = 300;
  final TextEditingController _place = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _triedSubmit = false;

  @override
  void initState() {
    super.initState();
    _place.text = widget.initialPlaceName;
    _note.text = widget.initialNote;
  }

  @override
  void dispose() {
    _place.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 20, minute: 30),
    );
    if (picked != null) setState(() => _time = picked);
  }

  void _submit() {
    setState(() => _triedSubmit = true);
    if (_date == null || _time == null || _place.text.trim().isEmpty) return;
    Navigator.of(context).pop(DateProposalInput(
      date: _date!,
      time: _time!,
      placeName: _place.text.trim(),
      placeAddress: _address.text.trim(),
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String dateLabel = _date == null
        ? 'Elegir fecha'
        : DateProposalInput(
                date: _date!,
                time: const TimeOfDay(hour: 0, minute: 0),
                placeName: '')
            .dateIso;
    final String timeLabel = _time == null
        ? 'Elegir hora'
        : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';
    final int remaining = _maxNote - _note.text.characters.length;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Proponer cita', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Sin reservas reales todavía: es una propuesta dentro del chat.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(dateLabel, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(timeLabel, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          if (_triedSubmit && (_date == null || _time == null))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Elige fecha y hora',
                  style:
                      TextStyle(color: theme.colorScheme.error, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _place,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Lugar (restaurante, café…)',
              border: const OutlineInputBorder(),
              errorText: _triedSubmit && _place.text.trim().isEmpty
                  ? 'Indica un lugar'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Dirección (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            minLines: 2,
            maxLength: _maxNote,
            buildCounter: (_,
                    {required int currentLength,
                    required bool isFocused,
                    int? maxLength}) =>
                Text('$remaining', style: theme.textTheme.bodySmall),
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              hintText: 'Ej: ¿Te viene bien cenar el viernes?',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('Enviar propuesta'),
          ),
        ],
      ),
    );
  }
}

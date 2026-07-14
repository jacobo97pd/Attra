import 'package:flutter/material.dart';

import '../data/safedate_service.dart';
import '../domain/trusted_contact.dart';

/// Hoja para crear un plan de cita segura desde el chat con un match. Recoge
/// lugar, fecha/hora, duración prevista y a qué contactos avisar. El plan es
/// PRIVADO del usuario: el match no lo ve ni sabe nada. Al crearlo, si la fase
/// de check-ins está activa, el backend programa los recordatorios.
class CreatePlanSheet extends StatefulWidget {
  const CreatePlanSheet({
    super.key,
    required this.uid,
    required this.chatId,
    required this.service,
    required this.otherName,
  });

  final String uid;
  final String chatId;
  final SafeDateService service;
  final String otherName;

  /// Abre la hoja y devuelve `true` si se creó un plan.
  static Future<bool> show(
    BuildContext context, {
    required String uid,
    required String chatId,
    required SafeDateService service,
    required String otherName,
  }) async {
    final bool? created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CreatePlanSheet(
        uid: uid,
        chatId: chatId,
        service: service,
        otherName: otherName,
      ),
    );
    return created ?? false;
  }

  @override
  State<CreatePlanSheet> createState() => _CreatePlanSheetState();
}

class _CreatePlanSheetState extends State<CreatePlanSheet> {
  final TextEditingController _placeCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  int _durationMinutes = 90;
  final Set<String> _selectedContactIds = <String>{};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _placeCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  DateTime? get _scheduledAt {
    if (_date == null || _time == null) return null;
    return DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 20, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    final String place = _placeCtrl.text.trim();
    final DateTime? when = _scheduledAt;
    if (place.isEmpty) {
      setState(() => _error = 'Indica el lugar de la cita.');
      return;
    }
    if (when == null) {
      setState(() => _error = 'Elige fecha y hora.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.createPlan(
        chatId: widget.chatId,
        placeName: place,
        scheduledAt: when,
        placeAddress: _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
        expectedDurationMinutes: _durationMinutes,
        trustedContactIds: _selectedContactIds.toList(growable: false),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on SafeDateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? when = _scheduledAt;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.shield_moon_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Planear cita segura',
                      style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Solo para ti. ${widget.otherName} no verá este plan ni tus '
              'contactos. Recomendamos un lugar público para una primera cita.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _placeCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Lugar',
                hintText: 'Ej. Café Central',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Dirección (opcional)',
                prefixIcon: Icon(Icons.map_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(_date == null
                        ? 'Fecha'
                        : '${_date!.day}/${_date!.month}/${_date!.year}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_time == null ? 'Hora' : _time!.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Duración prevista',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <int>[60, 90, 120, 180].map((int m) {
                final bool sel = _durationMinutes == m;
                return ChoiceChip(
                  label: Text(m < 120 ? '$m min' : '${m ~/ 60} h'),
                  selected: sel,
                  onSelected: (_) => setState(() => _durationMinutes = m),
                );
              }).toList(),
            ),
            if (when != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Regreso previsto sobre las '
                '${TimeOfDay.fromDateTime(when.add(Duration(minutes: _durationMinutes))).format(context)}.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(height: 16),
            Text('¿A quién avisar?',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Se les podrá avisar de forma prudente si no respondes a un '
              'check-in. Tú decides. Nunca se llama a nadie automáticamente.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<TrustedContact>>(
              stream: widget.service.observeTrustedContacts(widget.uid),
              builder: (BuildContext context,
                  AsyncSnapshot<List<TrustedContact>> snap) {
                final List<TrustedContact> contacts =
                    snap.data ?? const <TrustedContact>[];
                if (contacts.isEmpty) {
                  return Text(
                    'No tienes contactos de confianza. Puedes añadirlos en el '
                    'centro de SafeDate.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: contacts.map((TrustedContact c) {
                    final bool sel = _selectedContactIds.contains(c.id);
                    return FilterChip(
                      label: Text(c.displayName),
                      selected: sel,
                      onSelected: (bool v) => setState(() {
                        if (v) {
                          _selectedContactIds.add(c.id);
                        } else {
                          _selectedContactIds.remove(c.id);
                        }
                      }),
                    );
                  }).toList(),
                );
              },
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_busy ? 'Creando…' : 'Crear plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

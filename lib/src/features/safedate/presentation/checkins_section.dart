import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/safedate_service.dart';
import '../domain/safe_date_checkin.dart';
import '../domain/safe_date_plan.dart';
import '../domain/safedate_flags.dart';
import '../domain/trusted_contact.dart';
import 'active_date_screen.dart';

/// Sección de check-ins del centro SafeDate. Muestra las citas en curso o
/// próximas y sus check-ins pendientes, con respuesta en un toque. NUNCA llama a
/// nadie automáticamente: "Necesito ayuda" ofrece opciones (112, avisar a un
/// contacto) pero la acción siempre la inicia la persona.
class SafeDateCheckInsSection extends StatelessWidget {
  const SafeDateCheckInsSection({
    super.key,
    required this.uid,
    required this.service,
    required this.flags,
  });

  final String uid;
  final SafeDateService service;
  final SafeDateFlags flags;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SafeDatePlan>>(
      stream: service.observeMyPlans(uid),
      builder: (BuildContext context,
          AsyncSnapshot<List<SafeDatePlan>> snap) {
        final List<SafeDatePlan> open = (snap.data ?? const <SafeDatePlan>[])
            .where((SafeDatePlan p) => p.status.isOpen)
            .toList(growable: false);
        if (open.isEmpty) return const SizedBox.shrink();
        final ThemeData theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Tus citas',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final SafeDatePlan plan in open)
              _PlanCheckInsCard(
                plan: plan,
                service: service,
                uid: uid,
                flags: flags,
              ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }
}

class _PlanCheckInsCard extends StatelessWidget {
  const _PlanCheckInsCard({
    required this.plan,
    required this.service,
    required this.uid,
    required this.flags,
  });

  final SafeDatePlan plan;
  final SafeDateService service;
  final String uid;
  final SafeDateFlags flags;

  bool get _canOpenActive =>
      flags.liveLocationActive || flags.discreetAlertActive;

  String _when(BuildContext context) {
    final TimeOfDay t = TimeOfDay.fromDateTime(plan.scheduledAt);
    final String hm = t.format(context);
    final DateTime d = plan.scheduledAt;
    return '${d.day}/${d.month} · $hm';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.event_available_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(plan.placeName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(_when(context),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
            StreamBuilder<List<SafeDateCheckIn>>(
              stream: service.observeCheckIns(plan.id),
              builder: (BuildContext context,
                  AsyncSnapshot<List<SafeDateCheckIn>> snap) {
                final List<SafeDateCheckIn> items =
                    snap.data ?? const <SafeDateCheckIn>[];
                // Solo check-ins que requieren acción del usuario.
                final List<SafeDateCheckIn> actionable = items
                    .where((SafeDateCheckIn c) =>
                        c.status == CheckInStatus.pending ||
                        c.status == CheckInStatus.missed)
                    .toList(growable: false);
                if (actionable.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Sin check-ins pendientes.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  );
                }
                return Column(
                  children: <Widget>[
                    for (final SafeDateCheckIn c in actionable)
                      _CheckInRow(
                        checkIn: c,
                        planId: plan.id,
                        service: service,
                        uid: uid,
                        emergencyNumber: flags.emergencyNumber,
                      ),
                  ],
                );
              },
            ),
            if (_canOpenActive)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ActiveDateScreen(
                      uid: uid,
                      service: service,
                      plan: plan,
                      flags: flags,
                    ),
                  )),
                  icon: const Icon(Icons.shield_moon_outlined, size: 18),
                  label: const Text('Estoy en la cita'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const Map<String, String> _checkInLabels = <String, String>{
  'arrival': '¿Has llegado bien?',
  'during_date': '¿Va todo bien?',
  'expected_return': '¿Ya de vuelta a salvo?',
  'manual': '¿Todo bien?',
};

class _CheckInRow extends StatefulWidget {
  const _CheckInRow({
    required this.checkIn,
    required this.planId,
    required this.service,
    required this.uid,
    required this.emergencyNumber,
  });

  final SafeDateCheckIn checkIn;
  final String planId;
  final SafeDateService service;
  final String uid;
  final String emergencyNumber;

  @override
  State<_CheckInRow> createState() => _CheckInRowState();
}

class _CheckInRowState extends State<_CheckInRow> {
  bool _busy = false;

  Future<void> _respond(String response) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.respondCheckIn(
        planId: widget.planId,
        checkInId: widget.checkIn.id,
        response: response,
      );
    } on SafeDateException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool missed = widget.checkIn.status == CheckInStatus.missed;
    final String label =
        _checkInLabels[widget.checkIn.type.wireName] ?? _checkInLabels['manual']!;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(missed ? Icons.info_outline : Icons.schedule,
                  size: 16,
                  color: missed
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  missed ? '$label · sin responder' : label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: missed ? theme.colorScheme.error : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _respond('ok'),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Estoy bien'),
                ),
                TextButton(
                  onPressed: () => _respond('remind_later'),
                  child: const Text('Recuérdame luego'),
                ),
                TextButton(
                  onPressed: _openHelp,
                  style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error),
                  child: const Text('Necesito ayuda'),
                ),
              ],
            ),
          const Divider(height: 14),
        ],
      ),
    );
  }

  /// Hoja de "Necesito ayuda". Registra la petición (need_help) y ofrece
  /// opciones que SIEMPRE inicia la persona: llamar al 112 o avisar a un
  /// contacto de confianza. Nunca se llama a nadie automáticamente.
  Future<void> _openHelp() async {
    // Deja constancia sin bloquear la UI si falla la red.
    unawaited(_respond('need_help'));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final ThemeData theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(ctx).viewPadding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('¿Necesitas ayuda?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Tú decides. Puedes llamar a emergencias o avisar a una persona '
                'de confianza. Nada se hace de forma automática.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await launchUrl(
                      Uri(scheme: 'tel', path: widget.emergencyNumber));
                },
                style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error),
                icon: const Icon(Icons.emergency_outlined),
                label: Text('Llamar al ${widget.emergencyNumber}'),
              ),
              const SizedBox(height: 16),
              Text('Avisar a un contacto de confianza',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              StreamBuilder<List<TrustedContact>>(
                stream: widget.service.observeTrustedContacts(widget.uid),
                builder: (BuildContext context,
                    AsyncSnapshot<List<TrustedContact>> snap) {
                  final List<TrustedContact> contacts =
                      snap.data ?? const <TrustedContact>[];
                  if (contacts.isEmpty) {
                    return Text(
                      'No tienes contactos de confianza guardados.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    );
                  }
                  return Column(
                    children: <Widget>[
                      for (final TrustedContact c in contacts)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_outline),
                          title: Text(c.displayName),
                          subtitle: Text(c.phone ?? c.email ?? ''),
                          trailing: Wrap(
                            spacing: 4,
                            children: <Widget>[
                              if (c.phone != null)
                                IconButton(
                                  icon: const Icon(Icons.call_outlined),
                                  onPressed: () => launchUrl(
                                      Uri(scheme: 'tel', path: c.phone)),
                                ),
                              if (c.phone != null)
                                IconButton(
                                  icon: const Icon(Icons.sms_outlined),
                                  onPressed: () => launchUrl(
                                      Uri(scheme: 'sms', path: c.phone)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

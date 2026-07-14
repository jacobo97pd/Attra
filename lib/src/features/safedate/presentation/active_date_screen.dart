import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/safedate_service.dart';
import '../domain/safe_date_plan.dart';
import '../domain/safedate_flags.dart';

/// Pantalla de "cita en curso". Acciones discretas y control total del usuario:
/// compartir ubicación en directo (solo con consentimiento y temporal), pedir
/// que te llamen, "necesito salir", alerta silenciosa y acceso al 112. NUNCA se
/// informa al match ni se llama a nadie automáticamente. La ubicación se
/// comparte solo mientras esta pantalla está abierta y se borra al parar.
class ActiveDateScreen extends StatefulWidget {
  const ActiveDateScreen({
    super.key,
    required this.uid,
    required this.service,
    required this.plan,
    required this.flags,
  });

  final String uid;
  final SafeDateService service;
  final SafeDatePlan plan;
  final SafeDateFlags flags;

  @override
  State<ActiveDateScreen> createState() => _ActiveDateScreenState();
}

class _ActiveDateScreenState extends State<ActiveDateScreen> {
  bool _sharing = false;
  bool _busy = false;
  Timer? _locTimer;

  @override
  void initState() {
    super.initState();
    _sharing = widget.plan.liveLocationEnabled;
    if (_sharing) _startLocationTimer();
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    // Sin fondo: al cerrar la pantalla dejamos de actualizar y paramos la
    // sesión para no dejar una ubicación obsoleta sin refrescar (sin historial).
    if (_sharing) {
      widget.service.stopLiveLocation(widget.plan.id).catchError((_) {});
    }
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _startLocationTimer() {
    _locTimer?.cancel();
    _pushLocation(); // primer envío inmediato
    _locTimer = Timer.periodic(
        const Duration(seconds: 45), (_) => _pushLocation());
  }

  Future<void> _pushLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
      await widget.service.updateLiveLocation(
        widget.plan.id,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {
      /* best-effort: un fallo puntual no rompe la sesión */
    }
  }

  Future<void> _toggleSharing(bool value) async {
    if (_busy) return;
    if (value) {
      final bool ok = await _confirmLocationConsent();
      if (!ok) return;
      setState(() => _busy = true);
      try {
        await widget.service
            .startLiveLocation(widget.plan.id, consent: true);
        if (mounted) {
          setState(() => _sharing = true);
          _startLocationTimer();
        }
      } on SafeDateException catch (e) {
        _snack(e.message);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      setState(() => _busy = true);
      _locTimer?.cancel();
      try {
        await widget.service.stopLiveLocation(widget.plan.id);
        if (mounted) setState(() => _sharing = false);
      } on SafeDateException catch (e) {
        _snack(e.message);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirmLocationConsent() async {
    final ThemeData theme = Theme.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Compartir ubicación en directo'),
        content: Text(
          'Tu ubicación se compartirá de forma temporal mientras esta pantalla '
          'esté abierta y se borrará al pararla o terminar la cita. No hay '
          'historial y el match no la ve. ¿Continuar?',
          style: theme.textTheme.bodyMedium,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Acepto y compartir'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _sendAlert(String type, String feedback) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.sendAlert(widget.plan.id, type);
      _snack(feedback);
    } on SafeDateException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callEmergency() async {
    await launchUrl(Uri(scheme: 'tel', path: widget.flags.emergencyNumber));
  }

  Future<void> _finishDate() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Terminar cita'),
        content: const Text(
            'Se cerrará el seguimiento y se borrará la ubicación temporal.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Terminar')),
        ],
      ),
    );
    if (ok != true) return;
    _locTimer?.cancel();
    _sharing = false; // evita el stop duplicado en dispose
    try {
      await widget.service
          .setPlanStatus(widget.plan.id, SafeDatePlanStatus.completed);
      if (mounted) Navigator.of(context).pop();
    } on SafeDateException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SafeDateFlags flags = widget.flags;
    return Scaffold(
      appBar: AppBar(title: const Text('Cita en curso')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Icon(Icons.place_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(widget.plan.placeName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        if ((widget.plan.placeAddress ?? '').isNotEmpty)
                          Text(widget.plan.placeAddress!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ubicación en directo (opt-in, temporal).
          if (flags.liveLocationActive && !kIsWeb) ...<Widget>[
            Card(
              child: SwitchListTile(
                value: _sharing,
                onChanged: _busy ? null : _toggleSharing,
                secondary: Icon(Icons.my_location,
                    color: _sharing
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline),
                title: const Text('Compartir ubicación en directo'),
                subtitle: Text(_sharing
                    ? 'Compartiendo mientras esta pantalla esté abierta. Se '
                        'borrará al pararla.'
                    : 'Temporal y sin historial. Solo con tu permiso.'),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Acciones discretas.
          if (flags.discreetAlertActive) ...<Widget>[
            Text('Acciones discretas',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.phone_callback_outlined,
              title: 'Pedir que me llamen',
              subtitle: 'Deja constancia para tus contactos de confianza.',
              onTap: _busy
                  ? null
                  : () => _sendAlert('contact_me',
                      'Registrado. Puedes avisar a un contacto desde aquí.'),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.directions_walk_outlined,
              title: 'Necesito salir',
              subtitle: 'Marca esta cita como incómoda para tu seguimiento.',
              onTap: _busy
                  ? null
                  : () => _sendAlert(
                      'need_exit', 'Registrado. Cuídate; tú tienes el control.'),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.notifications_active_outlined,
              title: 'Alerta silenciosa',
              subtitle: 'Sin confirmaciones llamativas. El match no lo ve.',
              danger: true,
              onTap: _busy
                  ? null
                  : () => _sendAlert('silent_alert', 'Alerta silenciosa enviada.'),
            ),
            const SizedBox(height: 16),
          ],

          // Emergencias.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('¿Una emergencia?',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('SafeDate no sustituye a los servicios de emergencia.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _callEmergency,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  icon: const Icon(Icons.emergency_outlined),
                  label: Text('Llamar al ${flags.emergencyNumber}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _finishDate,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Terminar cita'),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        danger ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}

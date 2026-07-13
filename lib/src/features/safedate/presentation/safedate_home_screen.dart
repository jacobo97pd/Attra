import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/safedate_service.dart';
import '../domain/safedate_flags.dart';
import 'trusted_contacts_screen.dart';

/// Centro de Attra SafeDate. Tono calmado, control y privacidad. Sin falsas
/// garantías ("persona segura", "100% fiable"). Muestra acceso al número de
/// emergencias (112 en España) y deja claro que no sustituye a los servicios de
/// emergencia. Cada bloque aparece solo si su sub-flag está activa.
class SafeDateHomeScreen extends StatelessWidget {
  const SafeDateHomeScreen({
    super.key,
    required this.uid,
    required this.service,
    required this.flags,
  });

  final String uid;
  final SafeDateService service;
  final SafeDateFlags flags;

  Future<void> _callEmergency() async {
    final Uri uri = Uri(scheme: 'tel', path: flags.emergencyNumber);
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('SafeDate')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
        children: <Widget>[
          // Intro calmada + disclaimer honesto.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.shield_moon_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text('Queda con más tranquilidad',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tú decides qué compartir y durante cuánto tiempo. Para una '
                  'primera cita, recomendamos un lugar público. Puedes avisar a '
                  'una persona de confianza sin salir de Attra.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (flags.contactsActive) ...<Widget>[
            _SafeDateTile(
              icon: Icons.group_outlined,
              title: 'Contactos de confianza',
              subtitle: 'Personas a las que avisar. Privados: nadie más los ve.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    TrustedContactsScreen(uid: uid, service: service),
              )),
            ),
            const SizedBox(height: 10),
          ],

          if (flags.datePlanActive) ...<Widget>[
            _SafeDateTile(
              icon: Icons.event_available_outlined,
              title: 'Planear una cita segura',
              subtitle:
                  'Desde el chat con tu match: lugar, hora y a quién avisar.',
              onTap: null,
              trailing: Text('Desde el chat',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
            const SizedBox(height: 10),
          ],

          _SafeDateTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacidad y datos',
            subtitle: 'Qué se comparte, con quién y durante cuánto tiempo.',
            onTap: () => _showPrivacyInfo(context),
          ),
          const SizedBox(height: 20),

          // Emergencias: acceso directo al 112 + disclaimer.
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
                Text(
                  'SafeDate no sustituye a los servicios de emergencia.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
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
        ],
      ),
    );
  }

  void _showPrivacyInfo(BuildContext context) {
    showModalBottomSheet<void>(
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
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Tu privacidad', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final String line in const <String>[
                'Tu ubicación nunca se comparte por defecto: solo si tú la activas '
                    'y durante un tiempo limitado.',
                'La ubicación temporal se elimina al terminar la cita.',
                'Tus contactos de confianza son privados: el match no los ve ni '
                    'sabe si has enviado un aviso.',
                'No usamos estos datos para publicidad.',
                'Puedes eliminar tus datos de SafeDate cuando quieras.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.check_circle_outline,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SafeDateTile extends StatelessWidget {
  const _SafeDateTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
        onTap: onTap,
      ),
    );
  }
}

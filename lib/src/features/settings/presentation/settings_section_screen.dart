import 'package:flutter/material.dart';

import '../../../security/app_lock_controller.dart';
import '../../security/presentation/lock_screen.dart';
import '../domain/consent_record.dart';
import '../domain/setting_definition.dart';
import '../domain/settings_catalog.dart';
import 'settings_controller.dart';
import 'settings_icons.dart';

/// Renderiza una seccion concreta: toggles/enums (desde definiciones) y
/// acciones (botones). Es totalmente dirigida por el catalogo.
class SettingsSectionScreen extends StatefulWidget {
  const SettingsSectionScreen({
    super.key,
    required this.controller,
    required this.sectionKey,
  });

  final SettingsController controller;
  final String sectionKey;

  @override
  State<SettingsSectionScreen> createState() => _SettingsSectionScreenState();
}

class _SettingsSectionScreenState extends State<SettingsSectionScreen> {
  bool _busy = false;

  SettingsController get _c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final SettingsSection? section =
        SettingsCatalog.sectionByKey(widget.sectionKey);
    if (section == null) {
      return const Scaffold(
        body: Center(child: Text('Seccion no encontrada')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: AnimatedBuilder(
        animation:
            Listenable.merge(<Listenable>[_c, AppLockController.instance]),
        builder: (BuildContext context, _) {
          final List<Widget> children = <Widget>[];

          if (section.description.isNotEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  section.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            );
          }

          for (final SettingDefinition def in section.definitions) {
            if (!def.userVisible) continue;
            children.add(_buildSettingTile(context, def));
          }

          if (section.actions.isNotEmpty) {
            children.add(const SizedBox(height: 8));
            children.add(const Divider());
            for (final SettingsAction action in section.actions) {
              children.add(_buildActionTile(context, action));
            }
          }

          return ListView(children: children);
        },
      ),
    );
  }

  /// Cambia un toggle y, si era una integracion que fallo, muestra el error.
  Future<void> _onBoolChanged(SettingDefinition def, bool value) async {
    // Bloqueo de app: el PIN/biometría se gestionan en el dispositivo (flujo de
    // UI), no solo persistiendo un flag. El flag de Firestore es un espejo.
    if (def.key == 'security.appLock') {
      await _onAppLockChanged(value);
      return;
    }
    if (def.key == 'security.biometricUnlock') {
      await _onBiometricChanged(value);
      return;
    }
    // Instagram: en vez de la API de Meta, pide el @usuario y lo enlaza en el
    // perfil. Al tocar (on u off) abre el editor con el handle actual.
    if (def.key == 'integrations.instagram') {
      await _onInstagramTapped();
      return;
    }
    await _c.toggle(def, value);
    final String? error = _c.lastIntegrationError;
    if (error != null && mounted) {
      _c.lastIntegrationError = null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Editor del @usuario de Instagram (sin API de Meta). Vacío = desactiva.
  Future<void> _onInstagramTapped() async {
    final TextEditingController text =
        TextEditingController(text: _c.instagramHandle);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Tu Instagram'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
                'Escribe tu @usuario. Se mostrará como enlace en tu perfil. '
                'Déjalo vacío para quitarlo.'),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: '@',
                hintText: 'tu_usuario',
              ),
              onSubmitted: (String v) => Navigator.of(context).pop(v),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(text.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelado
    await _c.setInstagramHandle(result);
    _snack(_c.instagramHandle.isEmpty
        ? 'Instagram quitado del perfil.'
        : 'Instagram añadido a tu perfil.');
  }

  /// Activa/desactiva el PIN de la app (con confirmación). Persiste el espejo.
  Future<void> _onAppLockChanged(bool value) async {
    final AppLockController lock = AppLockController.instance;
    final SettingDefinition? def =
        SettingsCatalog.definitionByKey('security.appLock');
    if (value) {
      final bool ok = await runAppLockSetup(context, lock);
      if (ok && def != null) await _c.setValue(def, true);
      if (ok) _snack('Bloqueo con PIN activado.');
    } else {
      final bool ok = await confirmAppLockPin(context, lock);
      if (!ok) {
        _snack('PIN incorrecto. El bloqueo sigue activo.');
        return;
      }
      await lock.disable();
      if (def != null) await _c.setValue(def, false);
      final SettingDefinition? bio =
          SettingsCatalog.definitionByKey('security.biometricUnlock');
      if (bio != null) await _c.setValue(bio, false);
      _snack('Bloqueo desactivado.');
    }
  }

  /// Activa/desactiva el desbloqueo biométrico (requiere PIN ya configurado).
  Future<void> _onBiometricChanged(bool value) async {
    final AppLockController lock = AppLockController.instance;
    final SettingDefinition? def =
        SettingsCatalog.definitionByKey('security.biometricUnlock');
    if (value) {
      if (!lock.enabled) {
        _snack('Primero activa el "Bloqueo con PIN".');
        return;
      }
      if (!await lock.isBiometricAvailable()) {
        _snack('No hay biometría configurada en este dispositivo.');
        return;
      }
      if (!await lock.authenticateBiometric()) {
        _snack('No se pudo verificar la biometría.');
        return;
      }
      await lock.setBiometricEnabled(true);
      if (def != null) await _c.setValue(def, true);
    } else {
      await lock.setBiometricEnabled(false);
      if (def != null) await _c.setValue(def, false);
    }
  }

  // --- Tiles de ajuste ------------------------------------------------------

  Widget _buildSettingTile(BuildContext context, SettingDefinition def) {
    final EffectiveSetting eff = _c.effectiveFor(def);
    final List<Widget> badges = _badgesFor(def);

    switch (def.type) {
      case SettingType.boolean:
        final bool connecting = _c.isConnecting(def);
        // El bloqueo de app vive en el dispositivo: el switch refleja el estado
        // real del AppLockController, no solo el espejo de Firestore.
        final bool value = def.key == 'security.appLock'
            ? AppLockController.instance.enabled
            : def.key == 'security.biometricUnlock'
                ? AppLockController.instance.biometricEnabled
                : eff.boolValue;
        return SwitchListTile(
          value: value,
          onChanged: eff.locked || connecting
              ? null
              : (bool v) => _onBoolChanged(def, v),
          secondary: connecting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          title: _titleWithBadges(context, def.label, badges),
          subtitle: _subtitle(context, def, eff),
          isThreeLine: eff.locked || def.description.length > 60,
        );
      case SettingType.enumeration:
        return ListTile(
          enabled: !eff.locked,
          title: _titleWithBadges(context, def.label, badges),
          subtitle: _subtitle(context, def, eff),
          trailing: Text(
            _optionLabel(def, eff.stringValue),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          onTap: eff.locked ? null : () => _pickEnum(def, eff),
        );
      case SettingType.text:
      case SettingType.integer:
        return ListTile(
          enabled: !eff.locked,
          title: _titleWithBadges(context, def.label, badges),
          subtitle: _subtitle(context, def, eff),
          trailing: Text('${eff.value ?? ''}'),
        );
    }
  }

  Widget _titleWithBadges(
      BuildContext context, String label, List<Widget> badges) {
    if (badges.isEmpty) return Text(label);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: <Widget>[Text(label), ...badges],
    );
  }

  Widget _subtitle(
      BuildContext context, SettingDefinition def, EffectiveSetting eff) {
    // Instagram: muestra el @usuario guardado en lugar de la descripción genérica.
    final String desc =
        def.key == 'integrations.instagram' && _c.instagramHandle.isNotEmpty
            ? '@${_c.instagramHandle} · toca para editar'
            : def.description;
    final List<Widget> lines = <Widget>[
      Text(desc),
    ];
    if (eff.locked && eff.lockedReason != null) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.lock_outline,
                  size: 14, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  eff.lockedReason!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  List<Widget> _badgesFor(SettingDefinition def) {
    final List<Widget> badges = <Widget>[];
    if (def.requiresSubscription) {
      badges.add(const _Badge(label: 'Premium', color: Color(0xFFB8860B)));
    }
    if (def.requiresRegion != null) {
      badges.add(
          _Badge(label: def.requiresRegion!, color: const Color(0xFF1D6A96)));
    }
    if (def.scope == SettingScope.device) {
      badges.add(const _Badge(label: 'Dispositivo', color: Color(0xFF607D8B)));
    }
    return badges;
  }

  String _optionLabel(SettingDefinition def, String value) {
    for (final SettingOption o in def.options) {
      if (o.value == value) return o.label;
    }
    return value;
  }

  Future<void> _pickEnum(SettingDefinition def, EffectiveSetting eff) async {
    final String? chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(def.label,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final SettingOption o in def.options)
                ListTile(
                  title: Text(o.label),
                  trailing: o.value == eff.stringValue
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(o.value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen != null) {
      await _c.setValue(def, chosen);
    }
  }

  // --- Tiles de accion ------------------------------------------------------

  Widget _buildActionTile(BuildContext context, SettingsAction action) {
    final Color? color =
        action.destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(settingsIcon(action.icon), color: color),
      title: Text(action.label, style: TextStyle(color: color)),
      subtitle: Text(action.description),
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      onTap: _busy ? null : () => _runAction(action),
    );
  }

  Future<void> _runAction(SettingsAction action) async {
    switch (action.key) {
      case SettingsCatalog.actionExportData:
        await _confirmAndRun(
          title: 'Exportar mis datos',
          message:
              'Crearemos una copia de tus datos personales y te avisaremos '
              'cuando este lista.',
          confirmLabel: 'Solicitar',
          run: _c.requestDataExport,
        );
        break;
      case SettingsCatalog.actionDisableAccount:
        await _confirmAndRun(
          title: 'Pausar mi cuenta',
          message:
              'Tu perfil quedara oculto. Podras reactivarlo cuando quieras '
              'desde la seccion Privacidad.',
          confirmLabel: 'Pausar',
          run: _c.disableAccount,
        );
        break;
      case SettingsCatalog.actionDeleteAccount:
        await _confirmDelete();
        break;
      case SettingsCatalog.actionConsentHistory:
        await _openConsentHistory();
        break;
      case SettingsCatalog.actionChangeHistory:
        await _openChangeHistory();
        break;
    }
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<String> Function() run,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final String result = await run();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo completar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Esto eliminara tu cuenta y tus datos. Es una accion irreversible '
          'tras la ventana de seguridad. No cancela suscripciones contratadas '
          'por Apple o Google: gestionalas por separado.\n\n'
          'Si solo quieres descansar, considera "Pausar mi cuenta".',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _c.deleteAccount();
      // Tras borrar, la sesion cambia y el arbol se reconstruye solo.
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $error')),
        );
      }
    }
  }

  Future<void> _openConsentHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ConsentHistoryScreen(controller: _c),
      ),
    );
  }

  Future<void> _openChangeHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChangeHistoryScreen(controller: _c),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ConsentHistoryScreen extends StatelessWidget {
  const _ConsentHistoryScreen({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de consentimientos')),
      body: FutureBuilder<List<ConsentRecord>>(
        future: controller.loadConsentHistory(),
        builder: (BuildContext context,
            AsyncSnapshot<List<ConsentRecord>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<ConsentRecord> items = snapshot.data ?? <ConsentRecord>[];
          if (items.isEmpty) {
            return const Center(
                child: Text('Aun no hay consentimientos registrados.'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final ConsentRecord r = items[index];
              return ListTile(
                leading: Icon(
                  r.granted
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: r.granted ? Colors.green : Colors.redAccent,
                ),
                title: Text(r.purpose),
                subtitle: Text(
                  '${r.granted ? 'Otorgado' : 'Retirado'} · base: ${r.legalBasis}'
                  '${r.recordedAt != null ? ' · ${_fmt(r.recordedAt!)}' : ''}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChangeHistoryScreen extends StatelessWidget {
  const _ChangeHistoryScreen({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de cambios')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: controller.loadChangeHistory(),
        builder: (BuildContext context,
            AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<Map<String, dynamic>> items =
              snapshot.data ?? <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return const Center(child: Text('Sin cambios recientes.'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> e = items[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.edit_outlined, size: 18),
                title: Text('${e['settingKey'] ?? e['event'] ?? ''}'),
                subtitle: Text(
                  '${e['previousValue']} -> ${e['newValue']}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _fmt(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

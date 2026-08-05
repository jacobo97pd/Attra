import 'package:flutter/material.dart';

import '../../../../core/config/legal_links.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/theme_controller.dart';
import '../../../widgets/legal_links_row.dart';
import '../../anti_ghosting/presentation/busy_mode_sheet.dart';
import '../../tutorial/presentation/tutorial_screen.dart';
import '../domain/settings_catalog.dart';
import '../domain/setting_definition.dart';
import 'settings_controller.dart';
import 'settings_icons.dart';
import 'settings_section_screen.dart';

/// Pantalla raiz de Ajustes: apariencia (tema) + las 8 secciones del catalogo,
/// en un diseño moderno de tarjetas agrupadas con iconos de color.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    this.onSetThemeMode,
    this.busyModeFeatureEnabled = false,
    this.initialBusyUntil,
    this.onSetBusyMode,
  });

  final SettingsController controller;

  /// Cambia el modo de tema (claro/oscuro/sistema). Persiste en ajustes.
  final Future<void> Function(ThemeMode mode)? onSetThemeMode;

  /// Attra Clear §4: muestra la entrada de Modo ocupado si el flag está activo.
  final bool busyModeFeatureEnabled;
  final DateTime? initialBusyUntil;
  final Future<void> Function({
    required bool enabled,
    DateTime? until,
    String reason,
    bool visibleToMatches,
  })? onSetBusyMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Paleta de acentos para los iconos de las secciones (rota por orden).
  static const List<Color> _palette = <Color>[
    AppColors.aiViolet,
    AppColors.coral,
    AppColors.gold,
    AppColors.success,
    AppColors.nightBlue,
    AppColors.attraRed,
    AppColors.wine,
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  void _openSection(SettingsSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsSectionScreen(
          controller: widget.controller,
          sectionKey: section.key,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, _) {
        final bool showBusy =
            widget.busyModeFeatureEnabled && widget.onSetBusyMode != null;
        final List<SettingsSection> sections = SettingsCatalog.sections;
        final List<SettingsSection> normal = sections
            .where((SettingsSection s) => s.key != SettingsCatalog.secLifecycle)
            .toList(growable: false);
        SettingsSection? lifecycle;
        for (final SettingsSection s in sections) {
          if (s.key == SettingsCatalog.secLifecycle) lifecycle = s;
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
          children: <Widget>[
            const _SectionLabel('Personalización'),
            _ThemeCard(onSetThemeMode: widget.onSetThemeMode),
            const SizedBox(height: 22),
            const _SectionLabel('Ayuda y estado'),
            _Group(
              children: <Widget>[
                _NavRow(
                  icon: Icons.help_outline_rounded,
                  color: AppColors.nightBlue,
                  title: 'Cómo funciona Attra',
                  subtitle: 'Vuelve a ver el tutorial de bienvenida',
                  onTap: () => TutorialScreen.show(context),
                ),
                if (showBusy)
                  _BusyModeRow(
                    initialUntil: widget.initialBusyUntil,
                    onSetBusyMode: widget.onSetBusyMode!,
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionLabel('Ajustes'),
            _Group(
              children: <Widget>[
                for (int i = 0; i < normal.length; i++)
                  _NavRow(
                    icon: settingsIcon(normal[i].icon),
                    color: _palette[i % _palette.length],
                    title: normal[i].title,
                    subtitle: normal[i].description,
                    onTap: () => _openSection(normal[i]),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            // App Store Guidelines 1.2 y 3.1.2(c): el EULA y la política de
            // privacidad deben ser accesibles desde dentro de la app.
            const _SectionLabel('Legal y seguridad'),
            _Group(
              children: <Widget>[
                _NavRow(
                  icon: Icons.description_outlined,
                  color: AppColors.gold,
                  title: 'Condiciones de uso (EULA)',
                  subtitle:
                      'Normas de la comunidad, tolerancia cero y suscripciones',
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => AttraLegalLinksRow.openOrWarn(
                      context, LegalLinks.termsUrl),
                ),
                _NavRow(
                  icon: Icons.privacy_tip_outlined,
                  color: AppColors.nightBlue,
                  title: 'Política de privacidad',
                  subtitle: 'Qué datos tratamos y con qué finalidad',
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => AttraLegalLinksRow.openOrWarn(
                      context, LegalLinks.privacyUrl),
                ),
                _NavRow(
                  icon: Icons.shield_outlined,
                  color: AppColors.success,
                  title: 'Seguridad infantil',
                  subtitle: 'Nuestros estándares y cómo denunciar',
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => AttraLegalLinksRow.openOrWarn(
                      context, LegalLinks.childSafetyUrl),
                ),
                _NavRow(
                  icon: Icons.support_agent_outlined,
                  color: AppColors.coral,
                  title: 'Soporte',
                  subtitle: 'Contacto para incidencias y denuncias',
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => AttraLegalLinksRow.openOrWarn(
                      context, LegalLinks.supportUrl),
                ),
              ],
            ),
            if (lifecycle != null) ...<Widget>[
              const SizedBox(height: 22),
              const _SectionLabel('Cuenta y datos'),
              _Group(
                children: <Widget>[
                  _NavRow(
                    icon: settingsIcon(lifecycle.icon),
                    color: Theme.of(context).colorScheme.error,
                    title: lifecycle.title,
                    subtitle: lifecycle.description,
                    destructive: true,
                    onTap: () => _openSection(lifecycle!),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Etiqueta de grupo (pequeña, en mayúsculas suaves, sobre cada tarjeta).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Tarjeta que agrupa filas con separadores finos entre ellas.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: 62,
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// Fila de navegación: chip de icono con color + título + subtítulo + chevron.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: destructive ? theme.colorScheme.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.outline.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

/// Attra Clear §4: fila de Modo ocupado (estado optimista local para reflejar
/// el cambio al instante sin recargar la pantalla).
class _BusyModeRow extends StatefulWidget {
  const _BusyModeRow({required this.initialUntil, required this.onSetBusyMode});

  final DateTime? initialUntil;
  final Future<void> Function({
    required bool enabled,
    DateTime? until,
    String reason,
    bool visibleToMatches,
  }) onSetBusyMode;

  @override
  State<_BusyModeRow> createState() => _BusyModeRowState();
}

class _BusyModeRowState extends State<_BusyModeRow> {
  DateTime? _until;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final DateTime? u = widget.initialUntil;
    _until = (u != null && u.isAfter(DateTime.now())) ? u : null;
  }

  bool get _active => _until != null;

  Future<void> _toggle() async {
    if (_busy) return;
    if (_active) {
      setState(() => _busy = true);
      await widget.onSetBusyMode(enabled: false);
      if (mounted) {
        setState(() {
          _until = null;
          _busy = false;
        });
      }
      return;
    }
    final BusyModeChoice? choice = await BusyModeSheet.show(context);
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    await widget.onSetBusyMode(
      enabled: true,
      until: choice.until,
      visibleToMatches: choice.visibleToMatches,
    );
    if (mounted) {
      setState(() {
        _until = choice.until;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = _active ? AppColors.attraRed : AppColors.gold;
    final String subtitle = _active
        ? 'Activo hasta ${_fmt(_until!)} · toca para desactivar'
        : 'Pausa tu actividad y avisa suavemente a tus matches';
    return _NavRow(
      icon: Icons.bedtime_outlined,
      color: accent,
      title: 'Modo ocupado',
      subtitle: subtitle,
      onTap: _busy ? null : _toggle,
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : _active
              ? const Icon(Icons.toggle_on, color: AppColors.attraRed, size: 30)
              : null,
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Tarjeta "Apariencia": elige Sistema / Claro / Oscuro. Refleja el estado del
/// ThemeController (cambia al instante) y persiste vía [onSetThemeMode].
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({this.onSetThemeMode});

  final Future<void> Function(ThemeMode mode)? onSetThemeMode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (BuildContext context, ThemeMode mode, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.brightness_6_rounded,
                        size: 20, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Text('Apariencia',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 14),
              SegmentedButton<ThemeMode>(
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('Sistema')),
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('Claro')),
                  ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('Oscuro')),
                ],
                selected: <ThemeMode>{mode},
                showSelectedIcon: false,
                onSelectionChanged: onSetThemeMode == null
                    ? null
                    : (Set<ThemeMode> sel) => onSetThemeMode!(sel.first),
              ),
            ],
          ),
        );
      },
    );
  }
}

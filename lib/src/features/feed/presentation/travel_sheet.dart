import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../../geo/presentation/country_city_field.dart';

/// Hoja del MODO VIAJES (Plus/Pro): elige un destino para ver el feed de esa
/// parte del mundo y aparecer allí "de viaje". Si el usuario no es Plus/Pro,
/// muestra un muro hacia el paywall.
Future<void> showTravelSheet(
  BuildContext context, {
  required bool canUseTravelMode,
  required bool active,
  String? iso2,
  String? city,
  String? country,
  required Future<void> Function({
    required bool active,
    String iso2,
    String city,
    String country,
  }) onApply,
  VoidCallback? onUpgrade,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _TravelSheetBody(
      canUseTravelMode: canUseTravelMode,
      active: active,
      iso2: iso2,
      city: city,
      country: country,
      onApply: onApply,
      onUpgrade: onUpgrade,
    ),
  );
}

class _TravelSheetBody extends StatefulWidget {
  const _TravelSheetBody({
    required this.canUseTravelMode,
    required this.active,
    required this.onApply,
    this.iso2,
    this.city,
    this.country,
    this.onUpgrade,
  });

  final bool canUseTravelMode;
  final bool active;
  final String? iso2;
  final String? city;
  final String? country;
  final Future<void> Function({
    required bool active,
    String iso2,
    String city,
    String country,
  }) onApply;
  final VoidCallback? onUpgrade;

  @override
  State<_TravelSheetBody> createState() => _TravelSheetBodyState();
}

class _TravelSheetBodyState extends State<_TravelSheetBody> {
  String? _iso2;
  String? _country;
  String? _city;
  bool _busy = false;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _iso2 = widget.iso2;
    _country = widget.country;
    _city = widget.city;
    _active = widget.active;
  }

  bool get _hasDestination => (_country ?? '').trim().isNotEmpty;
  bool get _canActivate => _hasDestination && !_busy;

  /// Aplica el estado al backend. [close] cierra la hoja (botón); el toggle lo
  /// deja abierto para seguir ajustando el destino.
  Future<void> _apply(bool active, {bool close = true}) async {
    setState(() => _busy = true);
    try {
      await widget.onApply(
        active: active,
        iso2: _iso2 ?? '',
        city: active ? (_city ?? '') : '',
        country: active ? (_country ?? '') : '',
      );
      if (mounted && close) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Toggle maestro on/off del modo viajes.
  Future<void> _onToggle(bool value) async {
    setState(() => _active = value);
    if (!value) {
      // Apagar: desactiva el modo (vuelve a tu ubicación real).
      await _apply(false, close: false);
    } else if (_hasDestination) {
      // Encender con destino ya elegido: activa al instante.
      await _apply(true, close: false);
    }
    // Encender sin destino: deja el selector visible para elegir uno.
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                const Icon(Icons.travel_explore_rounded,
                    color: AppColors.attraRed, size: 24),
                const SizedBox(width: 10),
                Text('Modo viajes',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Cambia tu ubicación para ver quién hay en cualquier parte del '
              'mundo. Tu perfil aparecerá allí "de viaje".',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (!widget.canUseTravelMode)
              _UpsellWall(onUpgrade: widget.onUpgrade)
            else ...<Widget>[
              // Toggle maestro: enciende/apaga el modo viajes aparte del botón.
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.surfaceLine),
                ),
                child: SwitchListTile(
                  value: _active,
                  onChanged: _busy ? null : _onToggle,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  title: const Text('Modo viajes',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    _active
                        ? (_hasDestination
                            ? 'Activo · ${_city?.trim().isNotEmpty == true ? '${_city!.trim()}, ' : ''}${_country ?? ''}'
                            : 'Elige un destino abajo')
                        : 'Desactivado · usas tu ubicación real',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CountryCityField(
                label: 'Destino',
                initialCountryIso2: _iso2,
                initialCountryName: _country,
                initialCity: _city,
                onChanged: ({
                  required String? iso2,
                  required String? countryName,
                  required String? city,
                  required bool cityIsValid,
                }) {
                  setState(() {
                    _iso2 = iso2;
                    _country = countryName;
                    _city = city;
                  });
                },
              ),
              const SizedBox(height: 18),
              AttraPrimaryButton(
                label: _active ? 'Actualizar y ver' : 'Viajar aquí',
                icon: Icons.flight_takeoff_rounded,
                loading: _busy,
                onPressed: _canActivate ? () => _apply(true) : null,
              ),
              const SizedBox(height: 8),
              Text(
                'Solo cambia dónde te muestras y a quién ves. No comparte tu '
                'ubicación exacta.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Muro para Free: el modo viajes es Plus/Pro.
class _UpsellWall extends StatelessWidget {
  const _UpsellWall({required this.onUpgrade});
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.wine, AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Column(
        children: <Widget>[
          const Icon(Icons.public_rounded, size: 38, color: AppColors.attraRed),
          const SizedBox(height: 10),
          Text('El modo viajes es Plus y Pro',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'Hazte Plus o Pro para explorar y hacer match en cualquier ciudad '
            'del mundo antes de viajar.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          AttraPrimaryButton(
            label: 'Ver planes',
            icon: Icons.workspace_premium_rounded,
            onPressed: onUpgrade,
          ),
        ],
      ),
    );
  }
}

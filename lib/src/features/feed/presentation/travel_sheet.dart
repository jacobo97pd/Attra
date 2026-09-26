import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../../geo/domain/travel_destination_resolver.dart';
import '../../geo/presentation/country_city_field.dart';

/// Guarda (o apaga) el viaje. Devuelve si el destino se pudo situar en el
/// mapa (null = quien llama no lo sabe).
typedef TravelApply = Future<TravelApplyResult?> Function({
  required bool active,
  String iso2,
  String city,
  String country,
});

/// Hoja del MODO VIAJES (Plus/Pro): elige un destino para ver el feed de esa
/// parte del mundo y aparecer allí "de viaje". Si el usuario no es Plus/Pro,
/// muestra un muro hacia el paywall (y, si tenía un viaje puesto, el
/// interruptor para apagarlo: apagar nunca exige plan).
Future<void> showTravelSheet(
  BuildContext context, {
  required bool canUseTravelMode,
  required bool active,
  String? iso2,
  String? city,
  String? country,
  required TravelApply onApply,
  VoidCallback? onUpgrade,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
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
  final TravelApply onApply;
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

  /// La ciudad que llega guardada ya se validó al elegirla, así que se asume
  /// buena hasta que el campo diga lo contrario.
  bool _cityIsValid = true;

  @override
  void initState() {
    super.initState();
    _iso2 = widget.iso2;
    _country = widget.country;
    _city = widget.city;
    _active = widget.active;
  }

  bool get _hasDestination => (_country ?? '').trim().isNotEmpty;

  /// La ciudad es opcional (se puede viajar a un país entero), pero si se
  /// escribe tiene que existir: una ciudad inventada se publicaba tal cual en
  /// la ficha pública y además no ordenaba nada en el feed.
  bool get _cityIsUsable => (_city ?? '').trim().isEmpty || _cityIsValid;
  bool get _canActivate => _hasDestination && _cityIsUsable && !_busy;

  /// Aplica el estado al backend. [close] cierra la hoja (botón); el toggle lo
  /// deja abierto para seguir ajustando el destino. Si falla, lo muestra y
  /// revierte el toggle (no se queda "a medias" en silencio).
  ///
  /// Al APAGAR se mandan también país y ciudad: se conservan en el documento
  /// para que, al reabrir la hoja, el destino esté puesto y "Viajar aquí" no
  /// salga desactivado con un país que se ve elegido. Todo lo que mira el
  /// viaje exige `active`, así que conservarlos no publica nada.
  Future<void> _apply(bool active, {bool close = true}) async {
    setState(() => _busy = true);
    try {
      final TravelApplyResult? result = await widget.onApply(
        active: active,
        iso2: _iso2 ?? '',
        city: _city ?? '',
        country: _country ?? '',
      );
      if (!mounted) return;
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      final String city = (_city ?? '').trim();
      final String country = (_country ?? '').trim();
      final bool unlocated = active && result != null && !result.located;
      if (close) {
        Navigator.of(context).maybePop();
      }
      if (unlocated) {
        // El viaje se ha guardado igual, pero sin centro: el feed se queda en
        // el país con la ciudad delante. Mejor decirlo que dejar creer que
        // todo lo que sale es de la ciudad.
        messenger.showSnackBar(SnackBar(
          content: Text('No hemos podido situar $city en el mapa: verás gente '
              'de todo $country, con $city primero.'),
        ));
      } else if (!close) {
        messenger.showSnackBar(SnackBar(
          content: Text(
              active ? 'Modo viajes activado.' : 'Modo viajes desactivado.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _active = active ? false : true); // revierte el toggle
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar el modo viajes: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Toggle maestro on/off del modo viajes.
  Future<void> _onToggle(bool value) async {
    setState(() => _active = value);
    if (!value) {
      // Apagar: desactiva el modo (vuelve a tu ubicación real). Nunca exige
      // plan: con el plan caducado es la única salida del destino.
      await _apply(false, close: false);
    } else if (_hasDestination && _cityIsUsable && widget.canUseTravelMode) {
      // Encender con destino ya elegido Y válido: activa al instante. Antes el
      // interruptor no miraba la ciudad y publicaba tal cual una inventada
      // ("Cadizz") que el botón sí rechazaba.
      await _apply(true, close: false);
    }
    // Encender sin destino (o con una ciudad que no existe): deja el selector
    // visible para elegir uno; el subtítulo dice qué falta.
  }

  String get _subtitle {
    if (!_active) return 'Desactivado · usas tu ubicación real';
    if (!_hasDestination) return 'Elige un destino abajo';
    if (!_cityIsUsable) return 'Elige una ciudad de la lista';
    final String city = (_city ?? '').trim();
    return 'Activo · ${city.isNotEmpty ? '$city, ' : ''}${_country ?? ''}';
  }

  /// Interruptor maestro. [canTurnOn] = false cuando falta el plan: solo
  /// sirve para apagar un viaje que ya estaba puesto.
  Widget _toggleTile(ThemeData theme, {required bool canTurnOn}) {
    final bool enabled = !_busy && (canTurnOn || _active);
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: SwitchListTile(
        key: const ValueKey<String>('travel-toggle'),
        value: _active,
        onChanged: enabled
            ? (bool v) {
                if (v && !canTurnOn) return;
                _onToggle(v);
              }
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        title: const Text('Modo viajes',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          _subtitle,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.colors.textSecondary),
        ),
      ),
    );
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
                  color: context.colors.surfaceLine,
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
              'Elige una ciudad para ver a la gente de alrededor, en cualquier '
              'parte del mundo. Tu perfil aparecerá allí "de viaje" (y no en '
              'tu ciudad) mientras lo tengas activo.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (!widget.canUseTravelMode) ...<Widget>[
              // Sin plan (o con el plan caducado) el viaje NO se puede
              // encender, pero sí APAGAR: antes solo salía el muro y quien
              // tenía un viaje puesto no podía volver a su ciudad sin pagar.
              if (widget.active) ...<Widget>[
                _toggleTile(theme, canTurnOn: false),
                const SizedBox(height: 16),
              ],
              _UpsellWall(onUpgrade: widget.onUpgrade),
            ] else ...<Widget>[
              // Toggle maestro: enciende/apaga el modo viajes aparte del botón.
              _toggleTile(theme, canTurnOn: true),
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
                    // Sin esto se podía viajar a una ciudad inventada: el texto
                    // crudo acababa publicado como ciudad pública en el feed.
                    _cityIsValid = cityIsValid;
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
                    ?.copyWith(color: context.colors.textMuted),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.wine, context.colors.surface],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Column(
        children: <Widget>[
          const Icon(Icons.public_rounded, size: 38, color: AppColors.attraRed),
          const SizedBox(height: 10),
          Text('El modo viajes es Plus y Pro',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: context.colors.textPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'Hazte Plus o Pro para explorar y hacer match en cualquier ciudad '
            'del mundo antes de viajar.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: context.colors.textSecondary),
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../../auth/domain/app_user.dart';
import '../data/boost_service.dart';
import '../domain/boost.dart';

/// Hoja de consumibles: Boosts (visibilidad temporal) y Attra Swipes (likes
/// extra). Muestra saldos, permite ACTIVAR un Boost (consume saldo) y COMPRAR
/// más (placeholder de IAP). El Boost activo se ve en vivo con su temporizador.
Future<void> showBoostStoreSheet(
  BuildContext context, {
  required BoostService service,
  required AppUser? user,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BoostStoreBody(
      service: service,
      user: user,
      onChanged: onChanged,
    ),
  );
}

class _BoostStoreBody extends StatefulWidget {
  const _BoostStoreBody({
    required this.service,
    required this.user,
    this.onChanged,
  });

  final BoostService service;
  final AppUser? user;
  final VoidCallback? onChanged;

  @override
  State<_BoostStoreBody> createState() => _BoostStoreBodyState();
}

class _BoostStoreBodyState extends State<_BoostStoreBody> {
  bool _busy = false;
  int _boosts = 0;
  int _swipes = 0;

  @override
  void initState() {
    super.initState();
    _boosts = widget.user?.boostBalance ?? 0;
    _swipes = widget.user?.swipeBalance ?? 0;
  }

  String get _uid => widget.user?.uid ?? '';

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _activate(BoostType type) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final BoostActivationResult r = await widget.service.activateBoost(type: type);
      if (r.success) {
        setState(() => _boosts = r.remainingBoosts);
        _snack(type == BoostType.superboost
            ? '¡Superboost activado 24h!'
            : '¡Boost activado!');
        widget.onChanged?.call();
      } else if (r.status == 'no_balance') {
        _snack('No tienes Boosts. Compra uno abajo.');
      } else {
        _snack('No se pudo activar el Boost.');
      }
    } on BoostServiceException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(String kind, int amount) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final int balance =
          await widget.service.purchaseConsumable(kind: kind, amount: amount);
      setState(() {
        if (kind == 'boost') {
          _boosts = balance;
        } else {
          _swipes = balance;
        }
      });
      _snack('Compra realizada. Saldo: $balance');
      widget.onChanged?.call();
    } on BoostServiceException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            Text('Boosts y Swipes',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Más visibilidad y más likes cuando quieras.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),

            // Boost activo (en vivo) con temporizador.
            if (_uid.isNotEmpty)
              StreamBuilder<ActiveBoost?>(
                stream: widget.service.watchActiveBoost(_uid),
                builder: (_, AsyncSnapshot<ActiveBoost?> snap) {
                  final ActiveBoost? b = snap.data;
                  if (b == null) return const SizedBox.shrink();
                  return _ActiveBoostCard(boost: b);
                },
              ),

            // Saldos.
            Row(
              children: <Widget>[
                Expanded(
                    child: _BalanceTile(
                        icon: Icons.bolt_rounded,
                        label: 'Boosts',
                        value: _boosts)),
                const SizedBox(width: 12),
                Expanded(
                    child: _BalanceTile(
                        icon: Icons.swipe_rounded,
                        label: 'Swipes',
                        value: _swipes)),
              ],
            ),
            const SizedBox(height: 18),

            // Activar.
            Text('Activar Boost',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AttraPrimaryButton(
              label: 'Boost 30 min',
              icon: Icons.bolt_rounded,
              loading: _busy,
              onPressed:
                  _boosts > 0 && !_busy ? () => _activate(BoostType.boostNormal) : null,
            ),
            const SizedBox(height: 8),
            AttraSecondaryButton(
              label: 'Superboost 24h',
              onPressed:
                  _boosts > 0 && !_busy ? () => _activate(BoostType.superboost) : null,
            ),
            const SizedBox(height: 20),

            // Comprar (placeholder de IAP).
            Text('Comprar',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _BuyRow(
                label: '1 Boost',
                sub: 'Sube al frente del feed un rato',
                onTap: _busy ? null : () => _buy('boost', 1)),
            _BuyRow(
                label: '5 Boosts',
                sub: 'Pack ahorro',
                onTap: _busy ? null : () => _buy('boost', 5)),
            _BuyRow(
                label: '25 Attra Swipes',
                sub: 'Likes extra cuando se acaban los del día',
                onTap: _busy ? null : () => _buy('swipe', 25)),
            const SizedBox(height: 8),
            Text(
              'Compra de prueba (sin cargo). En producción se valida el pago real.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBoostCard extends StatefulWidget {
  const _ActiveBoostCard({required this.boost});
  final ActiveBoost boost;

  @override
  State<_ActiveBoostCard> createState() => _ActiveBoostCardState();
}

class _ActiveBoostCardState extends State<_ActiveBoostCard> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? exp = widget.boost.expiresAt;
    final Duration left =
        exp == null ? Duration.zero : exp.difference(DateTime.now());
    final int s = left.inSeconds < 0 ? 0 : left.inSeconds;
    final String mmss = left.inHours > 0
        ? '${left.inHours}h ${(left.inMinutes % 60)}m'
        : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppColors.action),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.bolt_rounded, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Boost activo — más visibilidad',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          Text(mmss,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: AppColors.attraRed),
          const SizedBox(height: 6),
          Text('$value',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _BuyRow extends StatelessWidget {
  const _BuyRow({required this.label, required this.sub, required this.onTap});
  final String label;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.add_circle_outline_rounded,
            color: AppColors.attraRed),
      ),
    );
  }
}

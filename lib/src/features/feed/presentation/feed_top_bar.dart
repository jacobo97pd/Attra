import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_backgrounds.dart';

/// Cabecera del feed al estilo Hinge.
///
/// Dos estados que ocupan el MISMO alto, para que la ficha no salte al pasar
/// de uno a otro:
/// - desplegada: la fila de filtros rápidos ([filters]);
/// - plegada: solo el nombre de la ficha que se está leyendo. Es lo que se ve
///   al bajar por un perfil, cuando los filtros ya no pintan nada y lo que
///   importa es saber de quién son las fotos.
class FeedTopBar extends StatelessWidget {
  const FeedTopBar({
    super.key,
    required this.collapsed,
    required this.title,
    required this.filters,
  });

  /// Alto útil de la barra, sin contar la zona de estado.
  static const double height = 52;

  final bool collapsed;
  final String title;
  final Widget filters;

  @override
  Widget build(BuildContext context) {
    final bool showTitle = collapsed && title.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: AttraAppShellBackground.contentColorOf(context),
        border: Border(
          bottom: BorderSide(
            color: showTitle ? context.colors.surfaceLine : Colors.transparent,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
              fit: StackFit.expand,
              children: <Widget>[...previous, if (current != null) current],
            ),
            child: showTitle
                ? _CollapsedTitle(
                    key: const ValueKey<String>('feed-top-bar-title'),
                    title: title,
                  )
                : KeyedSubtree(
                    key: const ValueKey<String>('feed-top-bar-filters'),
                    child: filters,
                  ),
          ),
        ),
      ),
    );
  }
}

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: Semantics(
          header: true,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

/// Fila de filtros: el botón de "todos los filtros" y los chips rápidos se
/// desplazan en horizontal; [trailing] (campana, directo…) queda fijo a la
/// derecha porque no son filtros y no deben perderse al desplazar.
class FeedFilterBar extends StatelessWidget {
  const FeedFilterBar({
    super.key,
    required this.activeCount,
    required this.onOpenAll,
    required this.chips,
    this.trailing = const <Widget>[],
  });

  /// Filtros activos en total (se pinta como contador sobre el botón).
  final int activeCount;
  final VoidCallback onOpenAll;
  final List<Widget> chips;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: ListView(
            key: const ValueKey<String>('feed-filter-bar'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 4, right: 12),
            children: <Widget>[
              Center(
                child: _AllFiltersButton(
                  activeCount: activeCount,
                  onPressed: onOpenAll,
                ),
              ),
              for (final Widget chip in chips)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Center(child: chip),
                ),
            ],
          ),
        ),
        ...trailing,
        if (trailing.isNotEmpty) const SizedBox(width: 4),
      ],
    );
  }
}

class _AllFiltersButton extends StatelessWidget {
  const _AllFiltersButton({required this.activeCount, required this.onPressed});

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        IconButton(
          tooltip: 'Filtros',
          icon: const Icon(Icons.tune),
          onPressed: onPressed,
        ),
        if (activeCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: CircleAvatar(
              radius: 8,
              backgroundColor: context.colors.accent,
              child: Text(
                '$activeCount',
                style: TextStyle(fontSize: 10, color: context.colors.onAccent),
              ),
            ),
          ),
      ],
    );
  }
}

/// Chip de filtro rápido. Relleno cuando el filtro está puesto, como en Hinge:
/// de un vistazo se sabe qué está recortando el feed sin abrir nada.
class FeedFilterChip extends StatelessWidget {
  const FeedFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
    this.icon,
    this.locked = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final IconData? icon;

  /// Filtro de pago sin el plan: lleva candado en vez de la flecha.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final AttraColors c = context.colors;
    final Color fg = active ? c.onAccent : c.textPrimary;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? c.accent : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: active ? c.accent : c.surfaceLine),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  locked
                      ? Icons.lock_outline_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: locked ? 14 : 18,
                  color: fg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Distintivo de Slow Dating. Antes iba junto al logo de la cabecera; sin
/// logo, va el primero de la fila de filtros, que es donde se entiende que
/// está cambiando qué perfiles salen.
class SlowDatingBadge extends StatelessWidget {
  const SlowDatingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: context.colors.accent.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.spa_rounded, size: 13, color: context.colors.accent),
          const SizedBox(width: 5),
          Text(
            'Slow Dating',
            style: TextStyle(
              color: context.colors.accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plegado vertical animado: esconde los avisos del feed junto con la fila de
/// filtros al bajar por una ficha.
class FeedCollapsible extends StatelessWidget {
  const FeedCollapsible({
    super.key,
    required this.collapsed,
    required this.child,
  });

  final bool collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        heightFactor: collapsed ? 0 : 1,
        child: child,
      ),
    );
  }
}

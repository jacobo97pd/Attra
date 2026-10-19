import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/attra_colors.dart';
import 'attra_glass.dart';

/// The same destinations and state, presented with each platform's tab control.
///
/// En el teléfono (no en el carril ancho) es una burbuja de vidrio flotante,
/// como el resto de controles desde la maqueta "Liquid Glass" del 19 de
/// octubre de 2026. Sigue siendo opaca cuando el sistema pide más contraste
/// (`MediaQuery.highContrastOf`): esa era la razón original de "nunca
/// comprometer las etiquetas", y sigue valiendo para quien lo necesita — el
/// vidrio es el añadido, no un reemplazo sin salida.
class AttraDestinationBar extends StatelessWidget {
  const AttraDestinationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.rail = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final bool rail;

  @override
  Widget build(BuildContext context) {
    if (rail) {
      return NavigationRail(
        backgroundColor: context.colors.surface,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labelType: NavigationRailLabelType.all,
        indicatorColor: context.colors.surfaceHigh,
        selectedIconTheme: IconThemeData(color: context.colors.textPrimary),
        unselectedIconTheme: IconThemeData(color: context.colors.textMuted),
        selectedLabelTextStyle: Theme.of(context).textTheme.labelMedium,
        unselectedLabelTextStyle: Theme.of(context).textTheme.bodySmall,
        destinations: <NavigationRailDestination>[
          for (final NavigationDestination destination in destinations)
            NavigationRailDestination(
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: Text(destination.label),
            ),
        ],
      );
    }
    final bool glass = !MediaQuery.highContrastOf(context);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // CupertinoTabScaffold normally applies this limit to its tab bar.
      // Here the bar lives in a Material Scaffold; content still scales fully.
      final Widget bar = MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1,
        child: CupertinoTabBar(
          currentIndex: selectedIndex,
          onTap: onDestinationSelected,
          backgroundColor: glass ? Colors.transparent : context.colors.surface,
          activeColor: context.colors.textPrimary,
          inactiveColor: context.colors.textMuted,
          border: glass
              ? null
              : Border(top: BorderSide(color: context.colors.surfaceLine)),
          height: 52,
          items: <BottomNavigationBarItem>[
            for (final NavigationDestination destination in destinations)
              BottomNavigationBarItem(
                icon: destination.icon,
                activeIcon: destination.selectedIcon ?? destination.icon,
                label: destination.label,
                tooltip: destination.tooltip,
              ),
          ],
        ),
      );
      return glass ? _GlassBarShell(child: bar) : bar;
    }
    final Widget bar = NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations,
      backgroundColor: glass ? Colors.transparent : null,
      surfaceTintColor: glass ? Colors.transparent : null,
      elevation: glass ? 0 : null,
      indicatorColor: glass ? Colors.white.withValues(alpha: 0.18) : null,
    );
    return glass ? _GlassBarShell(child: bar) : bar;
  }
}

/// Burbuja de vidrio flotante: el hueco que reserva el `Scaffold` para la
/// barra es un poco más alto que la propia píldora, con margen alrededor en
/// vez de tocar la estructura del `Scaffold` (`extendBody`), que habría
/// significado revisar el acolchado inferior de las cuatro pestañas en un
/// dispositivo real para que nada quedase tapado.
class _GlassBarShell extends StatelessWidget {
  const _GlassBarShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 8 + MediaQuery.viewPaddingOf(context).bottom),
      child: AttraGlassSurface(
        borderRadius: BorderRadius.circular(28),
        // El margen de abajo de este `Padding` YA cubre el indicador de
        // inicio/zona segura: si la barra de dentro también lo descontara,
        // el hueco se duplicaría y el contenido de los iconos quedaría más
        // apretado de lo necesario.
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: child,
        ),
      ),
    );
  }
}

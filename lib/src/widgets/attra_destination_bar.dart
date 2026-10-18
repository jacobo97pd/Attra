import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/attra_colors.dart';

/// The same destinations and state, presented with each platform's tab control.
/// Deliberately opaque: photos never compromise labels or require a blur effect.
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
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // CupertinoTabScaffold normally applies this limit to its tab bar.
      // Here the bar lives in a Material Scaffold; content still scales fully.
      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1,
        child: CupertinoTabBar(
          currentIndex: selectedIndex,
          onTap: onDestinationSelected,
          backgroundColor: context.colors.surface,
          activeColor: context.colors.textPrimary,
          inactiveColor: context.colors.textMuted,
          border: Border(top: BorderSide(color: context.colors.surfaceLine)),
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
    }
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations,
    );
  }
}

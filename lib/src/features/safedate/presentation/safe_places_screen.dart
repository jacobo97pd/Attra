import 'package:flutter/material.dart';

import '../data/safedate_service.dart';
import '../domain/safe_place.dart';

/// Lista de lugares públicos recomendados. Doble uso: informativo desde el
/// centro SafeDate, o selector al crear un plan (si [onPick] no es null).
/// NUNCA se etiqueta un lugar como "seguro al 100%".
class SafePlacesScreen extends StatelessWidget {
  const SafePlacesScreen({
    super.key,
    required this.service,
    this.onPick,
  });

  final SafeDateService service;
  final ValueChanged<SafePlace>? onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          title:
              Text(onPick != null ? 'Elegir lugar' : 'Lugares recomendados')),
      body: StreamBuilder<List<SafePlace>>(
        stream: service.observeSafePlaces(),
        builder: (BuildContext context, AsyncSnapshot<List<SafePlace>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<SafePlace> places = snap.data ?? const <SafePlace>[];
          if (places.isEmpty) {
            return _EmptyState(theme: theme);
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
            itemCount: places.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Sitios públicos donde muchas personas empiezan una primera '
                    'cita. Recomendados, no una garantía de seguridad.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                );
              }
              final SafePlace p = places[i - 1];
              return _PlaceCard(
                place: p,
                onTap: onPick == null
                    ? null
                    : () {
                        onPick!(p);
                        Navigator.of(context).pop();
                      },
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.onTap});

  final SafePlace place;
  final VoidCallback? onTap;

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
          child:
              Icon(Icons.local_cafe_outlined, color: theme.colorScheme.primary),
        ),
        title: Text(place.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (place.address.isNotEmpty) Text(place.address),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.verified_outlined,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(place.badgeLabel,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ),
              ],
            ),
          ],
        ),
        trailing: onTap != null ? const Icon(Icons.add_circle_outline) : null,
        isThreeLine: place.address.isNotEmpty,
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.place_outlined,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Todavía no hay lugares recomendados en tu zona',
                textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Mientras tanto, para una primera cita elige un sitio público y '
              'concurrido, y avisa a alguien de confianza.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../social/data/friend_group_service.dart';
import '../../social/data/social_discovery_service.dart';
import '../../social/domain/friend_group.dart';

/// Pantalla de Inicio "plan-first": la primera impresión de Attra ya no es un
/// swipe, sino planes, grupos y actividades. Todo lo demás (Personas, Chats,
/// citas) sigue accesible desde las pestañas; esto solo reencuadra la entrada.
class HomeLandingScreen extends StatelessWidget {
  const HomeLandingScreen({
    super.key,
    required this.uid,
    required this.displayName,
    required this.city,
    required this.interests,
    required this.onGoToPeople,
    required this.onGoToPlans,
    required this.onGoToChats,
    this.groupService,
    this.discoveryService,
    this.onOpenSafeDate,
    this.onOpenGroup,
    this.topBarActions = const <Widget>[],
  });

  final String uid;
  final String? displayName;
  final String city;
  final List<String> interests;

  final VoidCallback onGoToPeople;
  final VoidCallback onGoToPlans;
  final VoidCallback onGoToChats;

  final FriendGroupService? groupService;
  final SocialDiscoveryService? discoveryService;

  /// Escudo de SafeDate en la barra superior (si no es null y está activo).
  final VoidCallback? onOpenSafeDate;
  final void Function(FriendGroup group)? onOpenGroup;
  final List<Widget> topBarActions;

  static const List<_PlanCategory> _categories = <_PlanCategory>[
    _PlanCategory('Café', Icons.local_cafe_outlined),
    _PlanCategory('Cultura', Icons.museum_outlined),
    _PlanCategory('Aire libre', Icons.hiking_outlined),
    _PlanCategory('Cena', Icons.restaurant_outlined),
    _PlanCategory('Música', Icons.music_note_outlined),
    _PlanCategory('Otro', Icons.add),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = (displayName ?? '').trim();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Attra',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (city.trim().isNotEmpty) ...<Widget>[
              const SizedBox(width: 12),
              Icon(Icons.place_outlined,
                  size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 2),
              Text(city,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ],
        ),
        actions: <Widget>[
          if (onOpenSafeDate != null)
            IconButton(
              tooltip: 'SafeDate',
              icon: const Icon(Icons.shield_outlined),
              onPressed: onOpenSafeDate,
            ),
          ...topBarActions,
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
        children: <Widget>[
          Text(name.isEmpty ? 'Hola' : 'Hola, $name',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('¿Qué te apetece hacer?',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 14),

          // Categorías rápidas → llevan a explorar Planes.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories
                .map((_PlanCategory c) => ActionChip(
                      avatar: Icon(c.icon, size: 18),
                      label: Text(c.label),
                      onPressed: onGoToPlans,
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),

          // Tu próximo plan (primer grupo del que eres miembro).
          if (groupService != null)
            _NextPlan(
              uid: uid,
              service: groupService!,
              onOpenGroup: onOpenGroup,
              onGoToChats: onGoToChats,
              onGoToPlans: onGoToPlans,
            ),

          // Planes / grupos recomendados por afinidad.
          if (discoveryService != null)
            _Recommendations(
              uid: uid,
              service: discoveryService!,
              city: city,
              interests: interests,
              onOpenGroup: onOpenGroup,
              onSeeAll: onGoToPlans,
            ),

          const SizedBox(height: 8),
          const _SectionHeader(title: 'Personas con intereses comunes'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.people_alt_outlined,
                    color: theme.colorScheme.primary),
              ),
              title: const Text('Descubre personas afines'),
              subtitle: Text(interests.isEmpty
                  ? 'Basado en tus intereses y tu zona'
                  : interests.take(3).join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: onGoToPeople,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextPlan extends StatelessWidget {
  const _NextPlan({
    required this.uid,
    required this.service,
    required this.onOpenGroup,
    required this.onGoToChats,
    required this.onGoToPlans,
  });

  final String uid;
  final FriendGroupService service;
  final void Function(FriendGroup group)? onOpenGroup;
  final VoidCallback onGoToChats;
  final VoidCallback onGoToPlans;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return StreamBuilder<List<FriendGroup>>(
      stream: service.observeMyGroups(uid),
      builder:
          (BuildContext context, AsyncSnapshot<List<FriendGroup>> snap) {
        final List<FriendGroup> groups = snap.data ?? const <FriendGroup>[];
        if (groups.isEmpty) {
          // Sin plan aún: CTA para crear/unirse.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _SectionHeader(title: 'Tu próximo plan'),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(Icons.event_available_outlined,
                      color: theme.colorScheme.primary),
                  title: const Text('Aún no tienes planes'),
                  subtitle: const Text('Únete a un grupo o crea tu primer plan'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onGoToPlans,
                ),
              ),
              const SizedBox(height: 20),
            ],
          );
        }
        final FriendGroup g = groups.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SectionHeader(title: 'Tu próximo plan'),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(g.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Icon(Icons.place_outlined,
                            size: 15, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(g.city,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(width: 12),
                        Icon(Icons.group_outlined,
                            size: 15, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Text('${g.memberIds.length} personas',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () => onOpenGroup?.call(g),
                          child: const Text('Ver plan'),
                        ),
                        TextButton(
                          onPressed: onGoToChats,
                          child: const Text('Abrir chat'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _Recommendations extends StatelessWidget {
  const _Recommendations({
    required this.uid,
    required this.service,
    required this.city,
    required this.interests,
    required this.onOpenGroup,
    required this.onSeeAll,
  });

  final String uid;
  final SocialDiscoveryService service;
  final String city;
  final List<String> interests;
  final void Function(FriendGroup group)? onOpenGroup;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FutureBuilder<List<RecommendedGroup>>(
      future: service.recommendedGroups(
          uid: uid, city: city, myInterests: interests),
      builder: (BuildContext context,
          AsyncSnapshot<List<RecommendedGroup>> snap) {
        final List<RecommendedGroup> recs =
            snap.data ?? const <RecommendedGroup>[];
        if (recs.isEmpty) return const SizedBox.shrink();
        final RecommendedGroup best = recs.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionHeader(title: 'Planes para ti', onSeeAll: onSeeAll),
            const SizedBox(height: 8),
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int i) {
                  final FriendGroup g = recs[i].group;
                  return _PlanCard(
                    group: g,
                    onTap: () => onOpenGroup?.call(g),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Grupos que encajan contigo'),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.groups_outlined,
                      color: theme.colorScheme.primary),
                ),
                title: Text(best.group.name),
                subtitle: Text(
                    '${best.group.city} · ${best.group.memberIds.length} miembros'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenGroup?.call(best.group),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.group, required this.onTap});
  final FriendGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int free = group.maxMembers - group.memberIds.length;
    return SizedBox(
      width: 170,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(group.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(group.city,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 2),
                    Text(free > 0 ? '$free plazas' : 'Completo',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(title.toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: theme.colorScheme.outline)),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text('Ver todos',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
      ],
    );
  }
}

class _PlanCategory {
  const _PlanCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

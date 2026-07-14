import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../social/data/friend_group_service.dart';
import '../../social/data/social_discovery_service.dart';
import '../../social/domain/friend_group.dart';

/// Pantalla de Inicio "plan-first" (rediseño premium): planes, grupos y gente
/// como primera impresión, no un swipe. Todo lo demás sigue en sus pestañas.
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

  final VoidCallback? onOpenSafeDate;
  final void Function(FriendGroup group)? onOpenGroup;
  final List<Widget> topBarActions;

  static const List<({String label, IconData icon})> _categories =
      <({String label, IconData icon})>[
    (label: 'Café', icon: Icons.local_cafe_outlined),
    (label: 'Cultura', icon: Icons.museum_outlined),
    (label: 'Aire libre', icon: Icons.directions_run_rounded),
    (label: 'Cena', icon: Icons.restaurant_outlined),
    (label: 'Música', icon: Icons.music_note_rounded),
    (label: 'Otro', icon: Icons.add),
  ];

  @override
  Widget build(BuildContext context) {
    final String name = (displayName ?? '').trim();
    final String firstBits =
        name.isEmpty ? 'Hola' : 'Hola, $name';
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: <Widget>[
          // Fondo: negro Attra + resplandor rojo (más intenso) arriba-derecha,
          // justo donde está la campana de notificaciones.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.0, -1.0),
                  radius: 1.15,
                  colors: <Color>[
                    Color(0x80FF4F68),
                    Color(0x33D71945),
                    Color(0x000E0E10),
                  ],
                  stops: <double>[0.0, 0.28, 0.62],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 24 + MediaQuery.of(context).viewPadding.bottom),
              children: <Widget>[
                _topBar(context),
                const SizedBox(height: 18),
                Text(firstBits,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    )),
                const SizedBox(height: 4),
                const Text('¿Qué te apetece hacer?',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 16)),
                const SizedBox(height: 18),

                // Chips de categorías (2 filas × 3).
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _categories
                      .map((({String label, IconData icon}) c) =>
                          _CategoryChip(
                            label: c.label,
                            icon: c.icon,
                            onTap: onGoToPlans,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 26),

                if (groupService != null)
                  _NextPlanSection(
                    uid: uid,
                    service: groupService!,
                    onOpenGroup: onOpenGroup,
                    onGoToChats: onGoToChats,
                    onGoToPlans: onGoToPlans,
                  ),

                if (discoveryService != null)
                  _RecommendationsSection(
                    uid: uid,
                    service: discoveryService!,
                    city: city,
                    interests: interests,
                    onOpenGroup: onOpenGroup,
                    onSeeAll: onGoToPlans,
                  ),

                const _SectionLabel('Personas con intereses comunes'),
                const SizedBox(height: 10),
                _InfoCard(
                  icon: Icons.person_outline,
                  title: 'Descubre personas afines',
                  subtitle: interests.isEmpty
                      ? 'Basado en tus intereses y tu zona'
                      : interests.take(3).join(' · '),
                  onTap: onGoToPeople,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: <Widget>[
        const Text('Attra',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            )),
        if (city.trim().isNotEmpty) ...<Widget>[
          const SizedBox(width: 12),
          const Icon(Icons.place, size: 16, color: AppColors.attraRed),
          const SizedBox(width: 3),
          Text(city,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
        ],
        const Spacer(),
        if (onOpenSafeDate != null)
          IconButton(
            tooltip: 'SafeDate',
            onPressed: onOpenSafeDate,
            icon: const Icon(Icons.shield_outlined,
                color: AppColors.textPrimary),
          ),
        ...topBarActions,
      ],
    );
  }
}

// ─── Chip de categoría ──────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  const _CategoryChip(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 3 por fila con separaciones de 10 → (ancho - 20) / 3.
    final double w = (MediaQuery.of(context).size.width - 40 - 20) / 3;
    return SizedBox(
      width: w,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.surfaceLine),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 18, color: AppColors.attraRed),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Etiqueta de sección ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, {this.sparkle = false, this.onSeeAll});
  final String title;
  final bool sparkle;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            )),
        if (sparkle) ...<Widget>[
          const SizedBox(width: 6),
          const Icon(Icons.auto_awesome, size: 13, color: AppColors.attraRed),
        ],
        const Spacer(),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: const Row(
              children: <Widget>[
                Text('Ver todos',
                    style: TextStyle(
                        color: AppColors.attraRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, size: 18, color: AppColors.attraRed),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Sección "Tu próximo plan" ──────────────────────────────────────────────

class _NextPlanSection extends StatelessWidget {
  const _NextPlanSection({
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
    return StreamBuilder<List<FriendGroup>>(
      stream: service.observeMyGroups(uid),
      builder:
          (BuildContext context, AsyncSnapshot<List<FriendGroup>> snap) {
        final List<FriendGroup> groups = snap.data ?? const <FriendGroup>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SectionLabel('Tu próximo plan', sparkle: true),
            const SizedBox(height: 10),
            if (groups.isEmpty)
              _InfoCard(
                icon: Icons.event_available_outlined,
                title: 'Aún no tienes planes',
                subtitle: 'Únete a un grupo o crea tu primer plan',
                onTap: onGoToPlans,
              )
            else
              _NextPlanCard(
                group: groups.first,
                onView: () => onOpenGroup?.call(groups.first),
                onChat: onGoToChats,
              ),
            const SizedBox(height: 26),
          ],
        );
      },
    );
  }
}

class _NextPlanCard extends StatelessWidget {
  const _NextPlanCard(
      {required this.group, required this.onView, required this.onChat});
  final FriendGroup group;
  final VoidCallback onView;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final int members = group.memberIds.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _IconSquare(icon: Icons.event_note_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.place_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text(group.city,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                        const SizedBox(width: 12),
                        const Icon(Icons.group_outlined,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text('$members personas',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AvatarStack(count: members),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _GradientButton(label: 'Ver plan', onTap: onView),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OutlineButton(label: 'Abrir chat', onTap: onChat),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Icono en cuadrado redondeado con tinte rojo (como en el mockup).
class _IconSquare extends StatelessWidget {
  const _IconSquare({required this.icon, this.size = 46});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.attraRed.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: AppColors.attraRed, size: size * 0.5),
    );
  }
}

/// Pila de avatares superpuestos + "+N". Sin fotos reales: círculos con tinte.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final int shown = count.clamp(0, 2);
    final int extra = count - shown;
    return SizedBox(
      height: 32,
      width: shown == 0 ? 0 : (shown * 20.0 + (extra > 0 ? 22 : 12)),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int i = 0; i < shown; i++)
            Positioned(
              left: i * 20.0,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: AppColors.action),
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: const Icon(Icons.person,
                    size: 17, color: Colors.white),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown * 20.0,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.attraRed,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Text('+$extra',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: AppColors.action),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.attraRed, width: 1.4),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.attraRed,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ─── Sección "Planes para ti" ───────────────────────────────────────────────

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({
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
    return FutureBuilder<List<RecommendedGroup>>(
      future: service.recommendedGroups(
          uid: uid, city: city, myInterests: interests),
      builder: (BuildContext context,
          AsyncSnapshot<List<RecommendedGroup>> snap) {
        final List<RecommendedGroup> recs =
            snap.data ?? const <RecommendedGroup>[];
        if (recs.isEmpty) return const SizedBox.shrink();
        final FriendGroup best = recs.first.group;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SectionLabel('Planes para ti', onSeeAll: onSeeAll),
            const SizedBox(height: 12),
            SizedBox(
              height: 246,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: recs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (BuildContext context, int i) => _PlanImageCard(
                  group: recs[i].group,
                  index: i,
                  onTap: () => onOpenGroup?.call(recs[i].group),
                ),
              ),
            ),
            const SizedBox(height: 26),
            const _SectionLabel('Grupos que encajan contigo'),
            const SizedBox(height: 10),
            _InfoCard(
              icon: Icons.groups_outlined,
              title: best.name,
              subtitle: '${best.city} · ${best.memberIds.length} miembros',
              onTap: () => onOpenGroup?.call(best),
            ),
            const SizedBox(height: 26),
          ],
        );
      },
    );
  }
}

/// Paleta de gradientes para las cabeceras de las tarjetas de planes (no hay
/// fotos reales de grupo; se usa un gradiente premium + icono por categoría).
const List<List<Color>> _cardGradients = <List<Color>>[
  <Color>[Color(0xFF4A3B2A), Color(0xFF8A5A3A)], // atardecer/montaña
  <Color>[Color(0xFF3A1420), Color(0xFF6E1E30)], // cine (rojo)
  <Color>[Color(0xFF2E1E42), Color(0xFF5A2E62)], // vino/uva
  <Color>[Color(0xFF16303E), Color(0xFF2E5A66)], // agua/azul
  <Color>[Color(0xFF1E3A2A), Color(0xFF2E5A3E)], // naturaleza
];

IconData _iconForGroup(FriendGroup g) {
  final String s = '${g.name} ${g.interests.join(' ')}'.toLowerCase();
  bool has(List<String> k) => k.any(s.contains);
  if (has(<String>['sender', 'montaña', 'aire', 'natur', 'ruta'])) {
    return Icons.hiking_rounded;
  }
  if (has(<String>['cine', 'peli', 'film'])) {
    return Icons.movie_creation_outlined;
  }
  if (has(<String>['cena', 'tapas', 'gastro', 'comida', 'vino', 'restaur'])) {
    return Icons.restaurant_rounded;
  }
  if (has(<String>['mús', 'music', 'concier', 'directo'])) {
    return Icons.music_note_rounded;
  }
  if (has(<String>['café', 'cafe', 'brunch'])) return Icons.local_cafe_rounded;
  if (has(<String>['arte', 'museo', 'cultura', 'foto', 'expo'])) {
    return Icons.museum_outlined;
  }
  if (has(<String>['run', 'deporte', 'gym', 'fit', 'escalad', 'yoga'])) {
    return Icons.directions_run_rounded;
  }
  return Icons.groups_rounded;
}

class _PlanImageCard extends StatelessWidget {
  const _PlanImageCard(
      {required this.group, required this.index, required this.onTap});
  final FriendGroup group;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int free = group.maxMembers - group.memberIds.length;
    final List<Color> grad = _cardGradients[index % _cardGradients.length];
    return SizedBox(
      width: 186,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Cabecera "visual" (gradiente + icono grande + badge + guardar).
              SizedBox(
                height: 128,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: grad,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -8,
                      child: Icon(_iconForGroup(group),
                          size: 96,
                          color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(_iconForGroup(group),
                            size: 18, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Icon(Icons.bookmark_border_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(group.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              height: 1.15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.place_outlined,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(group.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.group_outlined,
                            size: 14, color: AppColors.attraRed),
                        const SizedBox(width: 4),
                        Text(free > 0 ? '$free plazas' : 'Completo',
                            style: const TextStyle(
                                color: AppColors.attraRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tarjeta informativa (grupos afines / personas) ─────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.surfaceLine),
          ),
          child: Row(
            children: <Widget>[
              _IconSquare(icon: icon, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

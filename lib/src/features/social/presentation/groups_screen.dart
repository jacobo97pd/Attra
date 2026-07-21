import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../profile/data/profile_summary_repository.dart';
import 'group_avatar.dart';
import 'group_chat_screen.dart';
import 'group_photo_picker.dart';
import '../../profile/domain/profile_summary.dart';
import '../data/friend_group_service.dart';
import '../data/social_discovery_service.dart';
import '../domain/friend_group.dart';

/// Modo Amigos — pantalla de grupos/planes: mis grupos + recomendados por
/// ciudad/intereses. Crear, solicitar unirse y (si eres creador) gestionar
/// solicitudes.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({
    super.key,
    required this.uid,
    required this.groupService,
    required this.discoveryService,
    required this.summaries,
    this.currentUserName = '',
    this.city = '',
    this.myInterests = const <String>[],
  });

  final String uid;
  final FriendGroupService groupService;
  final SocialDiscoveryService discoveryService;
  final ProfileSummaryRepository summaries;
  final String currentUserName;
  final String city;
  final List<String> myInterests;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late Future<List<RecommendedGroup>> _recommended;

  @override
  void initState() {
    super.initState();
    _recommended = _loadRecommended();
  }

  Future<List<RecommendedGroup>> _loadRecommended() {
    return widget.discoveryService.recommendedGroups(
      uid: widget.uid,
      city: widget.city,
      myInterests: widget.myInterests,
    );
  }

  void _refresh() => setState(() => _recommended = _loadRecommended());

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _create() async {
    final _NewGroupInput? input =
        await _CreateGroupSheet.show(context, widget.city);
    if (input == null) return;
    try {
      final String groupId = await widget.groupService.createGroup(
        name: input.name,
        description: input.description,
        city: input.city,
        interests: input.interests,
        maxMembers: input.maxMembers,
      );
      // Foto elegida al crear (preset o subida). Best-effort: no bloquea la
      // creación si falla.
      final GroupPhotoChoice? photo = input.photoChoice;
      if (groupId.isNotEmpty && photo != null) {
        try {
          if (photo.isPreset) {
            await widget.groupService.setGroupPreset(groupId, photo.presetValue!);
          } else if (photo.bytes != null) {
            await widget.groupService.updateGroupPhoto(
              groupId,
              uid: widget.uid,
              bytes: photo.bytes!,
              contentType: photo.contentType,
            );
          }
        } catch (_) {/* la foto es opcional */}
      }
      _snack('Grupo creado ✨');
      _refresh();
    } on FriendGroupException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _openGroup(FriendGroup g) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GroupDetailSheet(
        group: g,
        uid: widget.uid,
        userName: widget.currentUserName,
        service: widget.groupService,
        summaries: widget.summaries,
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.black,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _CreateGroupButton(onTap: _create),
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-1.0, -1.0),
                  radius: 1.2,
                  colors: <Color>[Color(0x33FF4F68), Color(0x000E0E10)],
                  stops: <double>[0.0, 0.55],
                ),
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                children: <Widget>[
                  _header(context, canPop),
                  const SizedBox(height: 22),

                  // ── Tus grupos ──
                  const _SectionHeader(
                      icon: Icons.groups_rounded, title: 'Tus grupos'),
                  const SizedBox(height: 12),
                  StreamBuilder<List<FriendGroup>>(
                    stream: widget.groupService.observeMyGroups(widget.uid),
                    builder: (BuildContext context,
                        AsyncSnapshot<List<FriendGroup>> snap) {
                      if (snap.hasError) {
                        return _ErrorNote(
                          'No se pudieron cargar tus grupos: ${snap.error}',
                          onRetry: _refresh,
                        );
                      }
                      final List<FriendGroup> mine =
                          snap.data ?? const <FriendGroup>[];
                      if (mine.isEmpty) {
                        return const _EmptyLine(
                            'Aún no estás en ningún grupo.');
                      }
                      return Column(
                        children: <Widget>[
                          for (final FriendGroup g in mine)
                            _MyGroupTile(
                              group: g,
                              uid: widget.uid,
                              onTap: () => _openGroup(g),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 26),

                  // ── Recomendados para ti ──
                  const _SectionHeader(
                      icon: Icons.auto_awesome,
                      title: 'Recomendados para ti',
                      filledIcon: true),
                  const SizedBox(height: 12),
                  FutureBuilder<List<RecommendedGroup>>(
                    future: _recommended,
                    builder: (BuildContext context,
                        AsyncSnapshot<List<RecommendedGroup>> snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.attraRed)),
                        );
                      }
                      if (snap.hasError) {
                        return _ErrorNote(
                          'No se pudieron cargar los grupos: ${snap.error}',
                          onRetry: _refresh,
                        );
                      }
                      final List<RecommendedGroup> recs =
                          snap.data ?? const <RecommendedGroup>[];
                      if (recs.isEmpty) {
                        return const _EmptyLine(
                            'No hay grupos abiertos por aquí todavía.');
                      }
                      return Column(
                        children: <Widget>[
                          for (final RecommendedGroup r in recs)
                            _RecommendedTile(
                              group: r.group,
                              onTap: () => _openGroup(r.group),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool canPop) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (canPop)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.arrow_back,
                        color: AppColors.textPrimary),
                  ),
                ),
              const Text('Planes',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 4),
              const Text('Explora grupos y planes para hacer cosas increíbles.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 15, height: 1.3)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _RoundAddButton(onTap: _create),
      ],
    );
  }
}

/// Icono rojo tintado en cuadrado redondeado (avatar de grupo/categoría).
IconData groupCategoryIcon(FriendGroup g) {
  final String s = '${g.name} ${g.interests.join(' ')}'.toLowerCase();
  bool has(List<String> k) => k.any(s.contains);
  if (has(<String>['sender', 'montaña', 'aire', 'natur', 'ruta'])) {
    return Icons.hiking_rounded;
  }
  if (has(<String>['cine', 'peli', 'film'])) {
    return Icons.movie_creation_outlined;
  }
  if (has(<String>['escalad', 'boulder'])) return Icons.terrain_rounded;
  if (has(<String>['cena', 'tapas', 'gastro', 'comida', 'vino', 'restaur'])) {
    return Icons.restaurant_rounded;
  }
  if (has(<String>['mús', 'music', 'concier', 'directo'])) {
    return Icons.music_note_rounded;
  }
  if (has(<String>['café', 'cafe', 'brunch'])) return Icons.local_cafe_rounded;
  if (has(<String>['foto'])) return Icons.photo_camera_outlined;
  if (has(<String>['arte', 'museo', 'cultura', 'expo'])) {
    return Icons.museum_outlined;
  }
  if (has(<String>['run', 'deporte', 'gym', 'fit', 'yoga'])) {
    return Icons.directions_run_rounded;
  }
  return Icons.groups_rounded;
}

/// Botón redondo "+" con glow y destellos (esquina superior de la cabecera).
class _RoundAddButton extends StatelessWidget {
  const _RoundAddButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          const Positioned(
              right: 2,
              top: 0,
              child: Icon(Icons.auto_awesome,
                  size: 14, color: AppColors.attraRed)),
          const Positioned(
              left: 4,
              bottom: 8,
              child: Icon(Icons.auto_awesome,
                  size: 10, color: AppColors.attraRed)),
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: AppColors.action),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: AppColors.attraRed.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón "Crear grupo" (píldora con gradiente y glow) flotante inferior.
class _CreateGroupButton extends StatelessWidget {
  const _CreateGroupButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: AppColors.attraRed.withValues(alpha: 0.45),
              blurRadius: 22,
              spreadRadius: 1),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.action),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.add, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text('Crear grupo',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.title, this.filledIcon = false});
  final IconData icon;
  final String title;
  final bool filledIcon;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: AppColors.attraRed, size: filledIcon ? 22 : 24),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        const Row(
          children: <Widget>[
            Text('Ver todos',
                style: TextStyle(
                    color: AppColors.attraRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Icon(Icons.chevron_right, size: 18, color: AppColors.attraRed),
          ],
        ),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 14)),
      );
}

/// Tarjeta de "Tus grupos": icono, nombre + rol, ubicación/aforo/intereses,
/// avatares y check. El grupo del que eres admin se resalta con borde rojo.
class _MyGroupTile extends StatelessWidget {
  const _MyGroupTile(
      {required this.group, required this.uid, required this.onTap});
  final FriendGroup group;
  final String uid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool admin = group.createdBy == uid;
    final String? role =
        admin ? 'Eres admin' : (group.isMember(uid) ? 'Eres miembro' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: admin
            ? AppColors.attraRed.withValues(alpha: 0.06)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: admin
                      ? AppColors.attraRed.withValues(alpha: 0.8)
                      : AppColors.surfaceLine),
            ),
            child: Row(
              children: <Widget>[
                GroupAvatar(photoUrl: group.photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (role != null) ...<Widget>[
                            const SizedBox(width: 8),
                            _RolePill(role),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      _MetaLine(group: group),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _MiniAvatars(count: group.memberCount),
                const SizedBox(width: 8),
                Icon(Icons.check_circle_outline,
                    color: AppColors.attraRed.withValues(alpha: 0.9)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendedTile extends StatelessWidget {
  const _RecommendedTile({required this.group, required this.onTap});
  final FriendGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
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
                GroupAvatar(
                    photoUrl: group.photoUrl,
                    fallbackIcon: groupCategoryIcon(group)),
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
                      _MetaLine(group: group),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Línea "Madrid · 2/8 · intereses" con el punto separador en rojo.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.group});
  final FriendGroup group;
  @override
  Widget build(BuildContext context) {
    const TextStyle base =
        TextStyle(color: AppColors.textSecondary, fontSize: 13);
    Widget dot() => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('·',
              style: TextStyle(
                  color: AppColors.attraRed,
                  fontSize: 15,
                  fontWeight: FontWeight.w900)),
        );
    return Row(
      children: <Widget>[
        const Icon(Icons.place_outlined, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(group.city.isEmpty ? '—' : group.city, style: base),
        dot(),
        const Icon(Icons.group_outlined, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text('${group.memberCount}/${group.maxMembers}', style: base),
        if (group.interests.isNotEmpty) ...<Widget>[
          dot(),
          Flexible(
            child: Text(group.interests.take(2).join(', '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: base),
          ),
        ],
      ],
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.attraRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: const TextStyle(
              color: AppColors.attraRed,
              fontSize: 11.5,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// Pila de avatares (placeholder con tinte; los grupos no guardan fotos).
class _MiniAvatars extends StatelessWidget {
  const _MiniAvatars({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final int shown = count.clamp(0, 2);
    final int extra = count - shown;
    if (shown == 0) return const SizedBox.shrink();
    return SizedBox(
      height: 30,
      width: shown * 19.0 + (extra > 0 ? 22 : 11),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int i = 0; i < shown; i++)
            Positioned(
              left: i * 19.0,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: AppColors.action),
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: const Icon(Icons.person, size: 16, color: Colors.white),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown * 19.0,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.attraRed,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Text('+$extra',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nota de error visible (en vez de vacío silencioso) para diagnosticar fallos
/// de reglas/índices al cargar grupos.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message, {this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
            ],
          ),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupDetailSheet extends StatefulWidget {
  const _GroupDetailSheet({
    required this.group,
    required this.uid,
    required this.userName,
    required this.service,
    required this.summaries,
  });

  final FriendGroup group;
  final String uid;
  final String userName;
  final FriendGroupService service;
  final ProfileSummaryRepository summaries;

  @override
  State<_GroupDetailSheet> createState() => _GroupDetailSheetState();
}

class _GroupDetailSheetState extends State<_GroupDetailSheet> {
  bool _busy = false;
  bool _uploadingPhoto = false;

  Future<void> _pickPhoto(FriendGroup g) async {
    if (_uploadingPhoto) return;
    final GroupPhotoChoice? choice = await GroupPhotoPickerSheet.show(context);
    if (choice == null || !mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      if (choice.isPreset) {
        await widget.service.setGroupPreset(g.id, choice.presetValue!);
      } else if (choice.bytes != null) {
        await widget.service.updateGroupPhoto(
          g.id,
          uid: widget.uid,
          bytes: choice.bytes!,
          contentType: choice.contentType,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto del grupo actualizada')));
      }
    } on FriendGroupException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo actualizar la foto.')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMsg)));
        Navigator.of(context).pop();
      }
    } on FriendGroupException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Estado en vivo del grupo (para ver solicitudes al momento si soy admin).
    return StreamBuilder<FriendGroup?>(
      stream: widget.service.observeGroup(widget.group.id),
      initialData: widget.group,
      builder: (BuildContext context, AsyncSnapshot<FriendGroup?> snap) {
        final FriendGroup g = snap.data ?? widget.group;
        final bool admin = g.isAdmin(widget.uid);
        final bool member = g.isMember(widget.uid);
        final bool pending = g.isPending(widget.uid);
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Avatar del grupo (editable si soy el creador).
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      GroupAvatar(
                        photoUrl: g.photoUrl,
                        size: 60,
                        circle: true,
                      ),
                      if (_uploadingPhoto)
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0x99000000),
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      if (admin && !_uploadingPhoto)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: GestureDetector(
                            onTap: () => _pickPhoto(g),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.attraRed,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(g.name, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          <String>[
                            if (g.city.isNotEmpty) g.city,
                            '${g.memberCount}/${g.maxMembers} miembros',
                            g.status.wireName,
                          ].join('  ·  '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                        if (admin) ...<Widget>[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap:
                                _uploadingPhoto ? null : () => _pickPhoto(g),
                            child: Text(
                                g.hasPhoto ? 'Cambiar foto' : 'Añadir foto',
                                style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (g.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(g.description, style: theme.textTheme.bodyMedium),
              ],
              if (g.interests.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final String i in g.interests) Chip(label: Text(i)),
                  ],
                ),
              ],
              // Admin: solicitudes pendientes (con nombre + foto).
              if (admin && g.pendingIds.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Text('Solicitudes', style: theme.textTheme.titleSmall),
                for (final String reqUid in g.pendingIds)
                  _PersonRow(
                    uid: reqUid,
                    summaries: widget.summaries,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                    () => widget.service.respondJoin(
                                      groupId: g.id,
                                      targetUid: reqUid,
                                      accept: false,
                                    ),
                                    'Solicitud rechazada',
                                  ),
                          child: const Text('Rechazar'),
                        ),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                    () => widget.service.respondJoin(
                                      groupId: g.id,
                                      targetUid: reqUid,
                                      accept: true,
                                    ),
                                    'Solicitud aceptada',
                                  ),
                          child: const Text('Aceptar'),
                        ),
                      ],
                    ),
                  ),
              ],
              // Miembros (con nombre + foto).
              const SizedBox(height: 14),
              Text('Miembros (${g.memberCount})',
                  style: theme.textTheme.titleSmall),
              for (final String memberUid in g.memberIds)
                _PersonRow(
                  uid: memberUid,
                  summaries: widget.summaries,
                  trailing: memberUid == g.createdBy
                      ? Text('Admin',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700))
                      : (memberUid == widget.uid
                          ? Text('Tú',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline))
                          : null),
                ),
              // Chat del grupo: disponible para miembros.
              if (member) ...<Widget>[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => GroupChatScreen(
                        groupId: g.id,
                        groupName: g.name,
                        groupPhotoUrl: g.photoUrl,
                        currentUid: widget.uid,
                        currentUserName: widget.userName,
                        service: widget.service,
                      ),
                    )),
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('Abrir chat'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Acción principal según mi relación con el grupo.
              if (admin)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.service.closeGroup(g.id),
                          'Grupo cerrado'),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Cerrar grupo'),
                )
              else if (member)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.service.leaveGroup(g.id),
                          'Has salido del grupo'),
                  icon: const Icon(Icons.logout),
                  label: const Text('Salir del grupo'),
                )
              else if (pending)
                const Text('Solicitud enviada. Espera la respuesta del creador.')
              else
                FilledButton.icon(
                  onPressed: (!g.isJoinable || _busy)
                      ? null
                      : () => _run(() => widget.service.requestJoin(g.id),
                          'Solicitud enviada'),
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(g.isJoinable ? 'Solicitar unirse' : 'No disponible'),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Fila de persona (miembro o solicitante) con nombre + foto resueltos vía
/// ProfileSummaryRepository (discovery → seed_profiles). Cae a "Alguien" si no
/// se resuelve.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.uid,
    required this.summaries,
    this.trailing,
  });

  final String uid;
  final ProfileSummaryRepository summaries;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FutureBuilder<ProfileSummary>(
      future: summaries.fetch(uid),
      initialData: summaries.peek(uid),
      builder: (BuildContext context, AsyncSnapshot<ProfileSummary> snap) {
        final ProfileSummary? s = snap.data;
        final String name = s?.displayName ?? 'Alguien';
        final String photo = s?.photoUrl ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                backgroundImage:
                    photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(color: theme.colorScheme.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        );
      },
    );
  }
}

class _NewGroupInput {
  const _NewGroupInput({
    required this.name,
    required this.description,
    required this.city,
    required this.interests,
    required this.maxMembers,
    this.photoChoice,
  });
  final String name;
  final String description;
  final String city;
  final List<String> interests;
  final int maxMembers;
  final GroupPhotoChoice? photoChoice;
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({required this.initialCity});
  final String initialCity;

  static Future<_NewGroupInput?> show(BuildContext context, String city) {
    return showModalBottomSheet<_NewGroupInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateGroupSheet(initialCity: city),
    );
  }

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _interests = TextEditingController();
  double _maxMembers = 8;
  bool _tried = false;
  GroupPhotoChoice? _photoChoice;

  Future<void> _pickGroupPhoto() async {
    final GroupPhotoChoice? choice = await GroupPhotoPickerSheet.show(context);
    if (choice != null && mounted) setState(() => _photoChoice = choice);
  }

  @override
  void initState() {
    super.initState();
    _city.text = widget.initialCity;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _city.dispose();
    _interests.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _tried = true);
    if (_name.text.trim().isEmpty) return;
    final List<String> interests = _interests.text
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
    Navigator.of(context).pop(_NewGroupInput(
      name: _name.text.trim(),
      description: _desc.text.trim(),
      city: _city.text.trim(),
      interests: interests,
      maxMembers: _maxMembers.round(),
      photoChoice: _photoChoice,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Crear grupo', style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            // Foto del grupo (preset o subida). Opcional.
            Center(
              child: GestureDetector(
                onTap: _pickGroupPhoto,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        _photoChoice?.bytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.memory(_photoChoice!.bytes!,
                                    width: 72, height: 72, fit: BoxFit.cover),
                              )
                            : GroupAvatar(
                                photoUrl: _photoChoice?.presetValue ?? '',
                                size: 72,
                                radius: 18),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppColors.attraRed,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: theme.scaffoldBackgroundColor,
                                  width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        _photoChoice == null
                            ? 'Foto del grupo (opcional)'
                            : 'Cambiar foto',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nombre',
                hintText: 'Senderismo por Madrid',
                border: const OutlineInputBorder(),
                errorText:
                    _tried && _name.text.trim().isEmpty ? 'Ponle un nombre' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Ciudad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _interests,
              decoration: const InputDecoration(
                labelText: 'Intereses (separados por comas)',
                hintText: 'senderismo, naturaleza, fotografía',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Tamaño máximo: ${_maxMembers.round()}',
                style: theme.textTheme.bodyMedium),
            Slider(
              value: _maxMembers,
              min: 2,
              max: 20,
              divisions: 18,
              label: '${_maxMembers.round()}',
              onChanged: (double v) => setState(() => _maxMembers = v),
            ),
            const SizedBox(height: 6),
            FilledButton(onPressed: _submit, child: const Text('Crear')),
          ],
        ),
      ),
    );
  }
}

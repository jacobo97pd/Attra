import 'package:flutter/material.dart';

import '../../profile/data/profile_summary_repository.dart';
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
    this.city = '',
    this.myInterests = const <String>[],
  });

  final String uid;
  final FriendGroupService groupService;
  final SocialDiscoveryService discoveryService;
  final ProfileSummaryRepository summaries;
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
      await widget.groupService.createGroup(
        name: input.name,
        description: input.description,
        city: input.city,
        interests: input.interests,
        maxMembers: input.maxMembers,
      );
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
        service: widget.groupService,
        summaries: widget.summaries,
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Grupos y planes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Crear grupo'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: <Widget>[
            Text('Tus grupos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            StreamBuilder<List<FriendGroup>>(
              stream: widget.groupService.observeMyGroups(widget.uid),
              builder: (BuildContext context,
                  AsyncSnapshot<List<FriendGroup>> snap) {
                if (snap.hasError) {
                  return _ErrorNote('No se pudieron cargar tus grupos: '
                      '${snap.error}');
                }
                final List<FriendGroup> mine = snap.data ?? const <FriendGroup>[];
                if (mine.isEmpty) {
                  return Text('Aún no estás en ningún grupo.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline));
                }
                return Column(
                  children: <Widget>[
                    for (final FriendGroup g in mine)
                      _GroupTile(
                        group: g,
                        uid: widget.uid,
                        onTap: () => _openGroup(g),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Text('Recomendados para ti', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<RecommendedGroup>>(
              future: _recommended,
              builder: (BuildContext context,
                  AsyncSnapshot<List<RecommendedGroup>> snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return _ErrorNote(
                      'No se pudieron cargar los grupos: ${snap.error}');
                }
                final List<RecommendedGroup> recs =
                    snap.data ?? const <RecommendedGroup>[];
                if (recs.isEmpty) {
                  return Text('No hay grupos abiertos por aquí todavía.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline));
                }
                return Column(
                  children: <Widget>[
                    for (final RecommendedGroup r in recs)
                      _GroupTile(
                        group: r.group,
                        uid: widget.uid,
                        affinityPercent: r.affinityPercent,
                        onTap: () => _openGroup(r.group),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Nota de error visible (en vez de vacío silencioso) para diagnosticar fallos
/// de reglas/índices al cargar grupos.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.uid,
    required this.onTap,
    this.affinityPercent,
  });

  final FriendGroup group;
  final String uid;
  final VoidCallback onTap;
  final int? affinityPercent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(Icons.groups_rounded, color: theme.colorScheme.primary),
        ),
        title: Text(group.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          <String>[
            if (group.city.isNotEmpty) group.city,
            '${group.memberCount}/${group.maxMembers}',
            if (group.interests.isNotEmpty) group.interests.take(2).join(', '),
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: affinityPercent != null && affinityPercent! > 0
            ? Text('$affinityPercent%',
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700))
            : (group.isMember(uid)
                ? const Icon(Icons.check_circle_outline)
                : group.isPending(uid)
                    ? const Icon(Icons.hourglass_top_rounded)
                    : const Icon(Icons.chevron_right)),
      ),
    );
  }
}

class _GroupDetailSheet extends StatefulWidget {
  const _GroupDetailSheet({
    required this.group,
    required this.uid,
    required this.service,
    required this.summaries,
  });

  final FriendGroup group;
  final String uid;
  final FriendGroupService service;
  final ProfileSummaryRepository summaries;

  @override
  State<_GroupDetailSheet> createState() => _GroupDetailSheetState();
}

class _GroupDetailSheetState extends State<_GroupDetailSheet> {
  bool _busy = false;

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
  });
  final String name;
  final String description;
  final String city;
  final List<String> interests;
  final int maxMembers;
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
            const SizedBox(height: 12),
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

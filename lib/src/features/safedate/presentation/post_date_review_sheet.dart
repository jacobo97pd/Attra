import 'package:flutter/material.dart';

import '../data/safedate_service.dart';
import '../domain/post_date_review.dart';

/// Etiquetas en español de las categorías de preocupación (privadas; solo para
/// moderación interna, nunca públicas ni visibles para el evaluado).
const Map<String, String> _concernLabels = <String, String>{
  PostDateConcern.fakeIdentity: 'Identidad falsa',
  PostDateConcern.sexualPressure: 'Presión sexual',
  PostDateConcern.insistedAfterNo: 'Insistió tras un no',
  PostDateConcern.aggressive: 'Agresividad',
  PostDateConcern.threats: 'Amenazas',
  PostDateConcern.controlManipulation: 'Control o manipulación',
  PostDateConcern.isolation: 'Intentó aislarme',
  PostDateConcern.substanceIssue: 'Problema con sustancias',
  PostDateConcern.misleadingLocation: 'Cambió el lugar acordado',
  PostDateConcern.moneyRequest: 'Pidió dinero',
  PostDateConcern.scam: 'Estafa',
  PostDateConcern.other: 'Otro',
};

/// Hoja de revisión post-cita. COMPLETAMENTE privada: la otra persona nunca la
/// ve, no hay puntuaciones públicas ni rankings. Opcionalmente permite reportar
/// o bloquear (reutiliza la moderación estándar; no se revela quién reporta).
class PostDateReviewSheet extends StatefulWidget {
  const PostDateReviewSheet({
    super.key,
    required this.planId,
    required this.service,
    required this.otherName,
  });

  final String planId;
  final SafeDateService service;
  final String otherName;

  static Future<bool> show(
    BuildContext context, {
    required String planId,
    required SafeDateService service,
    required String otherName,
  }) async {
    final bool? done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PostDateReviewSheet(
        planId: planId,
        service: service,
        otherName: otherName,
      ),
    );
    return done ?? false;
  }

  @override
  State<PostDateReviewSheet> createState() => _PostDateReviewSheetState();
}

class _PostDateReviewSheetState extends State<PostDateReviewSheet> {
  bool _feltSafe = true;
  bool _respectedBoundaries = true;
  bool _matchedProfile = true;
  bool _experiencedPressure = false;
  bool _wantsToReport = false;
  bool _wantsToBlock = false;
  final Set<String> _concerns = <String>{};
  bool _busy = false;
  String? _error;

  bool get _showConcerns =>
      !_feltSafe ||
      !_respectedBoundaries ||
      !_matchedProfile ||
      _experiencedPressure ||
      _wantsToReport;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.submitPostDateReview(
        planId: widget.planId,
        feltSafe: _feltSafe,
        respectedBoundaries: _respectedBoundaries,
        matchedProfile: _matchedProfile,
        experiencedPressure: _experiencedPressure,
        wantsToBlock: _wantsToBlock,
        wantsToReport: _wantsToReport,
        concernCategories: _concerns.toList(growable: false),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on SafeDateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('¿Cómo fue tu cita?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Esto es privado. ${widget.otherName} nunca lo verá y no hay '
              'puntuaciones públicas. Nos ayuda a cuidar de la comunidad.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            _YesNo(
              label: '¿Te sentiste a salvo?',
              value: _feltSafe,
              onChanged: (bool v) => setState(() => _feltSafe = v),
            ),
            _YesNo(
              label: '¿Respetó tus límites?',
              value: _respectedBoundaries,
              onChanged: (bool v) => setState(() => _respectedBoundaries = v),
            ),
            _YesNo(
              label: '¿Coincidía con su perfil?',
              value: _matchedProfile,
              onChanged: (bool v) => setState(() => _matchedProfile = v),
            ),
            _YesNo(
              label: '¿Sentiste presión?',
              value: _experiencedPressure,
              onChanged: (bool v) => setState(() => _experiencedPressure = v),
            ),
            if (_showConcerns) ...<Widget>[
              const SizedBox(height: 12),
              Text('¿Qué ocurrió? (opcional)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _concernLabels.entries.map(
                    (MapEntry<String, String> e) {
                  final bool sel = _concerns.contains(e.key);
                  return FilterChip(
                    label: Text(e.value),
                    selected: sel,
                    onSelected: (bool v) => setState(() {
                      if (v) {
                        _concerns.add(e.key);
                      } else {
                        _concerns.remove(e.key);
                      }
                    }),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wantsToReport,
              onChanged: (bool v) => setState(() => _wantsToReport = v),
              title: const Text('Reportar a esta persona'),
              subtitle: const Text('Lo revisa nuestro equipo. Es confidencial.'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wantsToBlock,
              onChanged: (bool v) => setState(() => _wantsToBlock = v),
              title: const Text('Bloquear a esta persona'),
              subtitle: const Text('No podréis volver a veros ni escribiros.'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Ahora no'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_busy ? 'Enviando…' : 'Enviar (privado)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _YesNo extends StatelessWidget {
  const _YesNo({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: true, label: Text('Sí')),
              ButtonSegment<bool>(value: false, label: Text('No')),
            ],
            selected: <bool>{value},
            onSelectionChanged: (Set<bool> s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

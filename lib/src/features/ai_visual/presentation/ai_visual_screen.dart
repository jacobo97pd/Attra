import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';
import '../data/ai_visual_service.dart';
import '../domain/profile_insight.dart';

/// Pantalla de IA visual de Attra Pro. Gating en cascada:
/// 1. No Pro -> upsell.
/// 2. Pro sin consentimiento -> pedir consentimiento (dato biométrico, RGPD).
/// 3. Pro + consentimiento -> subir foto de referencia + insights del perfil.
class AiVisualScreen extends StatefulWidget {
  const AiVisualScreen({
    super.key,
    required this.uid,
    required this.isPro,
    required this.hasConsent,
    required this.service,
    required this.onUpgrade,
    required this.onGiveConsent,
    required this.onRevokeConsent,
  });

  final String uid;
  final bool isPro;
  final bool hasConsent;
  final AiVisualService service;
  final VoidCallback onUpgrade;
  final Future<void> Function() onGiveConsent;
  final Future<void> Function() onRevokeConsent;

  @override
  State<AiVisualScreen> createState() => _AiVisualScreenState();
}

class _AiVisualScreenState extends State<AiVisualScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;
  String? _status;
  List<ProfileInsight> _insights = const <ProfileInsight>[];
  // Estado local de consentimiento: permite refrescar la pantalla al instante
  // tras conceder, sin tener que salir y volver a entrar.
  late bool _hasConsent;
  String? _referenceUrl;

  @override
  void initState() {
    super.initState();
    _hasConsent = widget.hasConsent;
    if (widget.isPro && _hasConsent) {
      _loadInsights();
      _loadReference();
    }
  }

  Future<void> _loadInsights() async {
    try {
      final List<ProfileInsight> list = await widget.service.getInsights();
      if (mounted) setState(() => _insights = list);
    } catch (_) {/* silencioso */}
  }

  Future<void> _loadReference() async {
    final String? url = await widget.service.getReferenceUrl(widget.uid);
    if (mounted) setState(() => _referenceUrl = url);
  }

  Future<void> _pickReference() async {
    final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (file == null || !mounted) return;
    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final String status =
          await widget.service.analyzeReference(uid: widget.uid, bytes: bytes);
      if (mounted) {
        setState(() => _status = status);
        _snack(status == 'pending_provider'
            ? 'Referencia guardada. El análisis visual se activará al integrar el motor de IA.'
            : 'Referencia analizada.');
        _loadReference(); // muestra la nueva miniatura
      }
    } on AiVisualException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IA visual · Pro')),
      body: !widget.isPro
          ? _upsell(context)
          : !_hasConsent
              ? _consent(context)
              : _active(context),
    );
  }

  Widget _upsell(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Violeta tecnológico: reservado para la IA (no se usa en el resto).
            const Icon(Icons.auto_awesome, size: 56, color: AppColors.aiViolet),
            const SizedBox(height: 16),
            Text('IA visual de Attra Pro', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Sube una foto de referencia y te mostraremos personas con un '
              'parecido estético, además de mejorar tu perfil con IA.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: widget.onUpgrade,
              icon: const Icon(Icons.workspace_premium),
              label: const Text('Hazte Pro'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _consent(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Icon(Icons.privacy_tip_outlined,
            size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('Consentimiento para la IA visual',
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'Para mostrarte personas con parecido estético analizamos el rostro de '
          'una foto de referencia y guardamos una huella visual (dato biométrico). '
          'Solo se usa para similitud estética y tus preferencias explícitas. '
          'NUNCA inferimos raza, etnia, religión, salud, política ni orientación. '
          'El análisis se guarda cifrado en el servidor, no se comparte, y puedes '
          'borrarlo cuando quieras.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await widget.onGiveConsent();
                  if (mounted) {
                    setState(() {
                      _busy = false;
                      _hasConsent = true; // refresca la pantalla al instante
                    });
                    _loadInsights();
                    _loadReference();
                  }
                },
          child: const Text('Doy mi consentimiento'),
        ),
      ],
    );
  }

  Widget _active(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Foto de referencia', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text(
          'Sube la foto de alguien con el estilo que te atrae. Te mostraremos '
          'perfiles con parecido estético (combinado con tus filtros).',
        ),
        const SizedBox(height: 12),
        if (_referenceUrl != null) ...<Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(_referenceUrl!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 80,
                        height: 80,
                        color: const Color(0xFFE0E0E0),
                        child: const Icon(Icons.image_not_supported_outlined))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Tu foto de referencia actual.',
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _busy ? null : _pickReference,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_a_photo_outlined),
          label: Text(_referenceUrl == null
              ? 'Subir foto de referencia'
              : 'Cambiar foto de referencia'),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _status == 'pending_provider'
                  ? 'Referencia guardada. El motor de similitud se activará pronto.'
                  : 'Referencia lista.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        const Divider(height: 32),
        Text('Mejora tu perfil', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_insights.isEmpty)
          const Text('Tu perfil está completo. ¡Buen trabajo!')
        else
          ..._insights.map((ProfileInsight i) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  i.severity == 'high'
                      ? Icons.priority_high
                      : i.severity == 'medium'
                          ? Icons.tips_and_updates_outlined
                          : Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                ),
                title: Text(i.text),
              )),
        const Divider(height: 32),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final NavigatorState nav = Navigator.of(context);
                  setState(() => _busy = true);
                  try {
                    await widget.service.clearAiData();
                    await widget.onRevokeConsent();
                    _snack('Datos de IA borrados.');
                    nav.maybePop();
                  } catch (_) {
                    _snack('No se pudo borrar.');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Borrar mis datos de IA y retirar consentimiento'),
        ),
      ],
    );
  }
}

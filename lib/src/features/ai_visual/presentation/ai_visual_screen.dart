import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/attra_image.dart';
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
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('IA visual · '),
            ShaderMask(
              shaderCallback: (Rect b) => const LinearGradient(colors: <Color>[
                AppColors.attraRed,
                AppColors.aiViolet,
              ]).createShader(b),
              child: const Text('Pro',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            const Text(' ✨', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
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
    final bool hasRef = _referenceUrl != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        // ── 01 Tu foto de referencia ─────────────────────────────────────
        const _SectionHeader(
          number: '01',
          title: 'Tu foto de referencia',
          subtitle:
              'Sube la foto de alguien con el estilo que te atrae y la IA encontrará perfiles con una estética similar.',
        ),
        const SizedBox(height: 14),
        _ReferencePhoto(url: _referenceUrl),
        const SizedBox(height: 12),
        _AnalysisPanel(hasRef: hasRef),
        const SizedBox(height: 12),
        _OutlinedAction(
          icon: Icons.image_outlined,
          label: hasRef
              ? 'Cambiar foto de referencia'
              : 'Subir foto de referencia',
          loading: _busy,
          onTap: _busy ? null : _pickReference,
        ),

        const SizedBox(height: 26),
        // ── 02 Lo que la IA hará por ti ──────────────────────────────────
        const _SectionHeader(number: '02', title: 'Lo que la IA hará por ti'),
        const SizedBox(height: 14),
        const Row(
          children: <Widget>[
            Expanded(
              child: _FeatureCard(
                icon: Icons.people_alt_rounded,
                title: 'Perfiles parecidos',
                body:
                    'Te mostramos primero personas con una estética similar a tu referencia.',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _FeatureCard(
                icon: Icons.insights_rounded,
                title: 'Mejor foto principal',
                body:
                    'Analizamos tus fotos y te sugerimos cuál genera más interés.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          children: <Widget>[
            Expanded(
              child: _FeatureCard(
                icon: Icons.edit_note_rounded,
                title: 'Optimización de perfil',
                body: 'Detectamos puntos débiles en tu bio y te damos mejoras.',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _FeatureCard(
                icon: Icons.favorite_rounded,
                title: 'Compatibilidad visual',
                body: 'Indicamos el nivel de parecido visual de cada perfil.',
              ),
            ),
          ],
        ),

        // Mejoras reales del perfil (insights del backend).
        if (_insights.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          const _SubHeader('Mejoras sugeridas para tu perfil'),
          const SizedBox(height: 8),
          ..._insights.map((ProfileInsight i) => _InsightRow(insight: i)),
        ],

        const SizedBox(height: 26),
        // ── 03 Buscar ────────────────────────────────────────────────────
        const _SectionHeader(number: '03', title: 'Buscar parecidos'),
        const SizedBox(height: 14),
        _SearchButton(
          enabled: hasRef && !_busy,
          onTap: _onSearchSimilar,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.lock_outline_rounded,
                size: 13, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Solo tú puedes ver tus referencias. Tu privacidad está 100% protegida.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _clearData,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.coral),
            label: const Text('Borrar mis datos de IA y retirar consentimiento',
                style: TextStyle(color: AppColors.coral)),
          ),
        ),
      ],
    );
  }

  void _onSearchSimilar() {
    if (_referenceUrl == null) {
      _snack('Sube primero una foto de referencia.');
      return;
    }
    // El motor real ordena el FEED por parecido (filtro "Solo parecidos a mi
    // referencia"). Volvemos al feed y guiamos al usuario.
    Navigator.of(context).maybePop();
    _snack(
        'Activa "Solo parecidos a mi referencia" en los filtros del feed para ver los resultados.');
  }

  Future<void> _clearData() async {
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
  }
}

// ── Widgets de la pantalla premium de IA visual ────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.number, required this.title, this.subtitle});
  final String number;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(number,
                style: const TextStyle(
                    color: AppColors.attraRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(subtitle!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary, height: 1.35)),
        ],
      ],
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.w700));
  }
}

class _ReferencePhoto extends StatelessWidget {
  const _ReferencePhoto({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (url != null && url!.isNotEmpty)
              Positioned.fill(child: AttraImage(url: url))
            else
              _placeholder(),
            // Badge "Referencia cargada".
            if (url != null && url!.isNotEmpty)
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: AppColors.attraRed.withValues(alpha: 0.6)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.check_circle_rounded,
                          size: 13, color: AppColors.attraRed),
                      SizedBox(width: 5),
                      Text('Referencia cargada',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceHigh,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add_a_photo_outlined,
                size: 40, color: AppColors.textMuted),
            SizedBox(height: 8),
            Text('Sube una foto de referencia',
                style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Panel "qué analiza la IA" — VERAZ: estética, no rasgos biométricos.
class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({required this.hasRef});
  final bool hasRef;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.auto_awesome, size: 16, color: AppColors.aiViolet),
              SizedBox(width: 8),
              Text('Cómo trabaja la IA',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          const _AnalysisRow(
              label: 'Qué analiza',
              value: 'La estética general: estilo, vibe, composición'),
          const _Sep(),
          const _AnalysisRow(
              label: 'Qué NO usa',
              value: 'Raza, etnia, salud, edad ni rasgos sensibles'),
          const _Sep(),
          _AnalysisRow(
              label: 'Estado',
              value: hasRef ? 'Referencia lista ✓' : 'Sin referencia aún'),
        ],
      ),
    );
  }
}

class _AnalysisRow extends StatelessWidget {
  const _AnalysisRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.bolt_rounded, size: 14, color: AppColors.attraRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AppColors.surfaceLine);
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.attraRed.withValues(alpha: 0.14),
            ),
            child: Icon(icon, size: 19, color: AppColors.attraRed),
          ),
          const SizedBox(height: 10),
          Text(title,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary, height: 1.3)),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});
  final ProfileInsight insight;
  @override
  Widget build(BuildContext context) {
    final IconData icon = insight.severity == 'high'
        ? Icons.priority_high_rounded
        : insight.severity == 'medium'
            ? Icons.tips_and_updates_outlined
            : Icons.auto_awesome;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.attraRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(insight.text,
                style: const TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.loading = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.surfaceLine),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.attraRed))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 18, color: AppColors.textPrimary),
                    const SizedBox(width: 8),
                    Text(label,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(colors: AppColors.action),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.attraRed.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Buscar perfiles similares',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

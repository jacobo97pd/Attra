import 'package:flutter/material.dart';
// PlatformException + Uint8List: el picker falla con PlatformException cuando
// el usuario deniega el acceso a las fotos.
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_image.dart';
import '../../../widgets/attra_loader.dart';
import '../data/ai_visual_service.dart';
import '../domain/ai_reference_state.dart';
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
    this.onSearchSimilar,
  });

  final String uid;
  final bool isPro;
  final bool hasConsent;
  final AiVisualService service;
  final VoidCallback onUpgrade;
  final Future<void> Function() onGiveConsent;
  final Future<void> Function() onRevokeConsent;

  /// Activa el filtro "Solo parecidos a mi referencia" y lleva al feed. Sin
  /// esto, el botón principal de la función estrella de Pro no buscaba nada:
  /// cerraba la pantalla y pedía al usuario que fuera a buscar el filtro.
  final VoidCallback? onSearchSimilar;

  @override
  State<AiVisualScreen> createState() => _AiVisualScreenState();
}

/// Aviso a pie de pantalla (sin red, plan caducado, permiso de fotos…). Antes
/// todos estos casos acababan en una pantalla muda o en un snackbar que ya se
/// había ido: el usuario no sabía por qué la IA no hacía nada.
class _Issue {
  _Issue({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class _AiVisualScreenState extends State<AiVisualScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;
  bool _loading = false;
  List<ProfileInsight> _insights = const <ProfileInsight>[];

  /// Estado REAL de la referencia (lo dice el backend, no la existencia del
  /// fichero en Storage).
  AiReferenceState _reference = AiReferenceState.empty;

  /// Las sugerencias ya se han pedido al menos una vez (para distinguir
  /// "todavía cargando" de "el backend no devolvió ninguna").
  bool _insightsLoaded = false;
  String? _insightsError;

  _Issue? _issue;

  // Estado local de consentimiento: permite refrescar la pantalla al instante
  // tras conceder, sin tener que salir y volver a entrar.
  late bool _hasConsent;

  @override
  void initState() {
    super.initState();
    _hasConsent = widget.hasConsent;
    if (widget.isPro && _hasConsent) {
      _load();
    }
  }

  /// Carga estado de referencia + sugerencias, clasificando los errores para
  /// poder explicárselos al usuario.
  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _issue = null;
      });
    }
    try {
      final AiReferenceState state =
          await widget.service.loadReferenceState(widget.uid);
      if (!mounted) return;
      setState(() => _reference = state);
      _issueForReference(state);
    } on AiVisualException catch (e) {
      if (mounted) setState(() => _issue = _issueFor(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadInsights();
  }

  /// Traduce un estado no utilizable de la referencia a un aviso accionable.
  void _issueForReference(AiReferenceState state) {
    if (state.status == AiReferenceStatus.denied) {
      // El backend distingue "no eres Pro / Pro caducado" de "consentimiento"
      // o "IA deshabilitada" solo por el texto; el CTA de planes únicamente
      // tiene sentido en el primer caso.
      final bool isPlan = state.explanation.toLowerCase().contains('pro');
      setState(() => _issue = _Issue(
            icon: Icons.workspace_premium_outlined,
            title: 'IA visual no disponible',
            message: state.explanation,
            actionLabel: isPlan ? 'Ver planes' : null,
            onAction: isPlan ? widget.onUpgrade : null,
          ));
      return;
    }
    if (state.status == AiReferenceStatus.unknown) {
      setState(() => _issue = _Issue(
            icon: Icons.wifi_off_rounded,
            title: 'Sin conexión con la IA',
            message: state.explanation,
            actionLabel: 'Reintentar',
            onAction: _load,
          ));
      return;
    }
    setState(() => _issue = null);
  }

  _Issue _issueFor(AiVisualException e) {
    if (e.isNetwork) {
      return _Issue(
        icon: Icons.wifi_off_rounded,
        title: 'Sin conexión',
        message: e.message,
        actionLabel: 'Reintentar',
        onAction: _load,
      );
    }
    if (e.isPlan) {
      return _Issue(
        icon: Icons.workspace_premium_outlined,
        title: 'Tu plan no cubre la IA visual',
        message: e.message,
        actionLabel: 'Ver planes',
        onAction: widget.onUpgrade,
      );
    }
    return _Issue(
      icon: Icons.error_outline_rounded,
      title: 'No se pudo completar',
      message: e.message,
      actionLabel: 'Reintentar',
      onAction: _load,
    );
  }

  Future<void> _loadInsights() async {
    try {
      final List<ProfileInsight> list = await widget.service.getInsights();
      if (!mounted) return;
      setState(() {
        _insights = list;
        _insightsLoaded = true;
        _insightsError = null;
      });
    } on AiVisualException catch (e) {
      // Antes se tragaba el error en silencio y la sección desaparecía sin más.
      if (!mounted) return;
      setState(() {
        _insightsLoaded = true;
        _insightsError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _insightsLoaded = true;
        _insightsError = 'No se pudieron cargar las sugerencias.';
      });
    }
  }

  Future<void> _pickReference() async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    } on PlatformException catch (e) {
      // Sin permiso de fotos el picker lanzaba y el botón se quedaba mudo: el
      // usuario pulsaba y no ocurría absolutamente nada.
      final bool denied = e.code == 'photo_access_denied' ||
          e.code == 'camera_access_denied' ||
          e.code == 'permission';
      setState(() => _issue = _Issue(
            icon: Icons.no_photography_outlined,
            title: denied
                ? 'Sin acceso a tus fotos'
                : 'No se pudo abrir la galería',
            message: denied
                ? 'Attra necesita permiso para acceder a tus fotos. Actívalo en '
                    'los ajustes del sistema (Attra → Fotos) y vuelve a intentarlo.'
                : 'No hemos podido abrir la galería (${e.code}). Inténtalo de nuevo.',
          ));
      return;
    } catch (_) {
      setState(() => _issue = _Issue(
            icon: Icons.no_photography_outlined,
            title: 'No se pudo abrir la galería',
            message: 'Inténtalo de nuevo en unos segundos.',
          ));
      return;
    }
    if (file == null || !mounted) return; // el usuario canceló

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      _snack('No se pudo leer esa foto. Prueba con otra.');
      return;
    }
    if (!mounted) return;
    if (bytes.isEmpty) {
      // Respuesta vacía del picker (fichero corrupto o en la nube sin
      // descargar): subirlo daría un análisis inútil.
      _snack('Esa foto está vacía o no se pudo descargar. Prueba con otra.');
      return;
    }

    setState(() {
      _busy = true;
      _issue = null;
      _reference = _reference.copyWith(status: AiReferenceStatus.processing);
    });
    try {
      final AiReferenceStatus status = await runWithAttraLoader(
        context,
        () => widget.service.analyzeReference(uid: widget.uid, bytes: bytes),
        message: 'Analizando tu referencia…',
      );
      final String? url = await widget.service.getReferenceUrl(widget.uid);
      if (!mounted) return;
      setState(
          () => _reference = AiReferenceState(status: status, photoUrl: url));
      if (status == AiReferenceStatus.ready) {
        _snack('Referencia lista: ya puedes buscar perfiles parecidos.');
      } else {
        // pending_provider: la foto está guardada pero NO hay huella visual.
        // Decir "referencia analizada" era mentira y la búsqueda no devolvía
        // nada.
        _snack('Foto guardada, pero el motor de IA no pudo analizarla.');
        setState(() => _issue = _Issue(
              icon: Icons.auto_awesome_outlined,
              title: 'Análisis no disponible',
              message: _reference.explanation,
              actionLabel: 'Probar otra foto',
              onAction: _pickReference,
            ));
      }
    } on AiVisualException catch (e) {
      if (!mounted) return;
      setState(() => _issue = _issueFor(e));
      _snack(e.message);
      await _load();
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
      backgroundColor: context.colors.bg,
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
                    _load();
                  }
                },
          child: const Text('Doy mi consentimiento'),
        ),
      ],
    );
  }

  Widget _active(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        if (_issue != null) ...<Widget>[
          _IssueBanner(issue: _issue!),
          const SizedBox(height: 14),
        ],
        // ── 01 Tu foto de referencia ─────────────────────────────────────
        const _SectionHeader(
          number: '01',
          title: 'Tu foto de referencia',
          subtitle:
              'Sube la foto de alguien con el estilo que te atrae y la IA encontrará perfiles con una estética similar.',
        ),
        const SizedBox(height: 14),
        _ReferencePhoto(state: _reference, loading: _loading),
        const SizedBox(height: 12),
        _AnalysisPanel(state: _reference, loading: _loading),
        const SizedBox(height: 12),
        _OutlinedAction(
          icon: Icons.image_outlined,
          label: _reference.hasPhoto
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
        const SizedBox(height: 18),
        const _SubHeader('Mejoras sugeridas para tu perfil'),
        const SizedBox(height: 8),
        ..._insightsSection(context),

        const SizedBox(height: 26),
        // ── 03 Buscar ────────────────────────────────────────────────────
        const _SectionHeader(number: '03', title: 'Buscar parecidos'),
        const SizedBox(height: 14),
        _SearchButton(
          enabled: _reference.canSearch && !_busy,
          onTap: _onSearchSimilar,
        ),
        if (!_reference.canSearch && !_loading) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _reference.explanation,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.colors.textMuted),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.lock_outline_rounded,
                size: 13, color: context.colors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Solo tú puedes ver tus referencias. Tu privacidad está 100% protegida.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.colors.textMuted),
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

  /// Sección de sugerencias: cargando / error / lista vacía / lista. Antes, si
  /// el backend fallaba o no devolvía nada, la sección desaparecía sin decir
  /// nada y parecía que la IA no hacía su trabajo.
  List<Widget> _insightsSection(BuildContext context) {
    if (!_insightsLoaded) {
      return <Widget>[
        Text('Analizando tu perfil…',
            style: TextStyle(color: context.colors.textMuted)),
      ];
    }
    if (_insightsError != null) {
      return <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded,
                size: 18, color: AppColors.coral),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_insightsError!,
                  style: TextStyle(color: context.colors.textSecondary)),
            ),
            TextButton(
                onPressed: _loadInsights, child: const Text('Reintentar')),
          ],
        ),
      ];
    }
    if (_insights.isEmpty) {
      return <Widget>[
        Text(
          'Ahora mismo no tenemos mejoras que sugerirte: tu perfil está completo.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      ];
    }
    return _insights
        .map((ProfileInsight i) => _InsightRow(insight: i))
        .toList(growable: false);
  }

  void _onSearchSimilar() {
    // La búsqueda solo funciona si el BACKEND tiene huella visual. Antes
    // bastaba con que hubiera foto, así que se llevaba al usuario a un feed que
    // no iba a devolver a nadie.
    if (!_reference.canSearch) {
      _snack(_reference.explanation);
      return;
    }
    // El motor de parecidos vive en el FEED (filtro "Solo parecidos a mi
    // referencia"). Antes este botón se limitaba a cerrar la pantalla y pedirle
    // al usuario que fuera a buscar el filtro él mismo, así que el botón
    // principal de la función estrella de Pro no hacía absolutamente nada.
    // Ahora lo activa y lleva al feed.
    final VoidCallback? apply = widget.onSearchSimilar;
    Navigator.of(context).maybePop();
    if (apply == null) {
      _snack(
          'Activa "Solo parecidos a mi referencia" en los filtros del feed.');
      return;
    }
    apply();
  }

  Future<void> _clearData() async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('¿Borrar tus datos de IA?'),
            content: const Text(
              'Eliminaremos tu huella visual del servidor y las fotos de '
              'referencia que hayas subido. También retiramos tu consentimiento: '
              'la búsqueda de parecidos dejará de funcionar hasta que vuelvas a '
              'activarla.',
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Borrar',
                    style: TextStyle(color: AppColors.coral)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // El borrado ahora incluye las fotos de Storage: antes solo se borraba la
      // huella del backend y las fotos seguían ahí (y la pantalla las seguía
      // enseñando como "Referencia cargada").
      final AiDataDeletion result =
          await widget.service.clearAiData(widget.uid);
      await widget.onRevokeConsent();
      if (!mounted) return;
      setState(() {
        _reference = AiReferenceState.empty;
        _insights = const <ProfileInsight>[];
        _insightsLoaded = false;
        _issue = null;
      });
      messenger.showSnackBar(SnackBar(
        content: Text(result.isComplete
            ? 'Datos de IA borrados: huella visual y fotos de referencia eliminadas.'
            : 'Huella visual borrada. No hemos podido eliminar todas las fotos '
                'de referencia del almacenamiento; vuelve a intentarlo más tarde.'),
      ));
      nav.maybePop();
    } on AiVisualException catch (e) {
      if (!mounted) return;
      setState(() => _issue = _issueFor(e));
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo borrar: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo borrar. Inténtalo de nuevo.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ── Widgets de la pantalla premium de IA visual ────────────────────────────

class _IssueBanner extends StatelessWidget {
  const _IssueBanner({required this.issue});
  final _Issue issue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(issue.icon, size: 20, color: AppColors.coral),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(issue.title,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(issue.message,
                    style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 13,
                        height: 1.3)),
                if (issue.actionLabel != null && issue.onAction != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: issue.onAction,
                      child: Text(issue.actionLabel!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
              style: theme.textTheme.bodySmall?.copyWith(
                  color: context.colors.textSecondary, height: 1.35)),
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
        style: TextStyle(
            color: context.colors.textPrimary, fontWeight: FontWeight.w700));
  }
}

class _ReferencePhoto extends StatelessWidget {
  const _ReferencePhoto({required this.state, required this.loading});
  final AiReferenceState state;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final String? url = state.photoUrl;
    final bool hasPhoto = url != null && url.isNotEmpty;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasPhoto)
              Positioned.fill(child: AttraImage(url: url))
            else
              _placeholder(context),
            // Badge de estado: antes decía siempre "Referencia cargada" con
            // solo existir el fichero, aunque no hubiera análisis detrás.
            if (hasPhoto && !loading)
              Positioned(
                left: 12,
                bottom: 12,
                child: _StatusBadge(state: state),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: context.colors.surfaceHigh,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add_a_photo_outlined,
                size: 40, color: context.colors.textMuted),
            const SizedBox(height: 8),
            Text(
                loading
                    ? 'Comprobando tu referencia…'
                    : 'Sube una foto de referencia',
                style: TextStyle(color: context.colors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});
  final AiReferenceState state;

  @override
  Widget build(BuildContext context) {
    final bool ready = state.status == AiReferenceStatus.ready;
    final IconData icon = ready
        ? Icons.check_circle_rounded
        : state.status == AiReferenceStatus.processing
            ? Icons.hourglass_top_rounded
            : Icons.error_outline_rounded;
    final Color tint = ready ? AppColors.attraRed : AppColors.coral;
    final String text = ready
        ? 'Referencia lista'
        : state.status == AiReferenceStatus.processing
            ? 'Analizando…'
            : 'Sin análisis';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Panel "qué analiza la IA" — VERAZ: estética, no rasgos biométricos.
class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({required this.state, required this.loading});
  final AiReferenceState state;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.auto_awesome,
                  size: 16, color: AppColors.aiViolet),
              const SizedBox(width: 8),
              Text('Cómo trabaja la IA',
                  style: TextStyle(
                      color: context.colors.textPrimary,
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
          // Estado REAL (lo dice el backend). Antes bastaba con que existiera la
          // foto para anunciar "Referencia lista ✓", aunque no hubiera huella
          // visual y la búsqueda no fuera a devolver nada.
          _AnalysisRow(
              label: 'Estado', value: loading ? 'Comprobando…' : state.label),
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
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13)),
          ),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: context.colors.textPrimary,
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
      Divider(height: 1, color: context.colors.surfaceLine);
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
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceLine),
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
                  ?.copyWith(color: context.colors.textSecondary, height: 1.3)),
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
                style: TextStyle(color: context.colors.textPrimary)),
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
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.surfaceLine),
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
                    Icon(icon, size: 18, color: context.colors.textPrimary),
                    const SizedBox(width: 8),
                    Text(label,
                        style: TextStyle(
                            color: context.colors.textPrimary,
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
          // Deshabilitado visualmente, pero sigue siendo pulsable para poder
          // EXPLICAR por qué no se puede buscar (antes no se enteraba nadie).
          onTap: onTap,
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

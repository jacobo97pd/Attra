import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_editorial.dart';
import '../../../widgets/attra_loader.dart';
import '../../../widgets/attra_image.dart';
import '../../anti_ghosting/presentation/reliability_badge.dart';
import '../../auth/domain/app_user.dart';
import '../../social/domain/intent_mode.dart';
import '../../social/presentation/intent_badge.dart';
import '../../profile/domain/intro_media.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_prompt.dart';
import '../../profile/domain/profile_trait.dart';
import '../../profile/presentation/edit_traits_screen.dart';
import '../../profile/presentation/intro_media_editor.dart';
import '../../profile/presentation/profile_prompts_editor_screen.dart';
import '../../profile/presentation/profile_strength_card.dart';
import '../../profile/presentation/profile_view_screen.dart';

/// Fila con icono + texto para el diálogo explicativo de Slow Dating.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onLogout,
    required this.onLoadProfileState,
    required this.onUploadAdditionalPhoto,
    required this.onDeleteAdditionalPhoto,
    this.onReorderPhotos,
    required this.onAddPrompt,
    required this.onClaimReward,
    required this.onLoadSeedProfiles,
    required this.onDeleteAccount,
    required this.onLoadProfileRaw,
    required this.onSetTrait,
    required this.onSetTraitVisibility,
    required this.onLoadProfilePrompts,
    required this.onSaveProfilePrompts,
    required this.onLoadIntroMedia,
    required this.onUploadIntroAudio,
    required this.onDeleteIntroAudio,
    required this.onUploadIntroVideo,
    required this.onDeleteIntroVideo,
    this.onOpenSettings,
    this.onOpenUpgrade,
    this.onOpenAiVisual,
    this.onOpenFriendMode,
    this.onOpenGroups,
    this.onOpenSafeDate,
    this.onOpenBoostStore,
    this.onSetSlowDating,
    this.currentPlanLabel = 'Free',
    this.isProUser = false,
    this.user,
    this.errorMessage,
  });

  final AppUser? user;
  final String? errorMessage;
  final VoidCallback onLogout;
  final Future<ProfileCompletionState> Function() onLoadProfileState;
  final Future<void> Function({
    required Uint8List photoBytes,
    required String fileExtension,
    required String source,
  }) onUploadAdditionalPhoto;
  final Future<void> Function(String storagePath) onDeleteAdditionalPhoto;

  /// Reordena las fotos adicionales (arrastrar para colocar). Null = sin
  /// reordenar.
  final Future<void> Function(List<String> orderedStoragePaths)?
      onReorderPhotos;
  final Future<void> Function(String prompt) onAddPrompt;
  final Future<void> Function(String rewardId) onClaimReward;
  final Future<List<SeedProfile>> Function() onLoadSeedProfiles;
  final Future<void> Function() onDeleteAccount;
  final Future<Map<String, dynamic>> Function() onLoadProfileRaw;
  final Future<void> Function(ProfileTraitDefinition def, Object? value)
      onSetTrait;
  final Future<void> Function(
    String traitKey, {
    required bool visibleInProfile,
    required bool useForMatching,
    required bool useForFilters,
  }) onSetTraitVisibility;
  final Future<List<ProfilePrompt>> Function() onLoadProfilePrompts;
  final Future<void> Function(List<ProfilePrompt> prompts) onSaveProfilePrompts;
  final Future<({IntroAudio? audio, IntroVideo? video})> Function()
      onLoadIntroMedia;
  final Future<void> Function({
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) onUploadIntroAudio;
  final Future<void> Function() onDeleteIntroAudio;
  final Future<void> Function({
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) onUploadIntroVideo;
  final Future<void> Function() onDeleteIntroVideo;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenUpgrade;
  final VoidCallback? onOpenAiVisual;

  /// Modo Amigos: abre el selector de intención / la pantalla de grupos. Null =
  /// oculto (servicios no inyectados).
  final VoidCallback? onOpenFriendMode;
  final VoidCallback? onOpenGroups;

  /// Attra SafeDate: abre el centro de seguridad. Null = oculto (flag OFF).
  final VoidCallback? onOpenSafeDate;

  /// Tienda de consumibles (Boosts y Attra Swipes). Existía pero no era
  /// alcanzable desde ninguna pantalla: nadie podía comprarlos.
  final VoidCallback? onOpenBoostStore;

  /// Activa/desactiva Slow Dating (toggle destacado en el perfil).
  final Future<void> Function(bool value)? onSetSlowDating;

  final String currentPlanLabel;
  final bool isProUser;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  ProfileCompletionState? _profile;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si cambió la completitud del usuario (p. ej. al persistir la ubicación
    // desde el feed) o el nº de fotos, recarga la tarjeta para reflejar el %.
    if (oldWidget.user?.profileCompletionPercent !=
        widget.user?.profileCompletionPercent) {
      _reload();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Abre una VISTA PREVIA del propio perfil tal y como lo ve el resto (mismo
  /// visor que se usa desde los chats), construido con los datos del usuario.
  Future<void> _previewProfile() async {
    final NavigatorState nav = Navigator.of(context);
    setState(() => _busy = true);
    SeedProfile? profile;
    try {
      final Map<String, dynamic> raw = await widget.onLoadProfileRaw();
      profile = SeedProfile.fromMap(widget.user?.uid ?? 'me', raw);
    } catch (_) {
      profile = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar tu perfil.')),
      );
      return;
    }
    nav.push(MaterialPageRoute<void>(
      builder: (_) => ProfileViewScreen(profile: profile!),
    ));
  }

  Future<void> _openEditTraits() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EditTraitsScreen(
        loadData: widget.onLoadProfileRaw,
        onSetTrait: widget.onSetTrait,
        onSetVisibility: widget.onSetTraitVisibility,
      ),
    ));
    if (mounted) _reload(); // refresca el score al volver
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ProfileCompletionState profile = await widget.onLoadProfileState();
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el estado del perfil. ($error)';
      });
    }
  }

  Future<void> _uploadPhoto(ImageSource source) async {
    final XFile? file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1440,
    );
    if (file == null) {
      return;
    }
    final int dot = file.name.lastIndexOf('.');
    final String extension = dot > -1 ? file.name.substring(dot + 1) : 'jpg';
    final Uint8List bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await runWithAttraLoader(
        context,
        () async {
          await widget.onUploadAdditionalPhoto(
            photoBytes: bytes,
            fileExtension: extension,
            source: source == ImageSource.camera ? 'camera' : 'gallery',
          );
          await _reload();
        },
        message: 'Subiendo foto…',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deletePhoto(String storagePath) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDeleteAdditionalPhoto(storagePath);
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (_busy) {
      return;
    }

    final bool? firstConfirmation = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Eliminar cuenta'),
          content: const Text(
            'Esta accion elimina tu cuenta y tus datos principales de forma permanente.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );

    if (firstConfirmation != true || !mounted) {
      return;
    }

    final bool? secondConfirmation = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmacion final'),
          content: const Text(
            'Confirmas que quieres eliminar definitivamente tu cuenta? Esta accion no se puede deshacer.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onError,
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Eliminar cuenta'),
            ),
          ],
        );
      },
    );

    if (secondConfirmation != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDeleteAccount();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ProfileCompletionState profile = _profile ??
        const ProfileCompletionState(
          percent: 0,
          pendingTasks: <String>[],
          availableRewards: <String>[],
          claimedRewards: <String>[],
          additionalPhotos: <AdditionalPhoto>[],
          prompts: <String>[],
          locationPermissionStatus: 'unknown',
          locationGranted: false,
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const _AttraTitleLogo(),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _reload,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpacing.pageInset(context), 12,
              AppSpacing.pageInset(context), 32),
          child: AttraContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeaderCard(theme),
                const SizedBox(height: 32),
                _buildAdditionalPhotosCard(theme, profile),
                const SizedBox(height: 32),
                _buildPromptsCard(theme, profile),
                const SizedBox(height: 32),
                IntroMediaEditor(
                  loadMedia: widget.onLoadIntroMedia,
                  onUploadAudio: widget.onUploadIntroAudio,
                  onDeleteAudio: widget.onDeleteIntroAudio,
                  onUploadVideo: widget.onUploadIntroVideo,
                  onDeleteVideo: widget.onDeleteIntroVideo,
                ),
                const SizedBox(height: 32),
                ProfileStrengthCard(
                  percent: profile.percent,
                  onEdit: _openEditTraits,
                  pendingTasks: profile.pendingTasks,
                ),
                const SizedBox(height: 8),
                Text(
                  'Completa más datos para mejorar la relevancia del matching y desbloquear recompensas.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                const AttraSectionHeading(title: 'Tu experiencia'),
                const SizedBox(height: 12),
                Material(
                  color: context.colors.surface,
                  child: Column(
                    children: <Widget>[
                      if (widget.onOpenFriendMode != null)
                        _buildFriendModeCard(theme),
                      if (widget.onSetSlowDating != null)
                        _buildSlowDatingCard(theme),
                      if (widget.onOpenGroups != null) _buildGroupsCard(theme),
                      if (widget.onOpenSafeDate != null)
                        _buildSafeDateCard(theme),
                      if (widget.onOpenAiVisual != null)
                        _buildAiVisualCard(theme),
                      if (widget.onOpenBoostStore != null)
                        _buildBoostStoreCard(theme),
                      if (widget.onOpenUpgrade != null)
                        _buildUpgradeCard(theme),
                      if (widget.onOpenSettings != null)
                        _buildSettingsCard(theme),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildLogoutButton(theme),
                const SizedBox(height: 24),
                _buildDangerZoneCard(theme),
                if (_error != null || widget.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error ?? widget.errorMessage!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    final String displayName = widget.user?.displayName ?? 'Usuario';
    final String email = widget.user?.email ?? 'Sin email';

    final String photoUrl = widget.user?.photoUrl ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(displayName, style: theme.textTheme.headlineLarge),
        ),
        const SizedBox(height: 6),
        Text(email, style: theme.textTheme.bodyMedium),
        // Attra Clear §8: badge positivo (lo escribe el backend).
        if (widget.user?.hasReliabilityBadge ?? false) ...<Widget>[
          const SizedBox(height: 6),
          const ReliabilityBadge(compact: true),
        ],
        if (photoUrl.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          Semantics(
            image: true,
            label: 'Tu foto principal',
            child: ExcludeSemantics(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: AttraImage(
                    url: photoUrl,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _busy ? null : _previewProfile,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Ver mi perfil'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _openEditTraits,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar información'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpgradeCard(ThemeData theme) {
    return _serviceRow(
      icon: Icons.workspace_premium_outlined,
      title: widget.isProUser
          ? 'Tu plan: ${widget.currentPlanLabel}'
          : 'Mejora a Attra Plus o Pro',
      subtitle: widget.isProUser
          ? 'Gestiona tu suscripción y compara los planes.'
          : 'Plan actual: ${widget.currentPlanLabel}. Ve todos tus '
              'likes, filtros avanzados y la IA visual de Pro.',
      onTap: widget.onOpenUpgrade,
    );
  }

  /// Modo Amigos: muestra el modo actual y abre el selector.
  Widget _buildFriendModeCard(ThemeData theme) {
    final IntentMode mode = widget.user?.intentMode ?? IntentMode.dating;
    final IntentModeVisual v = IntentModeVisual.of(mode);
    return _serviceRow(
      icon: v.icon,
      title: 'Qué buscas',
      subtitle: 'Ahora: ${v.label}. Toca para cambiar.',
      onTap: widget.onOpenFriendMode,
    );
  }

  /// Attra SafeDate: acceso al centro de seguridad en citas.
  Widget _buildSafeDateCard(ThemeData theme) {
    return _serviceRow(
      icon: Icons.shield_moon_outlined,
      title: 'SafeDate',
      subtitle: 'Queda con más tranquilidad y avisa a quien confías.',
      onTap: widget.onOpenSafeDate,
    );
  }

  /// Boosts y Attra Swipes: saldo y compra. La hoja existía desde hacía tiempo
  /// pero no se abría desde ningún sitio, así que los consumibles del catálogo
  /// no se podían comprar.
  Widget _buildBoostStoreCard(ThemeData theme) {
    final int boosts = widget.user?.boostBalance ?? 0;
    final int swipes = widget.user?.swipeBalance ?? 0;
    return _serviceRow(
      key: const ValueKey<String>('profile-boost-store'),
      icon: Icons.rocket_launch_outlined,
      title: 'Boosts y Swipes',
      subtitle: 'Tienes $boosts boosts y $swipes swipes.',
      onTap: widget.onOpenBoostStore,
    );
  }

  /// Modo Amigos: acceso a grupos y planes.
  Widget _buildGroupsCard(ThemeData theme) {
    return _serviceRow(
      icon: Icons.groups_outlined,
      title: 'Grupos y planes',
      subtitle: 'Únete o crea grupos por ciudad e intereses.',
      onTap: widget.onOpenGroups,
    );
  }

  Widget _buildAiVisualCard(ThemeData theme) {
    return _serviceRow(
      icon: Icons.auto_awesome_outlined,
      title: 'IA visual · Pro',
      subtitle:
          'Encuentra parecidos a una foto de referencia y mejora tu perfil.',
      onTap: widget.onOpenAiVisual,
    );
  }

  Widget _buildSettingsCard(ThemeData theme) {
    return _serviceRow(
      icon: Icons.settings_outlined,
      title: 'Ajustes',
      subtitle: 'Privacidad, notificaciones, cuenta…',
      onTap: widget.onOpenSettings,
    );
  }

  Widget _serviceRow({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      key: key,
      minTileHeight: 72,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, size: 22, color: context.colors.textSecondary),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: Text(subtitle, style: theme.textTheme.bodyMedium),
      trailing: Icon(Icons.chevron_right,
          size: 20, color: context.colors.textSecondary),
      onTap: onTap,
    );
  }

  /// Toggle DESTACADO de Slow Dating en el perfil. Al activarlo, explica en qué
  /// consiste; al confirmar, persiste el ajuste y el feed cambia su lógica.
  Widget _buildSlowDatingCard(ThemeData theme) {
    final bool active = widget.user?.slowDatingEnabled ?? false;
    return SwitchListTile.adaptive(
      value: active,
      onChanged: _busy ? null : _toggleSlowDating,
      secondary: Icon(Icons.spa_outlined,
          size: 22, color: context.colors.textSecondary),
      title: Text('Slow Dating', style: theme.textTheme.bodyLarge),
      subtitle: Text(
        '${active ? 'Activo. ' : ''}Citas con calma: menos perfiles pero más afines a ti.',
        style: theme.textTheme.bodyMedium,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Future<void> _toggleSlowDating(bool value) async {
    final Future<void> Function(bool)? cb = widget.onSetSlowDating;
    if (cb == null) return;
    if (value) {
      final bool? ok = await _showSlowDatingInfo();
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await cb(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(value
              ? 'Slow Dating activado. Tu feed irá con calma 🌿'
              : 'Slow Dating desactivado.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showSlowDatingInfo() {
    final ThemeData theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        icon:
            Icon(Icons.spa_rounded, color: theme.colorScheme.primary, size: 36),
        title: const Text('Slow Dating', textAlign: TextAlign.center),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Citas con calma, no deslizar sin parar. Si lo activas:'),
            SizedBox(height: 12),
            _InfoRow(
                icon: Icons.tune_rounded,
                text:
                    'Ves MENOS perfiles, pero más afines a ti (intereses y lo que buscáis).'),
            SizedBox(height: 8),
            _InfoRow(
                icon: Icons.favorite_rounded,
                text:
                    'Prioriza conexiones intencionales sobre el match masivo.'),
            SizedBox(height: 8),
            _InfoRow(
                icon: Icons.toggle_off_rounded,
                text: 'Puedes desactivarlo cuando quieras. No borra a nadie.'),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalPhotosCard(
    ThemeData theme,
    ProfileCompletionState profile,
  ) {
    final int remaining = 5 - profile.additionalPhotos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AttraSectionHeading(
          title: 'Fotos adicionales',
          subtitle: 'Hasta 5 fotos, además de tu selfie principal.',
        ),
        const SizedBox(height: 16),
        Text(
          'Restantes: $remaining',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        if (profile.additionalPhotos.isEmpty)
          Text('Aún no has subido fotos adicionales.',
              style: theme.textTheme.bodyMedium)
        else ...<Widget>[
          if (widget.onReorderPhotos != null &&
              profile.additionalPhotos.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Mantén pulsada una foto y arrástrala para cambiar el orden.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.colors.textMuted),
              ),
            ),
          _ReorderablePhotos(
            key: ValueKey<String>(profile.additionalPhotos
                .map((AdditionalPhoto p) => p.storagePath)
                .join(',')),
            photos: profile.additionalPhotos,
            busy: _busy,
            onDelete: _deletePhoto,
            onReorder: widget.onReorderPhotos,
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _busy || remaining <= 0
                  ? null
                  : () => _uploadPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: const Text('Subir de galería'),
            ),
            TextButton.icon(
              onPressed: _busy || remaining <= 0
                  ? null
                  : () => _uploadPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined, size: 20),
              label: const Text('Tomar foto'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPromptsCard(ThemeData theme, ProfileCompletionState profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AttraSectionHeading(
          title: 'Preguntas de perfil',
          subtitle: 'Respuestas para empezar una conversación.',
        ),
        const SizedBox(height: 8),
        if (profile.prompts.isEmpty)
          const Text('Añade una respuesta para que tu perfil no parezca '
              'un contrato de alquiler.')
        else
          ...profile.prompts.map((String prompt) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(prompt, style: theme.textTheme.bodyLarge),
              )),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _openPromptsEditor,
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            label: const Text('Gestionar preguntas'),
          ),
        ),
      ],
    );
  }

  Future<void> _openPromptsEditor() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfilePromptsEditorScreen(
        loadPrompts: widget.onLoadProfilePrompts,
        savePrompts: widget.onSaveProfilePrompts,
      ),
    ));
    if (mounted) _reload(); // refresca el espejo legacy y el score
  }

  Future<void> _confirmLogout() async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Cerrar sesión'),
            content: const Text('¿Seguro que quieres cerrar sesión?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ) ??
        false;
    if (ok) widget.onLogout();
  }

  Widget _buildLogoutButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _busy ? null : _confirmLogout,
        child: const Text('Cerrar sesión'),
      ),
    );
  }

  Widget _buildDangerZoneCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AttraSectionHeading(title: 'Cuenta y datos'),
        const SizedBox(height: 8),
        Text(
          'Eliminar tu cuenta borrara tu acceso y tus datos principales.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _confirmDeleteAccount,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Eliminar cuenta'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _AttraTitleLogo extends StatelessWidget {
  const _AttraTitleLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Attra',
      image: true,
      child: Image.asset(
        'assets/images/ATTRA.png',
        height: 28,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        color: context.colors.textPrimary,
      ),
    );
  }
}

/// Fotos adicionales reordenables por ARRASTRE (mantener pulsado y mover). Lista
/// horizontal con eliminar por foto. Persiste el nuevo orden vía [onReorder].
class _ReorderablePhotos extends StatefulWidget {
  const _ReorderablePhotos({
    super.key,
    required this.photos,
    required this.busy,
    required this.onDelete,
    required this.onReorder,
  });

  final List<AdditionalPhoto> photos;
  final bool busy;
  final void Function(String storagePath) onDelete;
  final Future<void> Function(List<String> orderedStoragePaths)? onReorder;

  @override
  State<_ReorderablePhotos> createState() => _ReorderablePhotosState();
}

class _ReorderablePhotosState extends State<_ReorderablePhotos> {
  late final List<AdditionalPhoto> _items = <AdditionalPhoto>[...widget.photos];

  void _onReorder(int oldIndex, int newIndex) {
    if (widget.onReorder == null) return;
    setState(() {
      // ReorderableListView entrega newIndex desplazado al mover hacia abajo.
      if (newIndex > oldIndex) newIndex -= 1;
      final AdditionalPhoto moved = _items.removeAt(oldIndex);
      _items.insert(newIndex, moved);
    });
    widget.onReorder!(
      _items.map((AdditionalPhoto p) => p.storagePath).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: widget.onReorder != null && !widget.busy,
        itemCount: _items.length,
        onReorder: _onReorder,
        proxyDecorator:
            (Widget child, int index, Animation<double> animation) => Material(
          color: Colors.transparent,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: child,
        ),
        itemBuilder: (BuildContext context, int index) {
          final AdditionalPhoto photo = _items[index];
          return Padding(
            key: ValueKey<String>(photo.storagePath),
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: <Widget>[
                AttraImage(
                  url: photo.url,
                  width: 144,
                  height: 192,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
                // Nº de posición (1 = principal de las adicionales).
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xCC111111),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${index + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                    tooltip: 'Eliminar foto ${index + 1}',
                    onPressed: widget.busy
                        ? null
                        : () => widget.onDelete(photo.storagePath),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: const Color(0xCC111111),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

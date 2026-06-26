import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../widgets/attra_image.dart';
import '../../auth/domain/app_user.dart';
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

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onUploadAdditionalPhoto(
        photoBytes: bytes,
        fileExtension: extension,
        source: source == ImageSource.camera ? 'camera' : 'gallery',
      );
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

  Future<void> _claimReward(String rewardId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onClaimReward(rewardId);
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
                foregroundColor: Colors.white,
                backgroundColor: Colors.red,
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
      appBar: AppBar(
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
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildHeaderCard(theme, profile),
                  const SizedBox(height: 12),
                  if (widget.onOpenUpgrade != null) ...<Widget>[
                    _buildUpgradeCard(theme),
                    const SizedBox(height: 12),
                  ],
                  if (widget.onOpenAiVisual != null) ...<Widget>[
                    _buildAiVisualCard(theme),
                    const SizedBox(height: 12),
                  ],
                  if (widget.onOpenSettings != null) ...<Widget>[
                    _buildSettingsCard(theme),
                    const SizedBox(height: 12),
                  ],
                  if (widget.onSetSlowDating != null) ...<Widget>[
                    _buildSlowDatingCard(theme),
                    const SizedBox(height: 12),
                  ],
                  _buildChecklistCard(theme, profile),
                  const SizedBox(height: 12),
                  _buildRewardsCard(theme, profile),
                  const SizedBox(height: 12),
                  _buildAdditionalPhotosCard(theme, profile),
                  const SizedBox(height: 12),
                  _buildPromptsCard(theme, profile),
                  const SizedBox(height: 12),
                  IntroMediaEditor(
                    loadMedia: widget.onLoadIntroMedia,
                    onUploadAudio: widget.onUploadIntroAudio,
                    onDeleteAudio: widget.onDeleteIntroAudio,
                    onUploadVideo: widget.onUploadIntroVideo,
                    onDeleteVideo: widget.onDeleteIntroVideo,
                  ),
                  const SizedBox(height: 12),
                  _buildLogoutButton(theme),
                  const SizedBox(height: 12),
                  _buildDangerZoneCard(theme),
                  if (_error != null ||
                      widget.errorMessage != null) ...<Widget>[
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
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, ProfileCompletionState profile) {
    final String displayName = widget.user?.displayName ?? 'Usuario';
    final String email = widget.user?.email ?? 'Sin email';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 28,
                  backgroundImage: (widget.user?.photoUrl?.isNotEmpty ?? false)
                      ? CachedNetworkImageProvider(widget.user!.photoUrl!)
                      : null,
                  child: (widget.user?.photoUrl?.isNotEmpty ?? false)
                      ? null
                      : const Icon(Icons.person, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(displayName, style: theme.textTheme.titleLarge),
                      Text(email, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _previewProfile,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Ver mi perfil'),
              ),
            ),
            const SizedBox(height: 16),
            ProfileStrengthCard(
              percent: profile.percent,
              onEdit: _openEditTraits,
              pendingTasks: profile.pendingTasks,
            ),
            const SizedBox(height: 8),
            Text(
              'Completa mas datos para mejorar la relevancia del matching y desbloquear recompensas.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeCard(ThemeData theme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpenUpgrade,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF1D6A96), Color(0xFFB8860B)],
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.workspace_premium,
                  color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.isProUser
                          ? 'Tu plan: ${widget.currentPlanLabel}'
                          : 'Mejora a Attra Plus o Pro',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isProUser
                          ? 'Gestiona tu suscripción y compara los planes.'
                          : 'Plan actual: ${widget.currentPlanLabel}. Ve todos tus '
                              'likes, filtros avanzados y la IA visual de Pro.',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiVisualCard(ThemeData theme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
        title: const Text('IA visual · Pro'),
        subtitle: const Text(
            'Encuentra parecidos a una foto de referencia y mejora tu perfil.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenAiVisual,
      ),
    );
  }

  Widget _buildSettingsCard(ThemeData theme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading:
            Icon(Icons.settings_outlined, color: theme.colorScheme.primary),
        title: const Text('Ajustes'),
        subtitle: const Text('Privacidad, notificaciones, cuenta…'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenSettings,
      ),
    );
  }

  /// Toggle DESTACADO de Slow Dating en el perfil. Al activarlo, explica en qué
  /// consiste; al confirmar, persiste el ajuste y el feed cambia su lógica.
  Widget _buildSlowDatingCard(ThemeData theme) {
    final bool active = widget.user?.slowDatingEnabled ?? false;
    final Color accent = theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: active
                ? accent.withValues(alpha: 0.6)
                : theme.colorScheme.outline.withValues(alpha: 0.4)),
      ),
      child: SwitchListTile(
        value: active,
        onChanged: _busy ? null : _toggleSlowDating,
        secondary: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.16),
          child: Icon(Icons.spa_rounded, color: accent),
        ),
        title: Row(
          children: <Widget>[
            const Flexible(child: Text('Slow Dating')),
            const SizedBox(width: 8),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Activo',
                    style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        subtitle:
            const Text('Citas con calma: menos perfiles pero más afines a ti.'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
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

  Widget _buildChecklistCard(ThemeData theme, ProfileCompletionState profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Completa tu perfil', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (profile.pendingTasks.isEmpty)
              Text('No tienes tareas pendientes.',
                  style: theme.textTheme.bodyMedium)
            else
              ...profile.pendingTasks.map((String task) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.check_circle_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(task)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardsCard(ThemeData theme, ProfileCompletionState profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Recompensas de completitud',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (profile.availableRewards.isEmpty)
              Text(
                'Aun no hay recompensas disponibles. Sube tu porcentaje para desbloquear hitos.',
                style: theme.textTheme.bodyMedium,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profile.availableRewards.map((String rewardId) {
                  return FilledButton(
                    onPressed: _busy ? null : () => _claimReward(rewardId),
                    child: Text('Reclamar $rewardId'),
                  );
                }).toList(growable: false),
              ),
            if (profile.claimedRewards.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Reclamadas: ${profile.claimedRewards.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalPhotosCard(
    ThemeData theme,
    ProfileCompletionState profile,
  ) {
    final int remaining = 5 - profile.additionalPhotos.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Fotos adicionales', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Puedes subir hasta 5 fotos adicionales aparte de tu selfie principal.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _busy || remaining <= 0
                      ? null
                      : () => _uploadPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Subir de galeria'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || remaining <= 0
                      ? null
                      : () => _uploadPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Tomar foto'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Restantes: $remaining',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (profile.additionalPhotos.isEmpty)
              Text('Aun no has subido fotos adicionales.',
                  style: theme.textTheme.bodyMedium)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: profile.additionalPhotos.map((AdditionalPhoto photo) {
                  return Stack(
                    children: <Widget>[
                      AttraImage(
                        url: photo.url,
                        width: 96,
                        height: 96,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: InkWell(
                          onTap: _busy
                              ? null
                              : () => _deletePhoto(photo.storagePath),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptsCard(ThemeData theme, ProfileCompletionState profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Preguntas de perfil', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Añade respuestas que ayuden a empezar una conversación.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (profile.prompts.isEmpty)
              const Text('Añade una respuesta para que tu perfil no parezca '
                  'un contrato de alquiler.')
            else
              ...profile.prompts.take(3).map((String prompt) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.chat_bubble_outline, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(prompt,
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
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
        ),
      ),
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

  Widget _buildLogoutButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _busy ? null : widget.onLogout,
        child: const Text('Cerrar sesión'),
      ),
    );
  }

  Widget _buildDangerZoneCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Zona de riesgo', style: theme.textTheme.titleMedium),
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
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
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
      ),
    );
  }
}

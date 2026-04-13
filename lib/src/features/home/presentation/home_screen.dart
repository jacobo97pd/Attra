import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/domain/app_user.dart';
import '../../profile/domain/profile_state.dart';

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

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _promptController = TextEditingController();

  ProfileCompletionState? _profile;
  List<SeedProfile> _seedProfiles = const <SeedProfile>[];
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
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ProfileCompletionState profile = await widget.onLoadProfileState();
      final List<SeedProfile> seeds = await widget.onLoadSeedProfiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _seedProfiles = seeds;
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

  Future<void> _addPrompt() async {
    final String prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAddPrompt(prompt);
      _promptController.clear();
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
        title: const Text('Attra'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _reload,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _busy ? null : widget.onLogout,
            tooltip: 'Cerrar sesion',
            icon: const Icon(Icons.logout),
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
                  _buildChecklistCard(theme, profile),
                  const SizedBox(height: 12),
                  _buildRewardsCard(theme, profile),
                  const SizedBox(height: 12),
                  _buildAdditionalPhotosCard(theme, profile),
                  const SizedBox(height: 12),
                  _buildPromptsCard(theme, profile),
                  const SizedBox(height: 12),
                  _buildSeedProfilesCard(theme),
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
    final double progress = profile.percent / 100;

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
                      ? NetworkImage(widget.user!.photoUrl!)
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
            const SizedBox(height: 16),
            Text(
              'Tu perfil esta completado al ${profile.percent}%',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: progress, minHeight: 10),
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          photo.url,
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
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
            Text('Prompts opcionales', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Anade un prompt o dato extra de personalidad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _addPrompt,
                child: const Text('Guardar prompt'),
              ),
            ),
            const SizedBox(height: 8),
            if (profile.prompts.isEmpty)
              const Text('Todavia no hay prompts guardados.')
            else
              ...profile.prompts.map((String prompt) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('- $prompt'),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildSeedProfilesCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Seed profiles (testing interno)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Perfiles sinteticos coherentes para pruebas de feed y matching futuro.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_seedProfiles.isEmpty)
              const Text('No hay seed profiles cargados en Firestore.')
            else
              ..._seedProfiles.take(5).map((SeedProfile seed) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: Text(
                    '${seed.displayName} - ${seed.city}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'scenario: ${seed.botScenario} - quality: ${seed.seedQualityScore}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZoneCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer.withOpacity(0.25),
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/domain/app_user.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_draft.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onLoadDraft,
    required this.onSaveDraft,
    required this.onUploadLiveSelfieDraft,
    required this.onSubmitOnboarding,
    required this.onLogout,
    this.user,
    this.errorMessage,
  });

  final AppUser? user;
  final String? errorMessage;
  final Future<OnboardingDraft> Function() onLoadDraft;
  final Future<void> Function(OnboardingDraft draft) onSaveDraft;
  final Future<LiveSelfieDraftUpload> Function({
    required Uint8List liveSelfieBytes,
    required String liveSelfieFileExtension,
  }) onUploadLiveSelfieDraft;
  final Future<void> Function({
    required OnboardingDraft draft,
    Uint8List? liveSelfieBytes,
    String? liveSelfieFileExtension,
  }) onSubmitOnboarding;
  final VoidCallback onLogout;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const int _totalSteps = 7;
  static const int _minimumAge = 18;

  final PageController _pageController = PageController();
  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController _visibleNameController;
  late final TextEditingController _birthCityController;
  late final TextEditingController _currentCityController;
  late final TextEditingController _heightController;
  late final TextEditingController _bioController;

  Timer? _draftDebounce;
  String? _lastPersistedFingerprint;
  bool _hasPendingDraftChanges = false;

  OnboardingDraft? _draft;
  bool _loadingDraft = true;
  bool _submitting = false;
  String? _localError;

  Uint8List? _liveSelfieBytes;
  String _liveSelfieFileExtension = 'jpg';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _visibleNameController = TextEditingController();
    _birthCityController = TextEditingController();
    _currentCityController = TextEditingController();
    _heightController = TextEditingController();
    _bioController = TextEditingController();

    _visibleNameController.addListener(_onTextInputChanged);
    _birthCityController.addListener(_onTextInputChanged);
    _currentCityController.addListener(_onTextInputChanged);
    _heightController.addListener(_onTextInputChanged);
    _bioController.addListener(_onTextInputChanged);

    _loadDraft();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftDebounce?.cancel();

    _visibleNameController.removeListener(_onTextInputChanged);
    _birthCityController.removeListener(_onTextInputChanged);
    _currentCityController.removeListener(_onTextInputChanged);
    _heightController.removeListener(_onTextInputChanged);
    _bioController.removeListener(_onTextInputChanged);

    unawaited(_persistCurrentDraft(force: true));

    _pageController.dispose();
    _visibleNameController.dispose();
    _birthCityController.dispose();
    _currentCityController.dispose();
    _heightController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _draftDebounce?.cancel();
      unawaited(_persistCurrentDraft(force: true));
    }
  }

  Future<void> _loadDraft() async {
    try {
      final OnboardingDraft loadedDraft = await widget.onLoadDraft();
      if (!mounted) {
        return;
      }

      _visibleNameController.text = loadedDraft.visibleName;
      _birthCityController.text = loadedDraft.birthCity;
      _currentCityController.text = loadedDraft.currentCity;
      _heightController.text = loadedDraft.heightCm?.toString() ?? '';
      _bioController.text = loadedDraft.bio;

      setState(() {
        _draft = loadedDraft;
        _loadingDraft = false;
        _localError = null;
      });

      _lastPersistedFingerprint = _draftFingerprint(loadedDraft);
      _hasPendingDraftChanges = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _pageController
            .jumpToPage(loadedDraft.currentStep.clamp(0, _totalSteps - 1));
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final OnboardingDraft fallbackDraft =
          OnboardingDraft.fromUser(widget.user);
      _visibleNameController.text = fallbackDraft.visibleName;
      _birthCityController.text = fallbackDraft.birthCity;
      _currentCityController.text = fallbackDraft.currentCity;
      _heightController.text = fallbackDraft.heightCm?.toString() ?? '';
      _bioController.text = fallbackDraft.bio;
      setState(() {
        _loadingDraft = false;
        _localError =
            'No se pudo cargar el onboarding guardado. Intenta de nuevo. ($error)';
        _draft = fallbackDraft;
      });
      _lastPersistedFingerprint = _draftFingerprint(fallbackDraft);
      _hasPendingDraftChanges = false;
    }
  }

  void _onTextInputChanged() {
    final OnboardingDraft? current = _draft;
    if (current == null) {
      return;
    }

    _draft = _syncControllersIntoDraft(current);
    _markDraftDirtyAndDebounceSave();
  }

  Future<void> _persistCurrentDraft({bool force = false}) async {
    final OnboardingDraft? current = _draft;
    if (current == null) {
      return;
    }

    final OnboardingDraft normalized = _syncControllersIntoDraft(current);
    final String fingerprint = _draftFingerprint(normalized);

    if (!force) {
      if (!_hasPendingDraftChanges) {
        return;
      }
      if (_lastPersistedFingerprint == fingerprint) {
        _hasPendingDraftChanges = false;
        return;
      }
    }

    try {
      await widget.onSaveDraft(normalized);
      _draft = normalized;
      _lastPersistedFingerprint = fingerprint;
      _hasPendingDraftChanges = false;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localError = 'No se pudo guardar progreso del onboarding. ($error)';
      });
    }
  }

  void _markDraftDirtyAndDebounceSave() {
    _hasPendingDraftChanges = true;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(_persistCurrentDraft()),
    );
  }

  Future<void> _captureLiveSelfie() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 1080,
      );
      if (photo == null) {
        return;
      }

      final Uint8List bytes = await photo.readAsBytes();
      final String extension = _extractFileExtension(photo.name, photo.path);

      final LiveSelfieDraftUpload upload = await widget.onUploadLiveSelfieDraft(
        liveSelfieBytes: bytes,
        liveSelfieFileExtension: extension,
      );

      final DateTime capturedAt = upload.capturedAt;
      final OnboardingDraft base =
          _draft ?? OnboardingDraft.fromUser(widget.user);
      final OnboardingDraft updatedDraft = base.copyWith(
        liveSelfieCaptured: true,
        liveSelfieCapturedAt: capturedAt,
        liveSelfieVerified: false,
        lastLiveSelfieAt: capturedAt,
        liveSelfiePublicPhotoUrl: upload.publicPhotoUrl,
        liveSelfiePublicStoragePath: upload.publicStoragePath,
        liveSelfiePrivatePhotoUrl: upload.privatePhotoUrl,
        liveSelfiePrivateStoragePath: upload.privateStoragePath,
        liveSelfieCaptureMethod: upload.captureMethod,
        liveSelfieStatus: upload.status,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _liveSelfieBytes = bytes;
        _liveSelfieFileExtension = extension;
        _draft = updatedDraft;
        _localError = null;
      });

      await _persistCurrentDraft(force: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localError =
            'No se pudo tomar la selfie. Revisa permisos de camara. ($error)';
      });
    }
  }

  Future<void> _goNext() async {
    final OnboardingDraft? current = _draft;
    if (current == null || _submitting) {
      return;
    }

    final OnboardingDraft normalized = _syncControllersIntoDraft(current);
    final String? validationError =
        _validateStep(normalized, normalized.currentStep);
    if (validationError != null) {
      setState(() {
        _localError = validationError;
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    if (normalized.currentStep == _totalSteps - 1) {
      await _submit(normalized);
      return;
    }

    final int nextStep = normalized.currentStep + 1;
    setState(() {
      _draft = normalized.copyWith(currentStep: nextStep);
    });

    await _persistCurrentDraft(force: true);
    if (!mounted) {
      return;
    }
    await _pageController.animateToPage(
      nextStep,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _goBack() async {
    final OnboardingDraft? current = _draft;
    if (current == null || current.currentStep == 0 || _submitting) {
      return;
    }

    final OnboardingDraft normalized = _syncControllersIntoDraft(current);
    final int previousStep = normalized.currentStep - 1;
    setState(() {
      _draft = normalized.copyWith(currentStep: previousStep);
    });

    await _persistCurrentDraft(force: true);
    if (!mounted) {
      return;
    }

    await _pageController.animateToPage(
      previousStep,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _submit(OnboardingDraft normalizedDraft) async {
    if (!_hasLiveSelfie(normalizedDraft)) {
      setState(() {
        _localError =
            'La primera foto debe ser una selfie tomada en este momento desde la camara.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _localError = null;
    });

    try {
      await _persistCurrentDraft(force: true);

      await widget.onSubmitOnboarding(
        draft: normalizedDraft.copyWith(currentStep: _totalSteps - 1),
        liveSelfieBytes: _liveSelfieBytes,
        liveSelfieFileExtension: _liveSelfieFileExtension,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localError =
            'No se pudo completar onboarding. Intenta de nuevo. ($error)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  bool _hasLiveSelfie(OnboardingDraft draft) {
    return draft.liveSelfieCaptured &&
        (_liveSelfieBytes != null ||
            draft.liveSelfiePublicPhotoUrl.isNotEmpty ||
            draft.liveSelfiePrivatePhotoUrl.isNotEmpty);
  }

  OnboardingDraft _syncControllersIntoDraft(OnboardingDraft draft) {
    final int? parsedHeight = int.tryParse(_heightController.text.trim());
    final String normalizedBirthCity =
        _normalizeToken(_birthCityController.text);
    final String normalizedCurrentCity =
        _normalizeToken(_currentCityController.text);
    return draft.copyWith(
      visibleName: _visibleNameController.text.trim(),
      birthCity: _birthCityController.text.trim(),
      birthCityNormalized: normalizedBirthCity,
      currentCity: _currentCityController.text.trim(),
      currentCityNormalized: normalizedCurrentCity,
      bio: _bioController.text.trim(),
      heightCm: parsedHeight,
      clearHeight: _heightController.text.trim().isEmpty,
    );
  }

  String? _validateStep(OnboardingDraft draft, int step) {
    switch (step) {
      case 0:
        if (!_hasLiveSelfie(draft)) {
          return 'Debes tomar una selfie real con la camara para continuar.';
        }
        return null;
      case 1:
        if (draft.birthDate == null) {
          return 'Selecciona tu fecha de nacimiento.';
        }
        if (_calculateAge(draft.birthDate!) < _minimumAge) {
          return 'Debes tener al menos $_minimumAge anos para usar la app.';
        }
        if (draft.gender.isEmpty) {
          return 'Selecciona tu genero.';
        }
        if (draft.birthCity.trim().isEmpty) {
          return 'La ciudad de nacimiento es obligatoria.';
        }
        if (draft.currentCity.trim().isEmpty) {
          return 'La ciudad actual es obligatoria.';
        }
        if (draft.languages.isEmpty) {
          return 'Selecciona al menos un idioma.';
        }
        return null;
      case 2:
        if (draft.heightCm == null) {
          return 'Indica tu altura en cm.';
        }
        if (draft.heightCm! < 120 || draft.heightCm! > 230) {
          return 'La altura debe estar entre 120 y 230 cm.';
        }
        if (draft.eyeColor.isEmpty ||
            draft.hairColor.isEmpty ||
            draft.hairType.isEmpty ||
            draft.bodyType.isEmpty) {
          return 'Completa todos los campos de apariencia.';
        }
        return null;
      case 3:
        if (draft.bio.trim().length < 20) {
          return 'Escribe una bio autentica de al menos 20 caracteres.';
        }
        if (draft.relationshipIntent.isEmpty) {
          return 'Selecciona tu intencion de relacion.';
        }
        return null;
      case 4:
        if (draft.smoking.isEmpty ||
            draft.drinking.isEmpty ||
            draft.fitnessLevel.isEmpty ||
            draft.wantsChildren.isEmpty ||
            draft.travelStyle.isEmpty) {
          return 'Completa todo el bloque de estilo de vida.';
        }
        return null;
      case 5:
        if (draft.fashionStyle.isEmpty) {
          return 'Selecciona al menos un estilo de moda.';
        }
        if (draft.personalityTags.isEmpty) {
          return 'Selecciona al menos una etiqueta de personalidad.';
        }
        return null;
      case 6:
        if (draft.interestedIn.isEmpty) {
          return 'Selecciona en quien tienes interes.';
        }
        if (draft.preferredAgeMin < _minimumAge ||
            draft.preferredAgeMax > 80 ||
            draft.preferredAgeMin > draft.preferredAgeMax) {
          return 'Rango de edad preferido invalido.';
        }
        if (draft.maxDistanceKm < 1 || draft.maxDistanceKm > 500) {
          return 'La distancia maxima debe estar entre 1 y 500 km.';
        }
        return null;
      default:
        return null;
    }
  }

  int _calculateAge(DateTime birthDate) {
    final DateTime now = DateTime.now();
    int age = now.year - birthDate.year;
    final bool hasBirthdayPassed = now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hasBirthdayPassed) {
      age -= 1;
    }
    return age;
  }

  String _extractFileExtension(String fileName, String filePath) {
    final String source = fileName.isNotEmpty ? fileName : filePath;
    final int dot = source.lastIndexOf('.');
    if (dot == -1 || dot == source.length - 1) {
      return 'jpg';
    }
    return source.substring(dot + 1).toLowerCase();
  }

  String _draftFingerprint(OnboardingDraft draft) {
    return jsonEncode(draft.toMap());
  }

  String _normalizeToken(String value) {
    final String lower = value.toLowerCase().trim();
    if (lower.isEmpty) {
      return '';
    }

    final StringBuffer buffer = StringBuffer();
    for (final int codePoint in lower.runes) {
      final String char = String.fromCharCode(codePoint);
      buffer.write(_latinMap[char] ?? char);
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> _requestLocationPermissionAndFix() async {
    final OnboardingDraft? current = _draft;
    if (current == null) {
      return;
    }

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _updateDraft(
          current.copyWith(
            locationPermissionGranted: false,
            locationPermissionStatus: 'service_disabled',
            clearLocationLatitude: true,
            clearLocationLongitude: true,
            locationUpdatedAt: DateTime.now(),
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _updateDraft(
          current.copyWith(
            locationPermissionGranted: false,
            locationPermissionStatus: 'denied',
            clearLocationLatitude: true,
            clearLocationLongitude: true,
            locationUpdatedAt: DateTime.now(),
          ),
        );
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _updateDraft(
          current.copyWith(
            locationPermissionGranted: false,
            locationPermissionStatus: 'denied_forever',
            clearLocationLatitude: true,
            clearLocationLongitude: true,
            locationUpdatedAt: DateTime.now(),
          ),
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      _updateDraft(
        current.copyWith(
          locationPermissionGranted: true,
          locationPermissionStatus: 'granted',
          locationLatitude: position.latitude,
          locationLongitude: position.longitude,
          locationUpdatedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      _updateDraft(
        current.copyWith(
          locationPermissionGranted: false,
          locationPermissionStatus: 'error',
          clearLocationLatitude: true,
          clearLocationLongitude: true,
          locationUpdatedAt: DateTime.now(),
        ),
      );
    }
  }

  void _continueWithoutLocation() {
    final OnboardingDraft? current = _draft;
    if (current == null) {
      return;
    }
    _updateDraft(
      current.copyWith(
        locationPermissionGranted: false,
        locationPermissionStatus: 'denied',
        clearLocationLatitude: true,
        clearLocationLongitude: true,
        locationUpdatedAt: DateTime.now(),
      ),
    );
  }

  String _locationStatusLabel(OnboardingDraft draft) {
    switch (draft.locationPermissionStatus) {
      case 'granted':
        return 'Ubicacion concedida';
      case 'denied':
        return 'Ubicacion no concedida';
      case 'denied_forever':
        return 'Ubicacion bloqueada por el sistema';
      case 'service_disabled':
        return 'Activa la ubicacion del dispositivo';
      case 'error':
        return 'No se pudo obtener tu ubicacion';
      default:
        return 'Todavia no hemos solicitado tu ubicacion';
    }
  }

  Color _locationStatusColor(ThemeData theme, OnboardingDraft draft) {
    switch (draft.locationPermissionStatus) {
      case 'granted':
        return Colors.green.shade700;
      case 'error':
      case 'denied_forever':
      case 'service_disabled':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_loadingDraft || _draft == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final OnboardingDraft draft = _draft!;
    final int step = draft.currentStep;
    final double progress = (step + 1) / _totalSteps;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa tu perfil'),
        actions: <Widget>[
          IconButton(
            onPressed: _submitting ? null : widget.onLogout,
            tooltip: 'Cerrar sesion',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Paso ${step + 1} de $_totalSteps',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  _buildSelfieStep(theme, draft),
                  _buildIdentityStep(theme, draft),
                  _buildAppearanceStep(theme, draft),
                  _buildPersonalStep(theme, draft),
                  _buildLifestyleStep(theme, draft),
                  _buildStyleStep(theme, draft),
                  _buildPreferencesStep(theme, draft),
                ],
              ),
            ),
            if (widget.errorMessage != null || _localError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  _localError ?? widget.errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: step == 0 || _submitting ? null : _goBack,
                      child: const Text('Atras'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _submitting ? null : _goNext,
                      child: Text(
                        _submitting
                            ? 'Guardando...'
                            : (step == _totalSteps - 1
                                ? 'Finalizar onboarding'
                                : 'Continuar'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelfieStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      title: 'Selfie en vivo obligatoria',
      subtitle:
          'Tu primera foto debe ser una selfie tomada ahora mismo desde la camara.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: _liveSelfieBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      _liveSelfieBytes!,
                      fit: BoxFit.cover,
                    ),
                  )
                : draft.liveSelfiePublicPhotoUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          draft.liveSelfiePublicPhotoUrl,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Center(
                        child: Text(
                          'Aun no has capturado tu selfie en vivo',
                          textAlign: TextAlign.center,
                        ),
                      ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _submitting ? null : _captureLiveSelfie,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_hasLiveSelfie(draft)
                ? 'Repetir selfie'
                : 'Tomar selfie ahora'),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      title: 'Identidad basica',
      subtitle: 'Informacion esencial para tu perfil publico.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _visibleNameController,
            decoration: const InputDecoration(
              labelText: 'Nombre visible *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _selectBirthDate(draft.birthDate),
            icon: const Icon(Icons.cake_outlined),
            label: Text(
              draft.birthDate == null
                  ? 'Seleccionar fecha de nacimiento *'
                  : 'Nacimiento: ${_formatDate(draft.birthDate!)}',
            ),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Genero *',
            options: _genderOptions,
            selected: draft.gender,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(gender: value)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _birthCityController,
            decoration: const InputDecoration(
              labelText: 'Ciudad de nacimiento *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currentCityController,
            decoration: const InputDecoration(
              labelText: 'Ciudad actual *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _buildMultiChoiceWrap(
            title: 'Idiomas *',
            options: _languageOptions,
            selected: draft.languages,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(languages: values)),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      title: 'Apariencia',
      subtitle: 'Describe rasgos generales sin entrar en detalles invasivos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _heightController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Altura (cm) *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Color de ojos *',
            options: _eyeColorOptions,
            selected: draft.eyeColor,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(eyeColor: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Color de pelo *',
            options: _hairColorOptions,
            selected: draft.hairColor,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(hairColor: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Tipo de pelo *',
            options: _hairTypeOptions,
            selected: draft.hairType,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(hairType: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Constitucion *',
            options: _bodyTypeOptions,
            selected: draft.bodyType,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(bodyType: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      title: 'Perfil personal',
      subtitle: 'Haz que tu perfil se sienta real y autentico.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _bioController,
            maxLines: 5,
            maxLength: 240,
            decoration: const InputDecoration(
              labelText: 'Bio *',
              hintText: 'Cuenta algo genuino sobre ti (minimo 20 caracteres).',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Que buscas *',
            options: _relationshipIntentOptions,
            selected: draft.relationshipIntent,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(relationshipIntent: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildLifestyleStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      title: 'Estilo de vida',
      subtitle: 'Compatibilidad sin juicios ni filtros rigidos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSingleChoiceWrap(
            title: 'Tabaco *',
            options: _smokingOptions,
            selected: draft.smoking,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(smoking: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Alcohol *',
            options: _drinkingOptions,
            selected: draft.drinking,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(drinking: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Nivel fitness *',
            options: _fitnessOptions,
            selected: draft.fitnessLevel,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(fitnessLevel: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Quieres hijos *',
            options: _wantsChildrenOptions,
            selected: draft.wantsChildren,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(wantsChildren: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Estilo social',
            options: _socialStyleOptions,
            selected: draft.socialStyle,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(socialStyle: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Estilo de viaje *',
            options: _travelStyleOptions,
            selected: draft.travelStyle,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(travelStyle: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      title: 'Estilo y vibe',
      subtitle: 'Define tu energia para personalizar la experiencia.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildMultiChoiceWrap(
            title: 'Fashion style *',
            options: _fashionStyleOptions,
            selected: draft.fashionStyle,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(fashionStyle: values)),
          ),
          const SizedBox(height: 16),
          _buildMultiChoiceWrap(
            title: 'Personality tags *',
            options: _personalityOptions,
            selected: draft.personalityTags,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(personalityTags: values)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesStep(ThemeData theme, OnboardingDraft draft) {
    final RangeValues ageRange = RangeValues(
      draft.preferredAgeMin.toDouble(),
      draft.preferredAgeMax.toDouble(),
    );

    return _StepLayout(
      title: 'Preferencias iniciales',
      subtitle: 'Personaliza a quien te mostraremos mas frecuentemente.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildMultiChoiceWrap(
            title: 'Interes inicial *',
            options: _interestedInOptions,
            selected: draft.interestedIn,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(interestedIn: values)),
          ),
          const SizedBox(height: 16),
          Text('Rango de edad preferido *', style: theme.textTheme.titleSmall),
          RangeSlider(
            min: _minimumAge.toDouble(),
            max: 80,
            divisions: 62,
            labels: RangeLabels(
              '${draft.preferredAgeMin}',
              '${draft.preferredAgeMax}',
            ),
            values: ageRange,
            onChanged: (RangeValues values) {
              _updateDraft(
                draft.copyWith(
                  preferredAgeMin: values.start.round(),
                  preferredAgeMax: values.end.round(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text('Distancia maxima: ${draft.maxDistanceKm} km *'),
          Slider(
            min: 1,
            max: 500,
            divisions: 99,
            label: '${draft.maxDistanceKm} km',
            value: draft.maxDistanceKm.toDouble(),
            onChanged: (double value) {
              _updateDraft(draft.copyWith(maxDistanceKm: value.round()));
            },
          ),
          const SizedBox(height: 12),
          _buildLocationBlock(theme, draft),
          const SizedBox(height: 12),
          _buildMultiChoiceWrap(
            title: 'Idiomas preferidos',
            options: _languageOptions,
            selected: draft.preferredLanguages,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(preferredLanguages: values)),
          ),
          const SizedBox(height: 12),
          _buildMultiChoiceWrap(
            title: 'Lifestyle que te atrae',
            options: _lifestylePreferenceOptions,
            selected: draft.lifestylePreferences,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(lifestylePreferences: values)),
          ),
          const SizedBox(height: 12),
          _buildMultiChoiceWrap(
            title: 'Apariencia que te atrae',
            options: _appearancePreferenceOptions,
            selected: draft.appearancePreferences,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(appearancePreferences: values)),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBlock(ThemeData theme, OnboardingDraft draft) {
    final String statusLabel = _locationStatusLabel(draft);
    final Color statusColor = _locationStatusColor(theme, draft);
    final bool hasCoordinates =
        draft.locationLatitude != null && draft.locationLongitude != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Ubicacion para perfiles cercanos',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Usamos tu ubicacion aproximada para mostrarte personas cerca de ti y respetar tu radio de busqueda. No mostramos tu ubicacion exacta a otros usuarios.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            statusLabel,
            style: theme.textTheme.bodyMedium?.copyWith(color: statusColor),
          ),
          if (hasCoordinates) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Ubicacion lista para calculo de proximidad.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _submitting ? null : _requestLocationPermissionAndFix,
                  icon: const Icon(Icons.my_location_outlined),
                  label: const Text('Permitir ubicacion'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : _continueWithoutLocation,
                  child: const Text('Ahora no'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectBirthDate(DateTime? current) async {
    final DateTime now = DateTime.now();
    final DateTime minimumDate = DateTime(now.year - 100, 1, 1);
    final DateTime maximumDate =
        DateTime(now.year - _minimumAge, now.month, now.day);
    final DateTime fallbackDate = DateTime(now.year - 24, now.month, now.day);

    DateTime selectedDate = current ?? fallbackDate;
    if (selectedDate.isBefore(minimumDate)) {
      selectedDate = minimumDate;
    }
    if (selectedDate.isAfter(maximumDate)) {
      selectedDate = maximumDate;
    }

    final DateTime? picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        DateTime tempSelected = selectedDate;
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 340,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).pop(tempSelected),
                        child: const Text('Aceptar'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      brightness: Brightness.light,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: selectedDate,
                      minimumDate: minimumDate,
                      maximumDate: maximumDate,
                      dateOrder: DatePickerDateOrder.dmy,
                      use24hFormat: true,
                      onDateTimeChanged: (DateTime value) {
                        tempSelected = value;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || picked == null || _draft == null) {
      return;
    }

    _updateDraft(_draft!.copyWith(birthDate: picked));
  }

  void _updateDraft(OnboardingDraft updated) {
    if (!mounted) {
      return;
    }
    setState(() {
      _draft = updated;
      _localError = null;
    });
    _markDraftDirtyAndDebounceSave();
  }

  Widget _buildSingleChoiceWrap({
    required String title,
    required List<_OptionItem> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((_OptionItem option) {
            final bool isSelected = selected == option.value;
            return ChoiceChip(
              label: Text(option.label),
              selected: isSelected,
              onSelected: (_) => onSelected(option.value),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildMultiChoiceWrap({
    required String title,
    required List<_OptionItem> options,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((_OptionItem option) {
            final bool isSelected = selected.contains(option.value);
            return FilterChip(
              label: Text(option.label),
              selected: isSelected,
              onSelected: (bool value) {
                final List<String> next = List<String>.from(selected);
                if (value) {
                  if (!next.contains(option.value)) {
                    next.add(option.value);
                  }
                } else {
                  next.remove(option.value);
                }
                onChanged(next);
              },
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final String d = date.day.toString().padLeft(2, '0');
    final String m = _monthNameEs(date.month);
    final String y = date.year.toString();
    return '$d $m $y';
  }

  String _monthNameEs(int month) {
    const List<String> months = <String>[
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    if (month < 1 || month > 12) {
      return '';
    }
    return months[month - 1];
  }
}

class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _OptionItem {
  const _OptionItem({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

const List<_OptionItem> _genderOptions = <_OptionItem>[
  _OptionItem(value: 'female', label: 'Mujer'),
  _OptionItem(value: 'male', label: 'Hombre'),
  _OptionItem(value: 'non_binary', label: 'No binario'),
];

const List<_OptionItem> _languageOptions = <_OptionItem>[
  _OptionItem(value: 'es', label: 'Español'),
  _OptionItem(value: 'en', label: 'Ingles'),
  _OptionItem(value: 'fr', label: 'Frances'),
  _OptionItem(value: 'it', label: 'Italiano'),
  _OptionItem(value: 'de', label: 'Aleman'),
  _OptionItem(value: 'pt', label: 'Portugues'),
];

const List<_OptionItem> _eyeColorOptions = <_OptionItem>[
  _OptionItem(value: 'brown', label: 'Marron'),
  _OptionItem(value: 'blue', label: 'Azul'),
  _OptionItem(value: 'green', label: 'Verde'),
  _OptionItem(value: 'gray', label: 'Gris'),
  _OptionItem(value: 'hazel', label: 'Avellana'),
];

const List<_OptionItem> _hairColorOptions = <_OptionItem>[
  _OptionItem(value: 'black', label: 'Negro'),
  _OptionItem(value: 'brown', label: 'Castaño'),
  _OptionItem(value: 'blonde', label: 'Rubio'),
  _OptionItem(value: 'red', label: 'Pelirrojo'),
  _OptionItem(value: 'gray', label: 'Canoso'),
];

const List<_OptionItem> _hairTypeOptions = <_OptionItem>[
  _OptionItem(value: 'straight', label: 'Liso'),
  _OptionItem(value: 'wavy', label: 'Ondulado'),
  _OptionItem(value: 'curly', label: 'Rizado'),
  _OptionItem(value: 'coily', label: 'Afro'),
  _OptionItem(value: 'shaved', label: 'Rapado'),
];

const List<_OptionItem> _bodyTypeOptions = <_OptionItem>[
  _OptionItem(value: 'slim', label: 'Delgado'),
  _OptionItem(value: 'athletic', label: 'Atletico'),
  _OptionItem(value: 'average', label: 'Medio'),
  _OptionItem(value: 'curvy', label: 'Curvy'),
  _OptionItem(value: 'plus_size', label: 'Grande'),
];

const List<_OptionItem> _relationshipIntentOptions = <_OptionItem>[
  _OptionItem(value: 'serious_relationship', label: 'Relacion seria'),
  _OptionItem(value: 'meet_people', label: 'Conocer gente'),
  _OptionItem(value: 'casual', label: 'Algo casual'),
  _OptionItem(value: 'open_to_see', label: 'Abierto a ver que surge'),
];

const List<_OptionItem> _smokingOptions = <_OptionItem>[
  _OptionItem(value: 'never', label: 'Nunca'),
  _OptionItem(value: 'occasionally', label: 'Ocasional'),
  _OptionItem(value: 'frequently', label: 'Frecuente'),
];

const List<_OptionItem> _drinkingOptions = <_OptionItem>[
  _OptionItem(value: 'never', label: 'Nunca'),
  _OptionItem(value: 'socially', label: 'Social'),
  _OptionItem(value: 'frequently', label: 'Frecuente'),
];
const List<_OptionItem> _fitnessOptions = <_OptionItem>[
  _OptionItem(value: 'low', label: 'Bajo'),
  _OptionItem(value: 'medium', label: 'Medio'),
  _OptionItem(value: 'high', label: 'Alto'),
];

const List<_OptionItem> _wantsChildrenOptions = <_OptionItem>[
  _OptionItem(value: 'yes', label: 'Si'),
  _OptionItem(value: 'no', label: 'No'),
  _OptionItem(value: 'maybe', label: 'Quizas'),
];

const List<_OptionItem> _socialStyleOptions = <_OptionItem>[
  _OptionItem(value: 'calm', label: 'Tranquilo'),
  _OptionItem(value: 'balanced', label: 'Equilibrado'),
  _OptionItem(value: 'very_social', label: 'Muy social'),
];

const List<_OptionItem> _travelStyleOptions = <_OptionItem>[
  _OptionItem(value: 'homebody', label: 'Hogareño'),
  _OptionItem(value: 'weekend_getaways', label: 'Escapadas'),
  _OptionItem(value: 'adventurous', label: 'Aventurero'),
];

const List<_OptionItem> _fashionStyleOptions = <_OptionItem>[
  _OptionItem(value: 'casual', label: 'Casual'),
  _OptionItem(value: 'elegant', label: 'Elegante'),
  _OptionItem(value: 'urban', label: 'Urbano'),
  _OptionItem(value: 'sporty', label: 'Deportivo'),
  _OptionItem(value: 'minimalist', label: 'Minimalista'),
];

const List<_OptionItem> _personalityOptions = <_OptionItem>[
  _OptionItem(value: 'ambitious', label: 'Ambicioso'),
  _OptionItem(value: 'empathetic', label: 'Empatico'),
  _OptionItem(value: 'fun', label: 'Divertido'),
  _OptionItem(value: 'creative', label: 'Creativo'),
  _OptionItem(value: 'calm', label: 'Tranquilo'),
  _OptionItem(value: 'intense', label: 'Intenso'),
];

const List<_OptionItem> _interestedInOptions = <_OptionItem>[
  _OptionItem(value: 'female', label: 'Mujer'),
  _OptionItem(value: 'male', label: 'Hombre'),
  _OptionItem(value: 'non_binary', label: 'No binario'),
];

const List<_OptionItem> _lifestylePreferenceOptions = <_OptionItem>[
  _OptionItem(value: 'active', label: 'Activo'),
  _OptionItem(value: 'homebody', label: 'Hogareño'),
  _OptionItem(value: 'traveler', label: 'Viajero'),
  _OptionItem(value: 'social', label: 'Social'),
  _OptionItem(value: 'healthy', label: 'Saludable'),
];

const List<_OptionItem> _appearancePreferenceOptions = <_OptionItem>[
  _OptionItem(value: 'intense_eyes', label: 'Mirada intensa'),
  _OptionItem(value: 'natural_look', label: 'Look natural'),
  _OptionItem(value: 'elegant_look', label: 'Look elegante'),
  _OptionItem(value: 'urban_style', label: 'Estilo urbano'),
  _OptionItem(value: 'sporty_vibe', label: 'Vibe deportiva'),
];

const Map<String, String> _latinMap = <String, String>{
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};

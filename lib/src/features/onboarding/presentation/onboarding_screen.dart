import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../auth/domain/app_user.dart';
import '../../geo/data/geo_repository.dart';
import '../../geo/presentation/country_city_field.dart';
import '../../profile/domain/profile_prompt.dart';
import '../../profile/presentation/company_field.dart';
import '../../profile/presentation/profile_prompts_editor_screen.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_backgrounds.dart';
import '../../../widgets/attra_buttons.dart';
import '../../../widgets/attra_loader.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_draft.dart';
import '../domain/voice_profile_suggestion.dart';
import 'voice_profile_setup.dart';

/// Metadatos visuales por paso (icono + etiqueta corta para el progreso).
const List<({IconData icon, String label})> _stepMeta =
    <({IconData icon, String label})>[
  (icon: Icons.camera_alt_rounded, label: 'Selfie'),
  (icon: Icons.badge_rounded, label: 'Identidad'),
  (icon: Icons.face_retouching_natural_rounded, label: 'Apariencia'),
  (icon: Icons.auto_awesome_rounded, label: 'Perfil'),
  (icon: Icons.spa_rounded, label: 'Estilo de vida'),
  (icon: Icons.palette_rounded, label: 'Vibe'),
  (icon: Icons.favorite_rounded, label: 'Preferencias'),
  (icon: Icons.chat_bubble_rounded, label: 'Preguntas'),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onLoadDraft,
    required this.onSaveDraft,
    required this.onUploadLiveSelfieDraft,
    required this.onGenerateVoiceProfile,
    required this.onSubmitOnboarding,
    required this.onLogout,
    this.user,
    this.errorMessage,
    this.onCheckVoiceProfileAvailability,
  });

  final AppUser? user;
  final String? errorMessage;
  final Future<OnboardingDraft> Function() onLoadDraft;
  final Future<void> Function(OnboardingDraft draft) onSaveDraft;
  final Future<LiveSelfieDraftUpload> Function({
    required Uint8List liveSelfieBytes,
    required String liveSelfieFileExtension,
  }) onUploadLiveSelfieDraft;
  final VoiceProfileGenerator onGenerateVoiceProfile;
  final Future<bool> Function()? onCheckVoiceProfileAvailability;
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
  static const int _totalSteps = 8;
  static const int _minimumAge = 18;

  final PageController _pageController = PageController();
  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController _visibleNameController;
  late final TextEditingController _heightController;
  late final TextEditingController _bioController;
  late final TextEditingController _jobTitleController;

  Timer? _draftDebounce;
  String? _lastPersistedFingerprint;
  bool _hasPendingDraftChanges = false;

  OnboardingDraft? _draft;
  bool _loadingDraft = true;
  bool _submitting = false;
  String? _localError;
  DateTime? _ageGateSelectedDate;
  bool _savingAgeGate = false;
  bool _birthCityValid = false;
  bool _currentCityValid = false;
  bool _voiceProfileAvailable = true;

  Uint8List? _liveSelfieBytes;
  String _liveSelfieFileExtension = 'jpg';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _visibleNameController = TextEditingController();
    _heightController = TextEditingController();
    _bioController = TextEditingController();
    _jobTitleController = TextEditingController();

    _visibleNameController.addListener(_onTextInputChanged);
    _heightController.addListener(_onTextInputChanged);
    _bioController.addListener(_onTextInputChanged);
    _jobTitleController.addListener(_onTextInputChanged);

    _loadDraft();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftDebounce?.cancel();

    _visibleNameController.removeListener(_onTextInputChanged);
    _heightController.removeListener(_onTextInputChanged);
    _bioController.removeListener(_onTextInputChanged);
    _jobTitleController.removeListener(_onTextInputChanged);

    unawaited(_persistCurrentDraft(force: true));

    _pageController.dispose();
    _visibleNameController.dispose();
    _heightController.dispose();
    _bioController.dispose();
    _jobTitleController.dispose();
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
    final Future<bool> availabilityFuture =
        widget.onCheckVoiceProfileAvailability?.call() ??
            Future<bool>.value(true);
    try {
      final OnboardingDraft loadedDraft = await widget.onLoadDraft();
      bool voiceProfileAvailable = false;
      try {
        voiceProfileAvailable = await availabilityFuture;
      } catch (_) {
        // Fail closed: the manual onboarding always remains available.
      }
      if (!mounted) {
        return;
      }

      _visibleNameController.text = loadedDraft.visibleName;
      _heightController.text = loadedDraft.heightCm?.toString() ?? '';
      _bioController.text = loadedDraft.bio;
      _jobTitleController.text = loadedDraft.jobTitle;
      _birthCityValid = loadedDraft.birthCountryCode.isNotEmpty &&
          loadedDraft.birthCity.trim().isNotEmpty;
      _currentCityValid = loadedDraft.currentCountryCode.isNotEmpty &&
          loadedDraft.currentCity.trim().isNotEmpty;

      setState(() {
        _draft = loadedDraft;
        _loadingDraft = false;
        _localError = null;
        _voiceProfileAvailable = voiceProfileAvailable;
      });

      _lastPersistedFingerprint = _draftFingerprint(loadedDraft);
      _hasPendingDraftChanges = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) {
          return;
        }
        final List<int> steps = _visibleSteps(loadedDraft);
        final int position = steps.indexOf(loadedDraft.currentStep);
        _pageController.jumpToPage(position < 0 ? 0 : position);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final OnboardingDraft fallbackDraft =
          OnboardingDraft.fromUser(widget.user);
      bool voiceProfileAvailable = false;
      try {
        voiceProfileAvailable = await availabilityFuture;
      } catch (_) {
        // The fallback draft still has the full manual path.
      }
      _visibleNameController.text = fallbackDraft.visibleName;
      _heightController.text = fallbackDraft.heightCm?.toString() ?? '';
      _bioController.text = fallbackDraft.bio;
      _jobTitleController.text = fallbackDraft.jobTitle;
      setState(() {
        _loadingDraft = false;
        _localError =
            'No se pudo cargar el onboarding guardado. Intenta de nuevo. ($error)';
        _draft = fallbackDraft;
        _voiceProfileAvailable = voiceProfileAvailable;
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
        // La selfie de verificación es SIEMPRE frontal.
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 90,
        maxWidth: 1080,
      );
      if (photo == null) {
        return;
      }

      final Uint8List raw = await photo.readAsBytes();
      // Des-espeja la selfie frontal (iOS suele guardarla reflejada) para que
      // salga natural, como te ven los demás. Si falla, usa la original.
      final Uint8List? unmirrored = _unmirrorSelfie(raw);
      final Uint8List bytes = unmirrored ?? raw;
      final String extension = unmirrored != null
          ? 'jpg'
          : _extractFileExtension(photo.name, photo.path);

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

  /// Voltea horizontalmente la selfie (quita el efecto espejo de la cámara
  /// frontal) y la re-codifica a JPEG. Devuelve null si no se pudo procesar
  /// (entonces se usa la imagen original tal cual).
  Uint8List? _unmirrorSelfie(Uint8List bytes) {
    try {
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final img.Image flipped = img.flipHorizontal(decoded);
      return Uint8List.fromList(img.encodeJpg(flipped, quality: 90));
    } catch (_) {
      return null;
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

    final List<int> visibleSteps = _visibleSteps(normalized);
    final int position = visibleSteps.indexOf(normalized.currentStep);
    if (position < 0) {
      setState(() {
        _localError =
            'No hemos podido recuperar este paso. Vuelve a elegir el método de configuración.';
      });
      return;
    }
    if (position == visibleSteps.length - 1) {
      await _submit(normalized);
      return;
    }

    final int nextPosition = position + 1;
    final int nextStep = visibleSteps[nextPosition];
    setState(() {
      _draft = normalized.copyWith(currentStep: nextStep);
    });

    await _persistCurrentDraft(force: true);
    if (!mounted) {
      return;
    }
    await _pageController.animateToPage(
      nextPosition,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _goBack() async {
    final OnboardingDraft? current = _draft;
    if (current == null || _submitting) {
      return;
    }

    final OnboardingDraft normalized = _syncControllersIntoDraft(current);
    final List<int> visibleSteps = _visibleSteps(normalized);
    final int position = visibleSteps.indexOf(normalized.currentStep);
    if (position <= 0) return;
    final int previousPosition = position - 1;
    final int previousStep = visibleSteps[previousPosition];
    setState(() {
      _draft = normalized.copyWith(currentStep: previousStep);
    });

    await _persistCurrentDraft(force: true);
    if (!mounted) {
      return;
    }

    await _pageController.animateToPage(
      previousPosition,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _returnToSetupMode() {
    final OnboardingDraft? current = _draft;
    if (current == null || _submitting) return;
    _updateDraft(
      _syncControllersIntoDraft(current).copyWith(
        currentStep: 0,
        setupMode: '',
        voiceProfileGenerated: false,
        quickRemainingSteps: const <int>[],
      ),
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
      await runWithAttraLoader(
        context,
        () async {
          await _persistCurrentDraft(force: true);

          await widget.onSubmitOnboarding(
            draft: normalizedDraft.copyWith(currentStep: _totalSteps - 1),
            liveSelfieBytes: _liveSelfieBytes,
            liveSelfieFileExtension: _liveSelfieFileExtension,
          );
        },
        message: 'Creando tu perfil…',
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
    return draft.copyWith(
      visibleName: _visibleNameController.text.trim(),
      bio: _bioController.text.trim(),
      jobTitle: _jobTitleController.text.trim(),
      heightCm: parsedHeight,
      clearHeight: _heightController.text.trim().isEmpty,
    );
  }

  /// Intent-first: las preguntas románticas solo aplican en dating/ambas.
  bool _isRomantic(OnboardingDraft draft) =>
      draft.intentMode == 'dating' || draft.intentMode == 'both';

  String? _validateStep(OnboardingDraft draft, int step) {
    switch (step) {
      case 0:
        if (!_hasLiveSelfie(draft)) {
          return 'Debes tomar una selfie real con la camara para continuar.';
        }
        return null;
      case 1:
        if (draft.visibleName.trim().length < 2) {
          return 'Escribe un nombre visible de al menos 2 caracteres.';
        }
        if (draft.birthDate == null) {
          return 'Selecciona tu fecha de nacimiento.';
        }
        if (_calculateAge(draft.birthDate!) < _minimumAge) {
          return 'Debes tener al menos $_minimumAge anos para usar la app.';
        }
        if (draft.gender.isEmpty) {
          return 'Selecciona tu genero.';
        }
        if (draft.birthCountryCode.isEmpty ||
            draft.birthCity.trim().isEmpty ||
            !_birthCityValid) {
          return 'Selecciona un pais y una ciudad de nacimiento reales (de la lista).';
        }
        if (draft.currentCountryCode.isEmpty ||
            draft.currentCity.trim().isEmpty ||
            !_currentCityValid) {
          return 'Selecciona un pais y una ciudad actual reales (de la lista).';
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
        if (_isRomantic(draft) && draft.relationshipIntent.isEmpty) {
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
        if (_isRomantic(draft) && draft.interestedIn.isEmpty) {
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
        return AppColors.success;
      case 'error':
      case 'denied_forever':
      case 'service_disabled':
        return AppColors.coral;
      default:
        return context.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_loadingDraft || _draft == null) {
      return const Scaffold(
        body: AttraGradientBackground(
          child: Center(
              child: CircularProgressIndicator(color: AppColors.attraRed)),
        ),
      );
    }

    final OnboardingDraft draft = _draft!;

    // La edad se confirma antes de cualquier flujo opcional de IA. La fecha se
    // persiste antes de avanzar para que la Function también pueda exigir +18.
    if (draft.birthDate == null ||
        _calculateAge(draft.birthDate!) < _minimumAge) {
      return _buildAgeGate(theme);
    }

    // Intent-first: antes de todo el onboarding, preguntamos qué busca la
    // persona. Attra no arranca por "¿quién te gusta?", sino por la intención.
    if (draft.intentMode.isEmpty) {
      return _buildIntentGate(theme, draft);
    }

    if (draft.setupMode.isEmpty) {
      return _buildSetupModeGate(theme, draft);
    }

    if (draft.setupMode == 'quick' && !draft.voiceProfileGenerated) {
      if (!_voiceProfileAvailable) {
        return _buildSetupModeGate(theme, draft);
      }
      return VoiceProfileSetup(
        intentMode: draft.intentMode,
        onGenerate: _generateVoiceSuggestionForReview,
        onAccepted: _applyVoiceSuggestion,
        onUseManual: () => _chooseSetupMode('manual'),
        onBack: () => _chooseSetupMode(''),
      );
    }

    final List<int> visibleSteps = _visibleSteps(draft);
    final int step = visibleSteps.contains(draft.currentStep)
        ? draft.currentStep
        : visibleSteps.first;
    final int position = visibleSteps.indexOf(step);
    final bool isLast = position == visibleSteps.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AttraGradientBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _buildHeader(
                theme,
                step,
                position: position,
                total: visibleSteps.length,
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: visibleSteps
                      .map((int index) => _buildStep(theme, draft, index))
                      .toList(growable: false),
                ),
              ),
              _buildFooter(
                theme,
                isLast,
                position: position,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<int> _visibleSteps(OnboardingDraft draft) {
    if (draft.setupMode == 'quick' && draft.voiceProfileGenerated) {
      final List<int> steps = draft.quickRemainingSteps
          .where((int step) => step >= 0 && step <= 6)
          .toSet()
          .toList(growable: false)
        ..sort();
      // Backward-compatible fallback for a quick draft created before the
      // condensed-step field existed.
      return steps.isEmpty ? const <int>[0, 1, 2, 6] : steps;
    }
    return List<int>.generate(_totalSteps, (int index) => index);
  }

  Widget _buildStep(
    ThemeData theme,
    OnboardingDraft draft,
    int index,
  ) {
    return switch (index) {
      0 => _buildSelfieStep(theme, draft),
      1 => _buildIdentityStep(theme, draft),
      2 => _buildAppearanceStep(theme, draft),
      3 => _buildPersonalStep(theme, draft),
      4 => _buildLifestyleStep(theme, draft),
      5 => _buildStyleStep(theme, draft),
      6 => _buildPreferencesStep(theme, draft),
      _ => _buildPromptsStep(theme, draft),
    };
  }

  Widget _buildAgeGate(ThemeData theme) {
    final DateTime? selected = _ageGateSelectedDate;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AttraGradientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _savingAgeGate ? null : widget.onLogout,
                        child: const Text('Cerrar sesión'),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.colors.accentSoft,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLg),
                        border: Border.all(color: context.colors.surfaceLine),
                      ),
                      child: Icon(
                        Icons.cake_outlined,
                        color: context.colors.accent,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Primero, confirmemos tu edad',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Attra es solo para mayores de 18 años. Necesitamos tu '
                      'fecha antes de ofrecer cualquier configuración con IA.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 26),
                    AttraCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Fecha de nacimiento',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No se muestra completa en tu perfil.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _savingAgeGate
                                ? null
                                : () async {
                                    final DateTime? picked =
                                        await _pickBirthDate(selected);
                                    if (!mounted || picked == null) return;
                                    setState(() {
                                      _ageGateSelectedDate = picked;
                                      _localError = null;
                                    });
                                  },
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text(
                              selected == null
                                  ? 'Seleccionar fecha'
                                  : _formatDate(selected),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_localError != null) ...<Widget>[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.attraRed.withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(
                            color: AppColors.attraRed.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          _localError!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    AttraPrimaryButton(
                      label: 'Confirmar y continuar',
                      icon: Icons.arrow_forward_rounded,
                      loading: _savingAgeGate,
                      onPressed: selected == null ? null : _confirmAgeGate,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'La fecha se usa para comprobar la mayoría de edad '
                            'y calcular la edad pública; nunca se envía al '
                            'modelo de IA.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAgeGate() async {
    final DateTime? birthDate = _ageGateSelectedDate;
    final OnboardingDraft? current = _draft;
    if (_savingAgeGate || birthDate == null || current == null) return;
    if (_calculateAge(birthDate) < _minimumAge) {
      setState(() => _localError =
          'Debes tener al menos $_minimumAge años para usar Attra.');
      return;
    }

    final OnboardingDraft updated = current.copyWith(birthDate: birthDate);
    setState(() {
      _savingAgeGate = true;
      _localError = null;
    });
    try {
      // Persist before advancing: the voice callable independently verifies
      // this value and fails closed if it is absent.
      await widget.onSaveDraft(updated);
      if (!mounted) return;
      setState(() {
        _draft = updated;
        _ageGateSelectedDate = null;
        _savingAgeGate = false;
      });
      _lastPersistedFingerprint = _draftFingerprint(updated);
      _hasPendingDraftChanges = false;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingAgeGate = false;
        _localError =
            'No hemos podido verificar la edad. Comprueba tu conexión e inténtalo de nuevo.';
      });
    }
  }

  Widget _buildSetupModeGate(ThemeData theme, OnboardingDraft draft) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AttraGradientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        IconButton(
                          onPressed: () => _updateDraft(
                            draft.copyWith(intentMode: ''),
                          ),
                          tooltip: 'Atrás',
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: widget.onLogout,
                          child: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Haz que tu perfil empiece sonando a ti',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _voiceProfileAvailable
                          ? 'Elige cómo quieres empezar. Los dos caminos terminan '
                              'en la misma revisión y puedes cambiar de idea '
                              'cuando quieras.'
                          : 'Puedes completar el perfil paso a paso. La opción '
                              'por voz aparecerá cuando su procesamiento privado '
                              'esté disponible.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_voiceProfileAvailable) ...<Widget>[
                      _SetupModeCard(
                        recommended: true,
                        icon: Icons.graphic_eq_rounded,
                        title: 'Configuración rápida',
                        duration: 'Un audio · unos 2 min',
                        description:
                            'Nos cuentas cómo eres y la IA propone una bio, '
                            'rasgos y preguntas. Lo revisas todo antes de '
                            'continuar.',
                        features: const <String>[
                          'Audio privado y de un solo uso',
                          'Borrador editable antes del alta',
                          'Sin inferir datos sensibles',
                        ],
                        onTap: () => _chooseSetupMode('quick'),
                      ),
                      const SizedBox(height: 14),
                    ] else ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceHigh,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusLg),
                          border: Border.all(color: context.colors.surfaceLine),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              Icons.mic_off_outlined,
                              color: context.colors.textMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'La configuración por voz está temporalmente '
                                'en pausa. No necesitas esperar para crear tu '
                                'perfil.',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _SetupModeCard(
                      icon: Icons.tune_rounded,
                      title: 'Paso a paso',
                      duration: 'Tú completas cada apartado',
                      description:
                          'La configuración actual, pregunta por pregunta, con '
                          'control directo sobre cada dato.',
                      features: const <String>[
                        'Sin procesamiento de voz',
                        'Puedes guardar y seguir luego',
                      ],
                      onTap: () => _chooseSetupMode('manual'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'En ambos casos te pediremos aparte la selfie y los '
                            'datos que una IA nunca debería adivinar.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _chooseSetupMode(String mode) {
    final OnboardingDraft? current = _draft;
    if (current == null) return;
    _updateDraft(
      current.copyWith(
        currentStep: mode == 'manual' ? 0 : current.currentStep,
        setupMode: mode,
        voiceProfileGenerated:
            mode == 'quick' ? current.voiceProfileGenerated : false,
        quickRemainingSteps:
            mode == 'quick' ? current.quickRemainingSteps : const <int>[],
      ),
    );
  }

  Future<VoiceProfileSuggestion> _generateVoiceSuggestionForReview({
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
    required String intentMode,
  }) async {
    final VoiceProfileSuggestion generated =
        await widget.onGenerateVoiceProfile(
      bytes: bytes,
      contentType: contentType,
      extension: extension,
      durationMs: durationMs,
      intentMode: intentMode,
    );
    final OnboardingDraft? base = _draft;
    if (base == null) return generated;
    return generated.withDraftFallback(base);
  }

  Future<void> _applyVoiceSuggestion(
    VoiceProfileSuggestion suggestion,
  ) async {
    final OnboardingDraft? current = _draft;
    if (current == null) return;
    OnboardingDraft updated = suggestion.applyTo(
      _syncControllersIntoDraft(current),
    );
    final List<int> remainingSteps = <int>[
      for (int step = 0; step <= 6; step++)
        if (_validateStep(updated, step) != null) step,
    ];
    // Preferences is the final confirmation in quick mode, even when defaults
    // are already valid. Prompts and completed AI sections are not repeated.
    if (!remainingSteps.contains(6)) remainingSteps.add(6);
    remainingSteps.sort();
    updated = updated.copyWith(
      currentStep: remainingSteps.first,
      quickRemainingSteps: remainingSteps,
    );
    _bioController.text = updated.bio;
    _jobTitleController.text = updated.jobTitle;
    setState(() {
      _draft = updated;
      _localError = null;
    });
    _markDraftDirtyAndDebounceSave();
    await _persistCurrentDraft(force: true);
  }

  /// Pantalla intent-first: qué busca la persona en Attra. Se muestra ANTES del
  /// onboarding. Las preguntas románticas solo aparecen si elige citas/ambas.
  Widget _buildIntentGate(ThemeData theme, OnboardingDraft draft) {
    void choose(String mode) => _updateDraft(draft.copyWith(intentMode: mode));
    const List<({String mode, IconData icon, String title, String subtitle})>
        options =
        <({String mode, IconData icon, String title, String subtitle})>[
      (
        mode: 'friends',
        icon: Icons.emoji_people_rounded,
        title: 'Amistades',
        subtitle: 'Conocer gente y hacer planes, sin rollo romántico.'
      ),
      (
        mode: 'dating',
        icon: Icons.favorite_rounded,
        title: 'Citas',
        subtitle: 'Conectar con alguien especial.'
      ),
      (
        mode: 'both',
        icon: Icons.auto_awesome_rounded,
        title: 'Ambas',
        subtitle: 'Abierto a lo que surja: amistad o citas.'
      ),
      (
        mode: 'groups',
        icon: Icons.groups_rounded,
        title: 'Grupos y planes',
        subtitle: 'Unirte a grupos y actividades por intereses.'
      ),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AttraGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '¿Qué quieres encontrar en Attra?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Puedes cambiarlo cuando quieras. Nos ayuda a mostrarte lo '
                  'que de verdad te interesa.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.textSecondary),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (BuildContext context, int i) {
                      final ({
                        String mode,
                        IconData icon,
                        String title,
                        String subtitle
                      }) o = options[i];
                      return _IntentCard(
                        icon: o.icon,
                        title: o.title,
                        subtitle: o.subtitle,
                        onTap: () => choose(o.mode),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    int step, {
    required int position,
    required int total,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Paso ${position + 1} de $total',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.attraRed,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _stepMeta[step].label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _submitting ? null : widget.onLogout,
                tooltip: 'Cerrar sesión',
                icon: Icon(Icons.logout_rounded,
                    color: context.colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StepProgress(current: position, total: total),
        ],
      ),
    );
  }

  Widget _buildFooter(
    ThemeData theme,
    bool isLast, {
    required int position,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.surfaceLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.errorMessage != null || _localError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.attraRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                      color: AppColors.attraRed.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.coral, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _localError ?? widget.errorMessage!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: <Widget>[
              _CircleNavButton(
                icon: Icons.arrow_back_rounded,
                onPressed: _submitting
                    ? null
                    : position > 0
                        ? _goBack
                        : _returnToSetupMode,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AttraPrimaryButton(
                  label: isLast ? 'Finalizar' : 'Continuar',
                  icon: isLast ? Icons.check_rounded : null,
                  loading: _submitting,
                  onPressed: _submitting ? null : _goNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelfieStep(ThemeData theme, OnboardingDraft draft) {
    final bool hasSelfie = _hasLiveSelfie(draft);
    final ImageProvider? selfieImage = _liveSelfieBytes != null
        ? MemoryImage(_liveSelfieBytes!)
        : (draft.liveSelfiePublicPhotoUrl.isNotEmpty
            ? NetworkImage(draft.liveSelfiePublicPhotoUrl)
            : null) as ImageProvider?;

    return _StepLayout(
      icon: _stepMeta[0].icon,
      title: 'Tu selfie en vivo',
      subtitle:
          'Tu primera foto debe ser una selfie tomada ahora mismo. Así verificamos que eres tú.',
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          Center(
            child: _SelfieRing(
              hasSelfie: hasSelfie,
              image: selfieImage,
              onTap: _submitting ? null : _captureLiveSelfie,
            ),
          ),
          const SizedBox(height: 20),
          AttraPrimaryButton(
            label: hasSelfie ? 'Repetir selfie' : 'Tomar selfie ahora',
            icon: Icons.camera_alt_rounded,
            expand: false,
            onPressed: _submitting ? null : _captureLiveSelfie,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.verified_user_rounded,
                  size: 16,
                  color:
                      hasSelfie ? AppColors.success : context.colors.textMuted),
              const SizedBox(width: 6),
              Text(
                hasSelfie ? 'Selfie capturada' : 'Pendiente de capturar',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      hasSelfie ? AppColors.success : context.colors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      icon: _stepMeta[1].icon,
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
          _buildSingleChoiceWrap(
            title: 'Pronombres',
            options: _pronounOptions,
            selected: draft.pronouns,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(pronouns: value)),
          ),
          const SizedBox(height: 12),
          _buildMultiChoiceWrap(
            title: 'Orientación sexual',
            options: _orientationOptions,
            selected: draft.orientation,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(orientation: values)),
          ),
          const SizedBox(height: 16),
          CountryCityField(
            label: 'Lugar de nacimiento *',
            initialCountryIso2: draft.birthCountryCode,
            initialCountryName: draft.birthCountryName,
            initialCity: draft.birthCity,
            onChanged: ({
              required String? iso2,
              required String? countryName,
              required String? city,
              required bool cityIsValid,
            }) {
              _birthCityValid = cityIsValid;
              _updateDraft(draft.copyWith(
                birthCountryCode: iso2 ?? '',
                birthCountryName: countryName ?? '',
                birthCity: city ?? '',
                birthCityNormalized: GeoRepository.normalize(city ?? ''),
              ));
            },
          ),
          const SizedBox(height: 16),
          CountryCityField(
            label: 'Ubicacion actual *',
            initialCountryIso2: draft.currentCountryCode,
            initialCountryName: draft.currentCountryName,
            initialCity: draft.currentCity,
            onChanged: ({
              required String? iso2,
              required String? countryName,
              required String? city,
              required bool cityIsValid,
            }) {
              _currentCityValid = cityIsValid;
              _updateDraft(draft.copyWith(
                currentCountryCode: iso2 ?? '',
                currentCountryName: countryName ?? '',
                currentCity: city ?? '',
                currentCityNormalized: GeoRepository.normalize(city ?? ''),
              ));
            },
          ),
          const SizedBox(height: 16),
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
      icon: _stepMeta[2].icon,
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
      icon: _stepMeta[3].icon,
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
          // Preguntas románticas: solo en modo citas/ambas (intent-first).
          if (_isRomantic(draft)) ...<Widget>[
            const SizedBox(height: 12),
            _buildSingleChoiceWrap(
              title: 'Que buscas *',
              options: _relationshipIntentOptions,
              selected: draft.relationshipIntent,
              onSelected: (String value) =>
                  _updateDraft(draft.copyWith(relationshipIntent: value)),
            ),
            const SizedBox(height: 12),
            _buildSingleChoiceWrap(
              title: 'Tipo de relación',
              options: _relationshipTypeOptions,
              selected: draft.relationshipType,
              onSelected: (String value) =>
                  _updateDraft(draft.copyWith(relationshipType: value)),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _jobTitleController,
            decoration: const InputDecoration(
              labelText: 'Trabajo / ocupación',
              hintText: 'Ej. Diseñadora, Ingeniero...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          CompanyField(
            initialValue: draft.company,
            onChanged: (String value) =>
                _updateDraft(draft.copyWith(company: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Estudios',
            options: _educationOptions,
            selected: draft.educationLevel,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(educationLevel: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Signo del zodiaco',
            options: _zodiacOptions,
            selected: draft.zodiac,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(zodiac: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildLifestyleStep(ThemeData theme, OnboardingDraft draft) {
    return _StepLayout(
      icon: _stepMeta[4].icon,
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
            title: 'Tienes hijos',
            options: _hasChildrenOptions,
            selected: draft.hasChildren,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(hasChildren: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Cannabis',
            options: _cannabisOptions,
            selected: draft.cannabis,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(cannabis: value)),
          ),
          const SizedBox(height: 12),
          _buildSingleChoiceWrap(
            title: 'Otras sustancias',
            options: _drugsOptions,
            selected: draft.drugs,
            onSelected: (String value) =>
                _updateDraft(draft.copyWith(drugs: value)),
          ),
          const SizedBox(height: 12),
          _buildMultiChoiceWrap(
            title: 'Mascotas',
            options: _petOptions,
            selected: draft.pets,
            onChanged: (List<String> values) =>
                _updateDraft(draft.copyWith(pets: values)),
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
      icon: _stepMeta[5].icon,
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
      icon: _stepMeta[6].icon,
      title: 'Preferencias iniciales',
      subtitle: 'Personaliza a quien te mostraremos mas frecuentemente.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // "En quién tienes interés" es una pregunta romántica: solo en
          // citas/ambas (intent-first). En amistad/grupos no aplica.
          if (_isRomantic(draft)) ...<Widget>[
            _buildMultiChoiceWrap(
              title: 'Interes inicial *',
              options: _interestedInOptions,
              selected: draft.interestedIn,
              onChanged: (List<String> values) =>
                  _updateDraft(draft.copyWith(interestedIn: values)),
            ),
            const SizedBox(height: 16),
          ],
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

    return AttraCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.place_rounded,
                  size: 18, color: AppColors.attraRed),
              const SizedBox(width: 8),
              Text(
                'Ubicacion para perfiles cercanos',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: context.colors.textPrimary),
              ),
            ],
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

  Future<DateTime?> _pickBirthDate(DateTime? current) async {
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
                      brightness: Brightness.dark,
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

    return mounted ? picked : null;
  }

  Future<void> _selectBirthDate(DateTime? current) async {
    final DateTime? picked = await _pickBirthDate(current);
    if (!mounted || picked == null || _draft == null) return;
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

  /// Paso OPCIONAL: preguntas de perfil (Attra Prompts). Reutiliza el editor del
  /// perfil conectado al BORRADOR en memoria (sin Firestore). Se puede saltar:
  /// el footer permite "Finalizar" aunque no haya ninguna.
  Widget _buildPromptsStep(ThemeData theme, OnboardingDraft draft) {
    final List<ProfilePrompt> prompts = draft.prompts
        .where((ProfilePrompt p) => p.isActive)
        .toList(growable: false);

    return _StepLayout(
      icon: _stepMeta[7].icon,
      title: 'Tus preguntas (opcional)',
      subtitle:
          'Da chispa a tu perfil. Elige preguntas del catálogo o crea las tuyas y respóndelas. Puedes saltarte este paso y añadirlas luego desde tu perfil.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          if (prompts.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.colors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: context.colors.surfaceLine),
              ),
              child: Column(
                children: <Widget>[
                  const Icon(Icons.chat_bubble_outline_rounded,
                      size: 40, color: AppColors.attraRed),
                  const SizedBox(height: 12),
                  Text(
                    'Aún no has añadido preguntas',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Las preguntas dan tema de conversación y mejoran tus matches.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: context.colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            for (final ProfilePrompt p in prompts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: context.colors.surfaceLine),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(p.question,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: context.colors.textSecondary)),
                      const SizedBox(height: 6),
                      Text(p.answer,
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, height: 1.25)),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 12),
          AttraPrimaryButton(
            label: prompts.isEmpty ? 'Elegir preguntas' : 'Editar preguntas',
            icon: Icons.add_comment_rounded,
            expand: false,
            onPressed: _submitting ? null : () => _openPromptsEditor(draft),
          ),
        ],
      ),
    );
  }

  Future<void> _openPromptsEditor(OnboardingDraft draft) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfilePromptsEditorScreen(
        // Carga/guarda contra el BORRADOR en memoria (no Firestore todavía).
        loadPrompts: () async => _draft?.prompts ?? const <ProfilePrompt>[],
        savePrompts: (List<ProfilePrompt> updated) async {
          final OnboardingDraft? current = _draft;
          if (current == null) return;
          _updateDraft(current.copyWith(prompts: updated));
        },
      ),
    ));
  }

  Widget _buildSingleChoiceWrap({
    required String title,
    required List<_OptionItem> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return _ChoiceGroup(
      title: title,
      options: options,
      isSelected: (String value) => selected == value,
      onTap: onSelected,
    );
  }

  Widget _buildMultiChoiceWrap({
    required String title,
    required List<_OptionItem> options,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    return _ChoiceGroup(
      title: title,
      options: options,
      multi: true,
      isSelected: (String value) => selected.contains(value),
      onTap: (String value) {
        final List<String> next = List<String>.from(selected);
        if (next.contains(value)) {
          next.remove(value);
        } else {
          next.add(value);
        }
        onChanged(next);
      },
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

class _SetupModeCard extends StatelessWidget {
  const _SetupModeCard({
    required this.icon,
    required this.title,
    required this.duration,
    required this.description,
    required this.features,
    required this.onTap,
    this.recommended = false,
  });

  final IconData icon;
  final String title;
  final String duration;
  final String description;
  final List<String> features;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AttraCard(
      onTap: onTap,
      borderColor:
          recommended ? context.colors.accent : context.colors.surfaceLine,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: recommended
                      ? context.colors.accentSoft
                      : context.colors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  icon,
                  color: recommended
                      ? context.colors.accent
                      : context.colors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (recommended)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.accentSoft,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                            ),
                            child: Text(
                              'Recomendado',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: context.colors.accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      duration,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: recommended
                            ? context.colors.accent
                            : context.colors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                color: context.colors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 14),
          for (final String feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 17,
                    color: recommended
                        ? context.colors.accent
                        : context.colors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(feature, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.attraRed.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.attraRed),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.colors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.title,
    required this.subtitle,
    required this.child,
    this.icon,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? c) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 16),
            child: c,
          ),
        );
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.action),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.attraRed.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: context.colors.textPrimary, size: 26),
              ),
              const SizedBox(height: 16),
            ],
            Text(title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(height: 6),
            Text(subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.colors.textSecondary, height: 1.4)),
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

/// Barra de progreso segmentada (un segmento por paso) que se rellena con el
/// degradado de marca de forma animada.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(total, (int i) {
        final bool filled = i <= current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              height: 5,
              decoration: BoxDecoration(
                gradient: filled
                    ? const LinearGradient(colors: AppColors.action)
                    : null,
                color: filled ? null : context.colors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Botón circular de navegación (atrás) con estilo grafito.
class _CircleNavButton extends StatelessWidget {
  const _CircleNavButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Material(
      color: context.colors.surfaceHigh,
      shape: CircleBorder(
        side: BorderSide(color: context.colors.surfaceLine),
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(icon,
              color: enabled
                  ? context.colors.textPrimary
                  : context.colors.textMuted),
        ),
      ),
    );
  }
}

/// Marco circular para la selfie en vivo: anillo con degradado de marca y glow
/// cuando hay foto; placeholder con icono cuando no.
class _SelfieRing extends StatelessWidget {
  const _SelfieRing({
    required this.hasSelfie,
    required this.image,
    required this.onTap,
  });

  final bool hasSelfie;
  final ImageProvider? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: hasSelfie
                ? AppColors.action
                : <Color>[
                    context.colors.surfaceLine,
                    context.colors.surfaceHigh
                  ],
          ),
          boxShadow: hasSelfie
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.attraRed.withValues(alpha: 0.4),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: image != null
              ? Image(image: image!, fit: BoxFit.cover)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.add_a_photo_rounded,
                        size: 44, color: context.colors.textMuted),
                    const SizedBox(height: 10),
                    Text('Toca para\ntomar tu selfie',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 13,
                            height: 1.3)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Grupo de selección (única o múltiple) con título y pills animadas.
class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.title,
    required this.options,
    required this.isSelected,
    required this.onTap,
    this.multi = false,
  });

  final String title;
  final List<_OptionItem> options;
  final bool Function(String value) isSelected;
  final ValueChanged<String> onTap;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((_OptionItem option) {
            return _SelectablePill(
              label: option.label,
              selected: isSelected(option.value),
              onTap: () => onTap(option.value),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}

/// Pill seleccionable animada: grafito cuando está apagada, degradado de marca
/// con check cuando está activa.
class _SelectablePill extends StatelessWidget {
  const _SelectablePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding:
            EdgeInsets.symmetric(horizontal: selected ? 14 : 16, vertical: 10),
        decoration: BoxDecoration(
          gradient:
              selected ? const LinearGradient(colors: AppColors.action) : null,
          color: selected ? null : context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected ? Colors.transparent : context.colors.surfaceLine,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.attraRed.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (selected) ...<Widget>[
              Icon(Icons.check_rounded,
                  size: 16, color: context.colors.textPrimary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? context.colors.textPrimary
                    : context.colors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
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
  _OptionItem(value: 'trans_woman', label: 'Mujer trans'),
  _OptionItem(value: 'trans_man', label: 'Hombre trans'),
  _OptionItem(value: 'genderfluid', label: 'Género fluido'),
  _OptionItem(value: 'agender', label: 'Agénero'),
  _OptionItem(value: 'other', label: 'Otro'),
];

const List<_OptionItem> _pronounOptions = <_OptionItem>[
  _OptionItem(value: 'she', label: 'Ella'),
  _OptionItem(value: 'he', label: 'Él'),
  _OptionItem(value: 'they', label: 'Elle'),
  _OptionItem(value: 'other', label: 'Otros'),
];

const List<_OptionItem> _orientationOptions = <_OptionItem>[
  _OptionItem(value: 'straight', label: 'Hetero'),
  _OptionItem(value: 'gay', label: 'Gay'),
  _OptionItem(value: 'lesbian', label: 'Lesbiana'),
  _OptionItem(value: 'bisexual', label: 'Bisexual'),
  _OptionItem(value: 'pansexual', label: 'Pansexual'),
  _OptionItem(value: 'asexual', label: 'Asexual'),
  _OptionItem(value: 'demisexual', label: 'Demisexual'),
  _OptionItem(value: 'queer', label: 'Queer'),
  _OptionItem(value: 'questioning', label: 'Cuestionándome'),
  _OptionItem(value: 'other', label: 'Otra'),
];

const List<_OptionItem> _educationOptions = <_OptionItem>[
  _OptionItem(value: 'high_school', label: 'Secundaria'),
  _OptionItem(value: 'vocational', label: 'FP / Técnico'),
  _OptionItem(value: 'bachelor', label: 'Grado'),
  _OptionItem(value: 'master', label: 'Máster'),
  _OptionItem(value: 'phd', label: 'Doctorado'),
  _OptionItem(value: 'other', label: 'Otro'),
];

const List<_OptionItem> _hasChildrenOptions = <_OptionItem>[
  _OptionItem(value: 'no', label: 'No tengo'),
  _OptionItem(value: 'yes', label: 'Tengo hijos'),
  _OptionItem(value: 'prefer_not', label: 'Prefiero no decir'),
];

const List<_OptionItem> _relationshipTypeOptions = <_OptionItem>[
  _OptionItem(value: 'monogamous', label: 'Monógama'),
  _OptionItem(value: 'open', label: 'Abierta'),
  _OptionItem(value: 'enm', label: 'No monógama ética'),
  _OptionItem(value: 'unsure', label: 'Aún no lo sé'),
];

const List<_OptionItem> _cannabisOptions = <_OptionItem>[
  _OptionItem(value: 'never', label: 'Nunca'),
  _OptionItem(value: 'sometimes', label: 'A veces'),
  _OptionItem(value: 'often', label: 'Frecuente'),
];

const List<_OptionItem> _drugsOptions = <_OptionItem>[
  _OptionItem(value: 'never', label: 'Nunca'),
  _OptionItem(value: 'sometimes', label: 'A veces'),
  _OptionItem(value: 'often', label: 'Frecuente'),
];

const List<_OptionItem> _petOptions = <_OptionItem>[
  _OptionItem(value: 'dog', label: 'Perro'),
  _OptionItem(value: 'cat', label: 'Gato'),
  _OptionItem(value: 'bird', label: 'Pájaro'),
  _OptionItem(value: 'reptile', label: 'Reptil'),
  _OptionItem(value: 'other', label: 'Otra'),
  _OptionItem(value: 'none', label: 'Ninguna'),
  _OptionItem(value: 'want', label: 'Quiero tener'),
];

const List<_OptionItem> _zodiacOptions = <_OptionItem>[
  _OptionItem(value: 'aries', label: 'Aries'),
  _OptionItem(value: 'taurus', label: 'Tauro'),
  _OptionItem(value: 'gemini', label: 'Géminis'),
  _OptionItem(value: 'cancer', label: 'Cáncer'),
  _OptionItem(value: 'leo', label: 'Leo'),
  _OptionItem(value: 'virgo', label: 'Virgo'),
  _OptionItem(value: 'libra', label: 'Libra'),
  _OptionItem(value: 'scorpio', label: 'Escorpio'),
  _OptionItem(value: 'sagittarius', label: 'Sagitario'),
  _OptionItem(value: 'capricorn', label: 'Capricornio'),
  _OptionItem(value: 'aquarius', label: 'Acuario'),
  _OptionItem(value: 'pisces', label: 'Piscis'),
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

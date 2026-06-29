import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../../../theme/theme_controller.dart';
import '../../onboarding/data/onboarding_error_messages.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../../onboarding/domain/onboarding_draft.dart';
import '../../ai_visual/data/ai_visual_service.dart';
import '../../chat/data/chat_service.dart';
import '../../integrations/domain/integration_connector.dart';
import '../../match/data/match_service.dart';
import '../../stories/data/story_service.dart';
import '../../monetization/data/boost_service.dart';
import '../../monetization/data/entitlement_service.dart';
import '../../monetization/data/feature_flag_service.dart';
import '../../feed/data/ranking_signals_repository.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/intro_media.dart';
import '../../profile/domain/profile_prompt.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_trait.dart';
import '../../feed/data/feed_metrics_service.dart';
import '../../notifications/data/notification_service.dart';
import '../../settings/data/settings_repository.dart';
import '../../spark/data/spark_service.dart';
import '../data/auth_service.dart';
import '../data/user_repository.dart';
import '../domain/app_user.dart';
import 'session_state.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required AuthService authService,
    required UserRepository userRepository,
    required OnboardingRepository onboardingRepository,
    required SettingsRepository settingsRepository,
    required EntitlementService entitlementService,
    required FeatureFlagService featureFlagService,
    required MatchService matchService,
    required ChatService chatService,
    required ProfileSummaryRepository profileSummaryRepository,
    required RankingSignalsRepository rankingSignalsRepository,
    required StoryService storyService,
    required AiVisualService aiVisualService,
    BoostService? boostService,
    SparkService? sparkService,
    FeedMetricsService? feedMetricsService,
    NotificationService? notificationService,
    IntegrationConnector? integrationConnector,
  })  : _authService = authService,
        _sparkService = sparkService,
        _boostService = boostService,
        _feedMetricsService = feedMetricsService,
        _notificationService = notificationService,
        _integrationConnector = integrationConnector,
        _storyService = storyService,
        _aiVisualService = aiVisualService,
        _userRepository = userRepository,
        _onboardingRepository = onboardingRepository,
        _settingsRepository = settingsRepository,
        _entitlementService = entitlementService,
        _featureFlagService = featureFlagService,
        _matchService = matchService,
        _chatService = chatService,
        _profileSummaryRepository = profileSummaryRepository,
        _rankingSignalsRepository = rankingSignalsRepository {
    _authSubscription =
        _authService.authStateChanges.listen((User? firebaseUser) {
      unawaited(_handleAuthStateChange(firebaseUser));
    });
  }

  final AuthService _authService;
  final UserRepository _userRepository;
  final OnboardingRepository _onboardingRepository;
  final SettingsRepository _settingsRepository;
  final EntitlementService _entitlementService;
  final FeatureFlagService _featureFlagService;
  final MatchService _matchService;
  final ChatService _chatService;
  final ProfileSummaryRepository _profileSummaryRepository;
  final RankingSignalsRepository _rankingSignalsRepository;
  final IntegrationConnector? _integrationConnector;
  final StoryService _storyService;
  final AiVisualService _aiVisualService;
  final SparkService? _sparkService;
  final BoostService? _boostService;
  final FeedMetricsService? _feedMetricsService;
  final NotificationService? _notificationService;

  /// Bandeja de notificaciones in-app. Null si no se inyecta.
  NotificationService? get notificationService => _notificationService;

  /// Servicio de Attra Spark (juego de 5 min). Null si no se inyecta.
  SparkService? get sparkService => _sparkService;

  /// Servicio de Boosts consumibles. Null si no se inyecta.
  BoostService? get boostService => _boostService;

  /// Telemetría del feed/embudo + impresiones. Null si no se inyecta.
  FeedMetricsService? get feedMetricsService => _feedMetricsService;

  /// Conector de integraciones externas (Spotify…) para la Settings Platform.
  IntegrationConnector? get integrationConnector => _integrationConnector;

  /// Servicio de stories de vídeo 24h (lecturas + crear/ver/responder/borrar).
  StoryService get storyService => _storyService;

  /// Servicio de IA visual (Pro): referencia, insights, borrado.
  AiVisualService get aiVisualService => _aiVisualService;

  /// Concede/retira el consentimiento de IA visual (dato biométrico).
  Future<void> setAiVisualConsent(bool granted) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.setAiVisualConsent(uid: uid, granted: granted);
    await _refreshAuthenticatedUser(uid);
  }

  /// Activa/desactiva Slow Dating (ajuste `privacy.slowDating`). Refresca el
  /// usuario para que el feed reaccione (lee `AppUser.slowDatingEnabled`).
  Future<void> setSlowDatingEnabled(bool value) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _settingsRepository
        .patchValues(uid, <String, Object?>{'privacy.slowDating': value});
    await _refreshAuthenticatedUser(uid);
  }

  /// MODO VIAJES (Plus/Pro): fija (active=true) o desactiva el destino. Refresca
  /// el usuario para que el feed reaccione (lee `AppUser.travel*`).
  Future<void> setTravelLocation({
    required bool active,
    String iso2 = '',
    String city = '',
    String country = '',
  }) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.setTravelLocation(
      uid: uid,
      active: active,
      iso2: iso2,
      city: city,
      country: country,
    );
    await _refreshAuthenticatedUser(uid);
  }

  /// Repositorio de la Settings Platform (consumido por HomeShell para
  /// construir el SettingsController de la sesion).
  SettingsRepository get settingsRepository => _settingsRepository;

  /// Servicios de monetizacion (consumidos por HomeShell para construir el
  /// EntitlementController de la sesion).
  EntitlementService get entitlementService => _entitlementService;
  FeatureFlagService get featureFlagService => _featureFlagService;

  /// Servicios de match y chat (Fase 3). Lecturas en vivo + escrituras via
  /// Cloud Functions. Los consumira la UI de matches/chats (Fase 4+).
  MatchService get matchService => _matchService;
  ChatService get chatService => _chatService;
  ProfileSummaryRepository get profileSummaryRepository =>
      _profileSummaryRepository;
  RankingSignalsRepository get rankingSignalsRepository =>
      _rankingSignalsRepository;

  StreamSubscription<User?>? _authSubscription;
  bool _isDisposed = false;

  String? _phoneVerificationId;
  ConfirmationResult? _phoneConfirmationResult;

  SessionState _state = const SessionState.initializing();
  SessionState get state => _state;

  Future<void> signInWithGoogle() async {
    _emit(
      SessionState(
        status: SessionStatus.authenticating,
        user: _state.user,
      ),
    );

    try {
      await _authService.signInWithGoogle();
    } on SignInCancelledFailure {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          clearErrorMessage: true,
        ),
      );
    } on AuthFailure catch (error) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage: error.message,
        ),
      );
    }
  }

  Future<void> signInWithApple() async {
    _emit(
      SessionState(
        status: SessionStatus.authenticating,
        user: _state.user,
      ),
    );

    try {
      await _authService.signInWithApple();
    } on SignInWithAppleCancelledFailure {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          clearErrorMessage: true,
        ),
      );
    } on AuthFailure catch (error) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage: error.message,
        ),
      );
    }
  }

  Future<void> sendPhoneCode(String phoneNumber) async {
    final String normalizedPhone = _normalizePhoneNumber(phoneNumber);
    if (!_isPhoneNumberValid(normalizedPhone)) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage:
              'Numero invalido. Usa formato internacional, por ejemplo +34600111222.',
        ),
      );
      return;
    }

    _clearPhoneFlow();
    _emit(
      _state.copyWith(
        status: SessionStatus.authenticating,
        clearErrorMessage: true,
        phoneCodeSent: false,
      ),
    );

    try {
      final PhoneAuthSession phoneSession =
          await _authService.startPhoneSignIn(normalizedPhone);

      if (phoneSession.completedSignIn) {
        _emit(
          _state.copyWith(
            status: SessionStatus.loadingProfile,
            clearErrorMessage: true,
            phoneCodeSent: false,
          ),
        );
        return;
      }

      _phoneVerificationId = phoneSession.verificationId;
      _phoneConfirmationResult = phoneSession.confirmationResult;

      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          clearErrorMessage: true,
          phoneCodeSent: phoneSession.requiresSmsCode,
        ),
      );
    } on AuthFailure catch (error) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage: error.message,
          phoneCodeSent: false,
        ),
      );
    }
  }

  Future<void> verifyPhoneCode(String smsCode) async {
    final String normalizedCode = smsCode.trim();
    if (normalizedCode.length < 4) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage: 'Introduce un codigo SMS valido.',
          phoneCodeSent: true,
        ),
      );
      return;
    }

    _emit(
      _state.copyWith(
        status: SessionStatus.authenticating,
        clearErrorMessage: true,
        phoneCodeSent: true,
      ),
    );

    try {
      await _authService.confirmPhoneCode(
        smsCode: normalizedCode,
        verificationId: _phoneVerificationId,
        confirmationResult: _phoneConfirmationResult,
      );
      _emit(
        _state.copyWith(
          status: SessionStatus.loadingProfile,
          clearErrorMessage: true,
          phoneCodeSent: false,
        ),
      );
    } on AuthFailure catch (error) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage: error.message,
          phoneCodeSent: true,
        ),
      );
    }
  }

  Future<OnboardingDraft> loadOnboardingDraft() async {
    final String? uid = _state.user?.uid;
    if (uid == null) {
      throw const OnboardingRepositoryException(
        'No hay sesion activa para cargar onboarding.',
      );
    }

    final OnboardingDraft? remoteDraft =
        await _onboardingRepository.loadDraft(uid);
    if (remoteDraft != null) {
      return remoteDraft;
    }

    return OnboardingDraft.fromUser(_state.user);
  }

  Future<void> saveOnboardingDraft(OnboardingDraft draft) async {
    try {
      await _onboardingRepository.saveDraftForUser(_state.user, draft);
    } catch (error) {
      _emit(
        _state.copyWith(
          status: SessionStatus.onboardingRequired,
          errorMessage: onboardingSaveErrorMessage(error),
        ),
      );
    }
  }

  Future<LiveSelfieDraftUpload> uploadOnboardingLiveSelfieDraft({
    required Uint8List liveSelfieBytes,
    required String liveSelfieFileExtension,
  }) async {
    final String? uid = _state.user?.uid;
    if (uid == null) {
      throw const OnboardingRepositoryException(
        'No hay sesion activa para subir la selfie en vivo.',
      );
    }

    return _onboardingRepository.uploadDraftLiveSelfie(
      uid: uid,
      bytes: liveSelfieBytes,
      fileExtension: liveSelfieFileExtension,
    );
  }

  Future<void> submitOnboarding({
    required OnboardingDraft draft,
    Uint8List? liveSelfieBytes,
    String? liveSelfieFileExtension,
  }) async {
    final AppUser? currentUser = _state.user;
    final String? uid = currentUser?.uid;
    if (uid == null) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage: 'No hay sesion activa para completar onboarding.',
        ),
      );
      return;
    }

    _emit(
      _state.copyWith(
        status: SessionStatus.loadingProfile,
        clearErrorMessage: true,
      ),
    );

    try {
      await _onboardingRepository.submitOnboarding(
        uid: uid,
        draft: draft,
        liveSelfieBytes: liveSelfieBytes,
        liveSelfieFileExtension: liveSelfieFileExtension ?? 'jpg',
      );

      // Paso opcional de prompts: si el usuario rellenó alguno, se persisten
      // por la misma vía que el editor del perfil (espeja legacy + discovery).
      if (draft.prompts.isNotEmpty) {
        try {
          await _userRepository.saveProfilePrompts(
              uid: uid, prompts: draft.prompts);
        } catch (_) {
          // No bloquea el alta: los prompts se pueden añadir luego del perfil.
        }
      }

      final AppUser updatedUser = await _userRepository.fetchByUid(uid);
      _emit(
        SessionState(
          status: SessionStatus.authenticated,
          user: updatedUser,
        ),
      );
    } catch (error) {
      _emit(
        SessionState(
          status: SessionStatus.onboardingRequired,
          user: currentUser,
          errorMessage: onboardingSaveErrorMessage(error),
        ),
      );
    }
  }

  Future<void> signOut() async {
    final SessionState previousState = _state;
    _emit(
      SessionState(
        status: SessionStatus.signingOut,
        user: previousState.user,
      ),
    );

    try {
      _clearPhoneFlow();
      await _authService.signOut();
    } on AuthFailure catch (error) {
      _emit(
        SessionState(
          status: previousState.status,
          user: previousState.user,
          errorMessage: error.message,
        ),
      );
    }
  }

  Future<void> deleteAccount() async {
    final SessionState previousState = _state;
    final String? uid = previousState.user?.uid;
    if (uid == null) {
      _emit(
        previousState.copyWith(
          status: SessionStatus.unauthenticated,
          errorMessage: 'No hay sesion activa para eliminar la cuenta.',
        ),
      );
      return;
    }

    _emit(
      SessionState(
        status: SessionStatus.signingOut,
        user: previousState.user,
      ),
    );

    try {
      await _userRepository.deleteUserData(uid);
      await _authService.deleteCurrentUserAccount();
      _clearPhoneFlow();
    } on AuthFailure catch (error) {
      _emit(
        SessionState(
          status: SessionStatus.authenticated,
          user: previousState.user,
          errorMessage: error.message,
        ),
      );
    } catch (error) {
      _emit(
        SessionState(
          status: SessionStatus.authenticated,
          user: previousState.user,
          errorMessage:
              'No se pudo eliminar la cuenta en este momento. ($error)',
        ),
      );
    }
  }

  Future<ProfileCompletionState> loadProfileCompletionState() async {
    final String? uid = _state.user?.uid;
    if (uid == null) {
      throw const OnboardingRepositoryException(
        'No hay sesion activa para cargar perfil.',
      );
    }
    return _userRepository.fetchProfileCompletionState(uid);
  }

  Future<void> uploadAdditionalPhoto({
    required Uint8List photoBytes,
    required String fileExtension,
    required String source,
  }) async {
    final String? uid = _state.user?.uid;
    if (uid == null) {
      return;
    }
    await _userRepository.uploadAdditionalPhoto(
      uid: uid,
      bytes: photoBytes,
      fileExtension: fileExtension,
      source: source,
    );
    await _refreshAuthenticatedUser(uid);
  }

  Future<void> deleteAdditionalPhoto(String storagePath) async {
    final String? uid = _state.user?.uid;
    if (uid == null) {
      return;
    }
    await _userRepository.deleteAdditionalPhoto(
      uid: uid,
      storagePath: storagePath,
    );
    await _refreshAuthenticatedUser(uid);
  }

  // ── Media de presentación (audio/vídeo) ──────────────────────────────────

  /// Carga la media de presentación actual del usuario (audio + vídeo).
  Future<({IntroAudio? audio, IntroVideo? video})> loadIntroMedia() async {
    final String? uid = _state.user?.uid;
    if (uid == null) return (audio: null, video: null);
    final Map<String, dynamic> data = await _userRepository.fetchUserData(uid);
    final Object? profile = data['profile'];
    final Map<String, dynamic> p = profile is Map
        ? profile.map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    return (
      audio: IntroAudio.fromMap(p['introAudio']),
      video: IntroVideo.fromMap(p['introVideo']),
    );
  }

  Future<void> uploadIntroAudio({
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.uploadIntroAudio(
      uid: uid,
      bytes: bytes,
      contentType: contentType,
      extension: extension,
      durationMs: durationMs,
    );
    await _refreshAuthenticatedUser(uid);
  }

  Future<void> deleteIntroAudio() async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.deleteIntroAudio(uid: uid);
    await _refreshAuthenticatedUser(uid);
  }

  Future<void> uploadIntroVideo({
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.uploadIntroVideo(
      uid: uid,
      bytes: bytes,
      contentType: contentType,
      extension: extension,
      durationMs: durationMs,
    );
    await _refreshAuthenticatedUser(uid);
  }

  Future<void> deleteIntroVideo() async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.deleteIntroVideo(uid: uid);
    await _refreshAuthenticatedUser(uid);
  }

  Future<void> addOptionalPrompt(String prompt) async {
    final String? uid = _state.user?.uid;
    if (uid == null) {
      return;
    }
    await _userRepository.addPrompt(uid: uid, prompt: prompt);
    await _refreshAuthenticatedUser(uid);
  }

  Future<void> claimProfileReward(String rewardId) async {
    final String? uid = _state.user?.uid;
    if (uid == null) {
      return;
    }
    await _userRepository.claimProfileReward(uid: uid, rewardId: rewardId);
    await _refreshAuthenticatedUser(uid);
  }

  /// Datos crudos del usuario (para la pantalla de editar rasgos).
  Future<Map<String, dynamic>> loadProfileRaw() async {
    final String? uid = _state.user?.uid;
    if (uid == null) return <String, dynamic>{};
    return _userRepository.fetchUserData(uid);
  }

  /// Guarda/borra un rasgo de perfil (gratis; nunca infiere ni autorrellena).
  Future<void> setProfileTrait(
      ProfileTraitDefinition def, Object? value) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.setProfileTrait(uid: uid, def: def, value: value);
    await _refreshAuthenticatedUser(uid);
  }

  /// Actualiza el consentimiento por campo (mostrar/matching/filtros).
  Future<void> setTraitVisibility(
    String traitKey, {
    required bool visibleInProfile,
    required bool useForMatching,
    required bool useForFilters,
  }) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.setTraitVisibility(
      uid: uid,
      traitKey: traitKey,
      visibleInProfile: visibleInProfile,
      useForMatching: useForMatching,
      useForFilters: useForFilters,
    );
    await _refreshAuthenticatedUser(uid);
  }

  /// Carga el perfil de un usuario por uid (para verlo desde chats/matches).
  Future<SeedProfile?> loadProfileByUid(String uid) =>
      _userRepository.fetchProfileByUid(uid);

  /// Prompts de perfil (preguntas/respuestas) del usuario actual.
  Future<List<ProfilePrompt>> loadProfilePrompts() async {
    final String? uid = _state.user?.uid;
    if (uid == null) return const <ProfilePrompt>[];
    return _userRepository.fetchProfilePrompts(uid);
  }

  Future<void> saveProfilePrompts(List<ProfilePrompt> prompts) async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.saveProfilePrompts(uid: uid, prompts: prompts);
    await _refreshAuthenticatedUser(uid);
  }

  Future<List<SeedProfile>> loadSeedProfiles() async {
    final String uid = _state.user?.uid ?? '';
    // Seeds (bots) son la base; los perfiles reales (discovery) se anaden si
    // la lectura esta permitida. Si discovery falla (reglas aun no publicadas),
    // el feed sigue mostrando los seeds.
    final List<SeedProfile> seeds = await _userRepository.fetchSeedProfiles();
    List<SeedProfile> discovery = const <SeedProfile>[];
    try {
      discovery = await _userRepository.fetchDiscoveryProfiles(excludeUid: uid);
    } catch (_) {
      discovery = const <SeedProfile>[];
    }
    return <SeedProfile>[...discovery, ...seeds];
  }

  Future<void> _handleAuthStateChange(User? firebaseUser) async {
    if (firebaseUser == null) {
      _emit(
        _state.copyWith(
          status: SessionStatus.unauthenticated,
          clearUser: true,
          clearErrorMessage: true,
          phoneCodeSent: false,
        ),
      );
      return;
    }

    _clearPhoneFlow();

    _emit(
      _state.copyWith(
        status: SessionStatus.loadingProfile,
        clearErrorMessage: true,
        phoneCodeSent: false,
      ),
    );

    try {
      final UserSyncResult syncResult =
          await _userRepository.syncUserFromAuth(firebaseUser);

      if (syncResult.needsOnboarding) {
        _emit(
          SessionState(
            status: SessionStatus.onboardingRequired,
            user: syncResult.user,
          ),
        );
        return;
      }

      _emit(
        SessionState(
          status: SessionStatus.authenticated,
          user: syncResult.user,
        ),
      );
    } catch (error) {
      _emit(
        SessionState(
          status: SessionStatus.onboardingRequired,
          user: _buildFallbackUser(firebaseUser),
          errorMessage: _profileSyncErrorMessage(error),
        ),
      );
    }
  }

  String _profileSyncErrorMessage(Object error) {
    if (error is FirebaseException) {
      if (kDebugMode) {
        debugPrint(
          '[Attra][SessionSync] FirebaseException '
          'plugin=${error.plugin} code=${error.code} message=${error.message}',
        );
      }
      final String detail = (error.message ?? '').trim();
      switch (error.code) {
        case 'permission-denied':
          return 'Firestore denego users/{uid} (code: ${error.code}). '
              'Detalle: ${detail.isEmpty ? 'sin detalle' : detail}';
        case 'unavailable':
          return 'Login OK, pero Firestore no esta disponible en este momento. (code: ${error.code})';
        case 'failed-precondition':
          return 'Login OK, pero Firestore no esta configurado para este proyecto. (code: ${error.code})';
        default:
          return 'Login OK, pero fallo la sincronizacion en Firestore. '
              '(code: ${error.code}) ${detail.isEmpty ? '' : 'Detalle: $detail'}';
      }
    }
    if (error is StateError) {
      return error.message;
    }
    return 'Login OK, pero no se pudo sincronizar perfil en Firestore.';
  }

  AppUser _buildFallbackUser(User firebaseUser) {
    return AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email,
      displayName: firebaseUser.displayName,
      photoUrl: firebaseUser.photoURL,
      onboardingCompleted: false,
      profileCompleted: false,
      profileCompletionPercent: 0,
      isBot: false,
    );
  }

  Future<void> _refreshAuthenticatedUser(String uid) async {
    final SessionState previous = _state;
    if (previous.status != SessionStatus.authenticated ||
        previous.user == null) {
      return;
    }
    final AppUser updated = await _userRepository.fetchByUid(uid);
    _emit(
      SessionState(
        status: SessionStatus.authenticated,
        user: updated,
        errorMessage: previous.errorMessage,
      ),
    );
  }

  bool _isPhoneNumberValid(String value) {
    final RegExp exp = RegExp(r'^\+[1-9]\d{7,14}$');
    return exp.hasMatch(value);
  }

  String _normalizePhoneNumber(String raw) {
    String normalized = raw.trim();
    normalized = normalized.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (normalized.startsWith('00')) {
      normalized = '+${normalized.substring(2)}';
    }
    return normalized;
  }

  void _clearPhoneFlow() {
    _phoneVerificationId = null;
    _phoneConfirmationResult = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }

  void _emit(SessionState newState) {
    if (_isDisposed) {
      return;
    }
    _state = newState;
    // Aplica la preferencia de tema del usuario (claro/oscuro/sistema) en cuanto
    // se conoce, para que persista entre sesiones.
    final AppUser? u = newState.user;
    if (u != null) {
      ThemeController.instance.set(ThemeController.fromWire(u.themeModeWire));
    }
    notifyListeners();
  }

  /// Cambia el modo de tema (Ajustes): aplica al instante (ThemeController) y lo
  /// persiste en `settings['appearance.themeMode']`.
  Future<void> setThemeMode(ThemeMode mode) async {
    ThemeController.instance.set(mode);
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _settingsRepository.patchValues(uid, <String, Object?>{
      'appearance.themeMode': ThemeController.toWire(mode)
    });
  }

  /// Re-publica el doc público de discovery del usuario actual. Lo llama Ajustes
  /// tras cambiar una opción de visibilidad/ubicación para que tenga efecto
  /// inmediato (ocultarse del feed, ocultar ciudad, fuzz de ubicación…).
  Future<void> republishDiscovery() async {
    final String? uid = _state.user?.uid;
    if (uid == null) return;
    await _userRepository.republishDiscovery(uid);
  }
}

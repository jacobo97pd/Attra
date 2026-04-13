import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../onboarding/data/onboarding_repository.dart';
import '../../onboarding/domain/onboarding_draft.dart';
import '../../profile/domain/profile_state.dart';
import '../data/auth_service.dart';
import '../data/user_repository.dart';
import '../domain/app_user.dart';
import 'session_state.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required AuthService authService,
    required UserRepository userRepository,
    required OnboardingRepository onboardingRepository,
  })  : _authService = authService,
        _userRepository = userRepository,
        _onboardingRepository = onboardingRepository {
    _authSubscription =
        _authService.authStateChanges.listen((User? firebaseUser) {
      unawaited(_handleAuthStateChange(firebaseUser));
    });
  }

  final AuthService _authService;
  final UserRepository _userRepository;
  final OnboardingRepository _onboardingRepository;

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
    final String? uid = _state.user?.uid;
    if (uid == null) {
      return;
    }

    try {
      await _onboardingRepository.saveDraft(uid, draft);
    } catch (error) {
      _emit(
        _state.copyWith(
          status: SessionStatus.onboardingRequired,
          errorMessage: _onboardingSaveErrorMessage(error),
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
          errorMessage: _onboardingSaveErrorMessage(error),
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

  Future<List<SeedProfile>> loadSeedProfiles() async {
    return _userRepository.fetchSeedProfiles();
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
      switch (error.code) {
        case 'permission-denied':
          return 'Login OK, pero Firestore deniega crear/actualizar users/{uid}. Revisa reglas o permisos IAM. (code: ${error.code})';
        case 'unavailable':
          return 'Login OK, pero Firestore no esta disponible en este momento. (code: ${error.code})';
        case 'failed-precondition':
          return 'Login OK, pero Firestore no esta configurado para este proyecto. (code: ${error.code})';
        default:
          return 'Login OK, pero fallo la sincronizacion en Firestore. (code: ${error.code})';
      }
    }
    if (error is StateError) {
      return error.message;
    }
    return 'Login OK, pero no se pudo sincronizar perfil en Firestore.';
  }

  String _onboardingSaveErrorMessage(Object error) {
    if (error is OnboardingRepositoryException) {
      return error.message;
    }
    if (error is FirebaseException) {
      return 'No se pudo guardar onboarding. (code: ${error.code})';
    }
    return 'No se pudo guardar onboarding. Intentalo nuevamente.';
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
    notifyListeners();
  }
}

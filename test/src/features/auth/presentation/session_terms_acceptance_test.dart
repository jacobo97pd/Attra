import 'dart:async';

import 'package:attra/src/features/ai_visual/data/ai_visual_service.dart';
import 'package:attra/src/features/auth/data/auth_service.dart';
import 'package:attra/src/features/auth/data/user_repository.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/auth/presentation/session_controller.dart';
import 'package:attra/src/features/auth/presentation/session_state.dart';
import 'package:attra/src/features/chat/data/chat_service.dart';
import 'package:attra/src/features/feed/data/ranking_signals_repository.dart';
import 'package:attra/src/features/match/data/match_service.dart';
import 'package:attra/src/features/monetization/data/entitlement_service.dart';
import 'package:attra/src/features/monetization/data/feature_flag_service.dart';
import 'package:attra/src/features/onboarding/data/onboarding_repository.dart';
import 'package:attra/src/features/onboarding/data/voice_profile_service.dart';
import 'package:attra/src/features/profile/data/profile_summary_repository.dart';
import 'package:attra/src/features/settings/data/settings_repository.dart';
import 'package:attra/src/features/stories/data/story_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _AuthEvents auth;
  late _UserRepository users;
  late SessionController controller;

  setUp(() {
    auth = _AuthEvents();
    users = _UserRepository();
    controller = SessionController(
      authService: auth,
      userRepository: users,
      onboardingRepository: _UnusedOnboarding(),
      voiceProfileService: _UnusedVoice(),
      settingsRepository: _UnusedSettings(),
      entitlementService: _UnusedEntitlements(),
      featureFlagService: _UnusedFlags(),
      matchService: _UnusedMatches(),
      chatService: _UnusedChat(),
      profileSummaryRepository: _UnusedProfiles(),
      rankingSignalsRepository: _UnusedRanking(),
      storyService: _UnusedStories(),
      aiVisualService: _UnusedAi(),
    );
  });

  tearDown(() async {
    controller.dispose();
    await auth.events.close();
  });

  Future<void> emitAuth(User? user,
      {SessionStatus? expectedStatus, bool expectError = false}) async {
    final Completer<void> settled = Completer<void>();
    void onStateChanged() {
      if (controller.state.status != SessionStatus.loadingProfile &&
          !settled.isCompleted) {
        settled.complete();
      }
    }

    controller.addListener(onStateChanged);
    try {
      auth.events.add(user);
      await settled.future;
      expect(controller.state.errorMessage, expectError ? isNotNull : isNull);
      expect(
        controller.state.status,
        expectedStatus ??
            (user == null
                ? SessionStatus.unauthenticated
                : SessionStatus.authenticated),
      );
    } finally {
      controller.removeListener(onStateChanged);
    }
  }

  test('una sesión antigua requiere el EULA antes de acceder al contenido',
      () async {
    await emitAuth(_FirebaseUser('restored-user'),
        expectedStatus: SessionStatus.termsRequired);

    expect(users.syncedUids, <String>['restored-user']);
    expect(users.acceptedUids, isEmpty);
  });

  test('una sesión con aceptación vigente entra sin pedirla de nuevo',
      () async {
    users.existingAcceptances.add('returning-user');
    await emitAuth(_FirebaseUser('returning-user'));
    expect(users.acceptedUids, isEmpty);
  });

  test('aceptar desde la sesión antigua guarda antes de dar acceso', () async {
    await emitAuth(_FirebaseUser('restored-user'),
        expectedStatus: SessionStatus.termsRequired);
    users.recordPending = Completer<void>();
    final Future<void> accepting = controller.acceptTermsForCurrentSession();
    expect(controller.state.status, SessionStatus.acceptingTerms);
    users.recordPending!.complete();
    await accepting;
    expect(controller.state.status, SessionStatus.authenticated);
    expect(users.acceptedUids, <String>['restored-user']);
  });

  test('un fallo de escritura conserva el gate y permite reintentar', () async {
    await emitAuth(_FirebaseUser('restored-user'),
        expectedStatus: SessionStatus.termsRequired);
    users.failRecording = true;
    await controller.acceptTermsForCurrentSession();
    expect(controller.state.status, SessionStatus.termsRequired);
    expect(controller.state.errorMessage, isNotNull);
    expect(users.acceptedUids, isEmpty);
    users.failRecording = false;
    await controller.acceptTermsForCurrentSession();
    expect(controller.state.status, SessionStatus.authenticated);
    expect(controller.state.errorMessage, isNull);
  });

  test('un fallo al comprobar el EULA nunca da acceso por defecto', () async {
    users.failReading = true;
    await emitAuth(_FirebaseUser('restored-user'),
        expectedStatus: SessionStatus.termsRequired, expectError: true);
    expect(users.acceptedUids, isEmpty);
  });

  test('un fallo al guardar desde login también exige reintentar', () async {
    users.failRecording = true;
    controller.confirmTermsAcceptedForSignIn();
    await emitAuth(_FirebaseUser('new-sign-in'),
        expectedStatus: SessionStatus.termsRequired, expectError: true);
    expect(users.acceptedUids, isEmpty);
  });

  test('una escritura pendiente no restaura una sesión que ya se cerró',
      () async {
    await emitAuth(_FirebaseUser('restored-user'),
        expectedStatus: SessionStatus.termsRequired);
    users.recordPending = Completer<void>();
    final Future<void> accepting = controller.acceptTermsForCurrentSession();
    await emitAuth(null);
    users.recordPending!.complete();
    await accepting;
    expect(controller.state.status, SessionStatus.unauthenticated);
    expect(controller.state.user, isNull);
  });

  test('una cuenta sin onboarding solo pasa al onboarding tras aceptar',
      () async {
    users.completedOnboarding = false;
    await emitAuth(_FirebaseUser('incomplete-user'),
        expectedStatus: SessionStatus.termsRequired);
    await controller.acceptTermsForCurrentSession();
    expect(controller.state.status, SessionStatus.onboardingRequired);
  });

  test('el acceso con aceptación explícita registra el EULA para ese usuario',
      () async {
    await emitAuth(null);
    controller.confirmTermsAcceptedForSignIn();

    await emitAuth(_FirebaseUser('signed-in-user'));

    expect(users.acceptedUids, <String>['signed-in-user']);
  });

  test('los siguientes eventos de autenticación no repiten la aceptación',
      () async {
    controller.confirmTermsAcceptedForSignIn();
    await emitAuth(_FirebaseUser('signed-in-user'));
    await emitAuth(_FirebaseUser('signed-in-user'));

    expect(users.syncedUids, <String>['signed-in-user', 'signed-in-user']);
    expect(users.acceptedUids, <String>['signed-in-user']);
  });

  test('salir descarta una aceptación pendiente para la siguiente sesión',
      () async {
    controller.confirmTermsAcceptedForSignIn();
    await emitAuth(null);
    await emitAuth(_FirebaseUser('another-user'),
        expectedStatus: SessionStatus.termsRequired);

    expect(users.acceptedUids, isEmpty);
  });

  test('un refresco pendiente no restaura una sesión cerrada', () async {
    users.existingAcceptances.add('first-user');
    await emitAuth(_FirebaseUser('first-user'));
    users.fetchPending = Completer<AppUser>();
    final Future<void> refreshing = controller.refreshCurrentUser();
    expect(users.fetchedUids, <String>['first-user']);

    await emitAuth(null);
    users.fetchPending!.complete(_appUser('first-user'));
    await refreshing;

    expect(controller.state.status, SessionStatus.unauthenticated);
    expect(controller.state.user, isNull);
  });

  for (final bool secondUserAccepted in <bool>[false, true]) {
    final SessionStatus expectedStatus = secondUserAccepted
        ? SessionStatus.authenticated
        : SessionStatus.termsRequired;
    test('un refresco anterior no sustituye otra cuenta en $expectedStatus',
        () async {
      users.existingAcceptances.add('first-user');
      if (secondUserAccepted) users.existingAcceptances.add('second-user');
      await emitAuth(_FirebaseUser('first-user'));
      users.fetchPending = Completer<AppUser>();
      final Future<void> refreshing = controller.refreshCurrentUser();
      expect(users.fetchedUids, <String>['first-user']);

      await emitAuth(_FirebaseUser('second-user'),
          expectedStatus: expectedStatus);
      users.fetchPending!.complete(_appUser('first-user'));
      await refreshing;

      expect(controller.state.status, expectedStatus);
      expect(controller.state.user?.uid, 'second-user');
      expect(users.acceptedUids, isEmpty);
    });
  }

  for (final bool termsAccepted in <bool>[false, true]) {
    final SessionStatus expectedStatus = termsAccepted
        ? SessionStatus.authenticated
        : SessionStatus.termsRequired;
    test('la respuesta OTP tardía conserva el estado $expectedStatus',
        () async {
      if (termsAccepted) users.existingAcceptances.add('phone-user');
      await emitAuth(null);
      await controller.sendPhoneCode('+34600000000');
      expect(controller.state.phoneCodeSent, isTrue);
      auth.phoneConfirmationPending = Completer<void>();
      final Future<void> confirming = controller.verifyPhoneCode('123456');
      expect(controller.state.status, SessionStatus.authenticating);
      expect(auth.confirmedVerificationId, 'verification-id');

      // Firebase puede emitir authStateChanges y terminar de cargar la cuenta
      // antes de resolver el Future que confirma el código.
      await emitAuth(_FirebaseUser('phone-user'),
          expectedStatus: expectedStatus);
      auth.phoneConfirmationPending!.complete();
      await confirming;

      expect(controller.state.status, expectedStatus);
      expect(controller.state.user?.uid, 'phone-user');
      expect(controller.state.phoneCodeSent, isFalse);
    });

    test('la verificación automática tardía conserva $expectedStatus',
        () async {
      if (termsAccepted) users.existingAcceptances.add('automatic-user');
      await emitAuth(null);
      auth.phoneStartPending = Completer<PhoneAuthSession>();
      final Future<void> starting = controller.sendPhoneCode('+34600000000');
      expect(controller.state.status, SessionStatus.authenticating);

      await emitAuth(_FirebaseUser('automatic-user'),
          expectedStatus: expectedStatus);
      auth.phoneStartPending!.complete(
        const PhoneAuthSession(completedSignIn: true),
      );
      await starting;

      expect(controller.state.status, expectedStatus);
      expect(controller.state.user?.uid, 'automatic-user');
      expect(controller.state.phoneCodeSent, isFalse);
    });
  }
}

class _UnexpectedCalls {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Llamada inesperada: ${invocation.memberName}');
}

class _AuthEvents extends _UnexpectedCalls implements AuthService {
  final StreamController<User?> events = StreamController<User?>();
  Completer<PhoneAuthSession>? phoneStartPending;
  Completer<void>? phoneConfirmationPending;
  String? confirmedVerificationId;

  @override
  Stream<User?> get authStateChanges => events.stream;

  @override
  Future<PhoneAuthSession> startPhoneSignIn(String phoneNumber) async {
    if (phoneStartPending != null) return phoneStartPending!.future;
    return const PhoneAuthSession(verificationId: 'verification-id');
  }

  @override
  Future<void> confirmPhoneCode({
    required String smsCode,
    String? verificationId,
    ConfirmationResult? confirmationResult,
  }) async {
    confirmedVerificationId = verificationId;
    if (phoneConfirmationPending != null) {
      await phoneConfirmationPending!.future;
    }
  }
}

class _FirebaseUser extends _UnexpectedCalls implements User {
  _FirebaseUser(this.uid);

  @override
  final String uid;
}

class _UserRepository extends _UnexpectedCalls implements UserRepository {
  final List<String> syncedUids = <String>[];
  final List<String> fetchedUids = <String>[];
  final List<String> acceptedUids = <String>[];
  final Set<String> existingAcceptances = <String>{};
  bool failReading = false;
  bool failRecording = false;
  bool completedOnboarding = true;
  Completer<void>? recordPending;
  Completer<AppUser>? fetchPending;

  @override
  Future<UserSyncResult> syncUserFromAuth(User firebaseUser) async {
    syncedUids.add(firebaseUser.uid);
    return UserSyncResult(
      user:
          _appUser(firebaseUser.uid, completedOnboarding: completedOnboarding),
      isNewUser: false,
    );
  }

  @override
  Future<AppUser> fetchByUid(String uid) async {
    fetchedUids.add(uid);
    if (fetchPending != null) return fetchPending!.future;
    return _appUser(uid, completedOnboarding: completedOnboarding);
  }

  @override
  Future<void> recordTermsAcceptance(String uid) async {
    if (recordPending != null) await recordPending!.future;
    if (failRecording) throw StateError('Firestore unavailable');
    acceptedUids.add(uid);
    existingAcceptances.add(uid);
  }

  @override
  Future<bool> hasAcceptedCurrentTerms(String uid) async {
    if (failReading) throw StateError('Firestore unavailable');
    return existingAcceptances.contains(uid);
  }
}

AppUser _appUser(String uid, {bool completedOnboarding = true}) => AppUser(
      uid: uid,
      email: null,
      displayName: 'Demo',
      photoUrl: null,
      onboardingCompleted: completedOnboarding,
      profileCompleted: true,
      profileCompletionPercent: 100,
      isBot: false,
    );

// Estos servicios no participan en el acceso ni en la aceptación del EULA.
// Una llamada accidental falla para evitar dependencia de Firebase o la red.
class _UnusedOnboarding extends _UnexpectedCalls
    implements OnboardingRepository {}

class _UnusedVoice extends _UnexpectedCalls implements VoiceProfileService {}

class _UnusedSettings extends _UnexpectedCalls implements SettingsRepository {}

class _UnusedEntitlements extends _UnexpectedCalls
    implements EntitlementService {}

class _UnusedFlags extends _UnexpectedCalls implements FeatureFlagService {}

class _UnusedMatches extends _UnexpectedCalls implements MatchService {}

class _UnusedChat extends _UnexpectedCalls implements ChatService {}

class _UnusedProfiles extends _UnexpectedCalls
    implements ProfileSummaryRepository {}

class _UnusedRanking extends _UnexpectedCalls
    implements RankingSignalsRepository {}

class _UnusedStories extends _UnexpectedCalls implements StoryService {}

class _UnusedAi extends _UnexpectedCalls implements AiVisualService {}

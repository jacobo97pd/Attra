import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attra/src/features/auth/data/user_document_defaults.dart';
import 'package:attra/src/features/auth/domain/app_user.dart';
import 'package:attra/src/features/onboarding/data/onboarding_error_messages.dart';
import 'package:attra/src/features/onboarding/data/onboarding_repository.dart';
import 'package:attra/src/features/onboarding/data/onboarding_user_store.dart';
import 'package:attra/src/features/onboarding/domain/onboarding_draft.dart';

void main() {
  group('OnboardingRepository', () {
    test('usuario autenticado construye la ruta users/{uid}', () async {
      final FakeOnboardingUserStore store = FakeOnboardingUserStore();
      final OnboardingRepository repository =
          OnboardingRepository.withStore(userStore: store);
      const AppUser user = AppUser(
        uid: 'user-123',
        email: 'ada@example.test',
        displayName: 'Ada',
        photoUrl: null,
        onboardingCompleted: false,
        profileCompleted: false,
        profileCompletionPercent: 0,
        isBot: false,
      );

      await repository.saveDraftForUser(
        user,
        const OnboardingDraft(visibleName: ' Ada '),
      );

      expect(store.writes, hasLength(1));
      expect(store.writes.single.uid, 'user-123');
      expect(store.writes.single.path, 'users/user-123');
      expect(store.writes.single.merge, isTrue);
      expect(store.writes.single.data['uid'], 'user-123');
      expect(store.writes.single.data['empresa'], UserDocumentDefaults.empresa);
      expect(store.writes.single.data['onboardingDraft'], isA<Map>());
    });

    test('usuario null no intenta escribir y devuelve error controlado',
        () async {
      final FakeOnboardingUserStore store = FakeOnboardingUserStore();
      final OnboardingRepository repository =
          OnboardingRepository.withStore(userStore: store);

      await expectLater(
        repository.saveDraftForUser(null, const OnboardingDraft()),
        throwsA(
          isA<OnboardingRepositoryException>().having(
            (OnboardingRepositoryException error) => error.message,
            'message',
            contains('No hay sesion activa'),
          ),
        ),
      );
      expect(store.writes, isEmpty);
    });

    test('permission-denied se propaga y produce mensaje claro', () async {
      final FirebaseException permissionDenied = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
      final FakeOnboardingUserStore store =
          FakeOnboardingUserStore(errorOnSet: permissionDenied);
      final OnboardingRepository repository =
          OnboardingRepository.withStore(userStore: store);

      await expectLater(
        repository.saveDraft('user-123', const OnboardingDraft()),
        throwsA(
          isA<FirebaseException>().having(
            (FirebaseException error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect(store.writes, isEmpty);
      expect(
        onboardingSaveErrorMessage(permissionDenied),
        'No se pudo guardar onboarding (code: permission-denied). '
        'Detalle: Missing or insufficient permissions.',
      );
    });

    test('entorno Firebase incorrecto o no inicializado tiene error claro', () {
      expect(
        onboardingSaveErrorMessage(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
          ),
        ),
        contains('Firestore no esta configurado'),
      );
      expect(
        onboardingSaveErrorMessage(
          FirebaseException(
            plugin: 'firebase_core',
            code: 'no-app',
          ),
        ),
        contains('Firebase no esta inicializado'),
      );
    });

    test('onboarding ya guardado se lee desde onboardingDraft', () async {
      final FakeOnboardingUserStore store = FakeOnboardingUserStore(
        documents: <String, Map<String, dynamic>>{
          'user-123': <String, dynamic>{
            'uid': 'user-123',
            'empresa': UserDocumentDefaults.empresa,
            'onboardingDraft': <String, dynamic>{
              'visibleName': ' Ada ',
              'preferredLanguages': <String>['es'],
            },
          },
        },
      );
      final OnboardingRepository repository =
          OnboardingRepository.withStore(userStore: store);

      final OnboardingDraft? draft = await repository.loadDraft('user-123');

      expect(draft, isNotNull);
      expect(draft!.visibleName, 'Ada');
      expect(draft.preferredLanguages, <String>['es']);
    });

    test('datos minimos de onboarding producen payload compatible', () async {
      final FakeOnboardingUserStore store = FakeOnboardingUserStore();
      final OnboardingRepository repository =
          OnboardingRepository.withStore(userStore: store);

      await repository.submitOnboarding(
        uid: 'user-123',
        draft: _minimalCompletedDraft(),
      );

      expect(store.writes, hasLength(2));
      final StoreWrite mainWrite = store.writes.first;
      expect(mainWrite.path, 'users/user-123');
      expect(mainWrite.data['uid'], 'user-123');
      expect(mainWrite.data['empresa'], UserDocumentDefaults.empresa);
      expect(mainWrite.data['onboardingCompleted'], isTrue);
      expect(mainWrite.data['profileCompleted'], isTrue);
      expect(
        mainWrite.data.keys.toSet().difference(_allowedUserTopLevelKeys),
        isEmpty,
      );

      final StoreWrite completionWrite = store.writes.last;
      expect(completionWrite.data['profileCompletionPercent'], isA<int>());
      expect(completionWrite.data['pendingProfileTasks'], isA<List>());
      expect(
        completionWrite.data.keys.toSet().difference(_allowedUserTopLevelKeys),
        isEmpty,
      );
    });

    test('payload de draft contiene solo claves top-level admitidas', () async {
      final FakeOnboardingUserStore store = FakeOnboardingUserStore();
      final OnboardingRepository repository =
          OnboardingRepository.withStore(userStore: store);

      await repository.saveDraft('user-123', const OnboardingDraft());

      expect(store.writes, hasLength(1));
      expect(
        store.writes.single.data.keys
            .toSet()
            .difference(_allowedUserTopLevelKeys),
        isEmpty,
      );
      expect(store.writes.single.data['onboardingDraft'], isA<Map>());
      expect(store.writes.single.data['onboardingDraftUpdatedAt'],
          isA<FieldValue>());
    });
  });
}

OnboardingDraft _minimalCompletedDraft() {
  return OnboardingDraft(
    visibleName: 'Ada',
    birthDate: DateTime.utc(1992, 1, 2),
    gender: 'female',
    birthCity: 'Madrid',
    currentCity: 'Madrid',
    languages: const <String>['es'],
    liveSelfiePublicPhotoUrl: 'https://example.test/public.jpg',
    liveSelfiePublicStoragePath: 'users/user-123/public/profile/selfie.jpg',
    liveSelfiePrivatePhotoUrl: 'https://example.test/private.jpg',
    liveSelfiePrivateStoragePath:
        'users/user-123/private/live_selfie/selfie.jpg',
  );
}

const Set<String> _allowedUserTopLevelKeys = <String>{
  'uid',
  'empresa',
  'email',
  'displayName',
  'photoUrl',
  'profilePhotoUrl',
  'createdAt',
  'lastLoginAt',
  'onboardingCompleted',
  'profileCompleted',
  'authProvider',
  'onboardingCompletedAt',
  'updatedAt',
  'profile',
  'appearance',
  'lifestyle',
  'style',
  'preferences',
  'location',
  'photos',
  'profileCompletionPercent',
  'profileCompletionChecklist',
  'pendingProfileTasks',
  'profileCompletionRewardsClaimed',
  'availableProfileRewards',
  'isBot',
  'botProfileVersion',
  'botScenario',
  'seedQualityScore',
  'verification',
  'aiData',
  'onboardingDraft',
  'onboardingDraftUpdatedAt',
};

class FakeOnboardingUserStore implements OnboardingUserStore {
  FakeOnboardingUserStore({
    Map<String, Map<String, dynamic>>? documents,
    this.errorOnSet,
  }) : documents = documents == null
            ? <String, Map<String, dynamic>>{}
            : documents.map(
                (String uid, Map<String, dynamic> data) =>
                    MapEntry<String, Map<String, dynamic>>(
                  uid,
                  Map<String, dynamic>.from(data),
                ),
              );

  final Map<String, Map<String, dynamic>> documents;
  final Object? errorOnSet;
  final List<StoreWrite> writes = <StoreWrite>[];

  @override
  String userPath(String uid) => 'users/$uid';

  @override
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final Map<String, dynamic>? data = documents[uid];
    if (data == null) {
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<void> setUserData(
    String uid,
    Map<String, dynamic> data, {
    required bool merge,
  }) async {
    final Object? error = errorOnSet;
    if (error != null) {
      throw error;
    }
    final Map<String, dynamic> copied = Map<String, dynamic>.from(data);
    writes.add(
      StoreWrite(
        uid: uid,
        path: userPath(uid),
        data: copied,
        merge: merge,
      ),
    );
    if (merge) {
      documents[uid] = <String, dynamic>{
        ...?documents[uid],
        ...copied,
      };
    } else {
      documents[uid] = copied;
    }
  }
}

class StoreWrite {
  const StoreWrite({
    required this.uid,
    required this.path,
    required this.data,
    required this.merge,
  });

  final String uid;
  final String path;
  final Map<String, dynamic> data;
  final bool merge;
}

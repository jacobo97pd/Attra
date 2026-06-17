import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../profile/data/discovery_publisher.dart';
import '../../profile/domain/intro_media.dart';
import '../../profile/domain/profile_completion.dart';
import '../../profile/domain/profile_prompt.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_trait.dart';
import '../../profile/domain/public_identity.dart';
import '../domain/app_user.dart';
import 'user_document_defaults.dart';

class UserSyncResult {
  const UserSyncResult({required this.user, required this.isNewUser});

  final AppUser user;
  final bool isNewUser;

  bool get needsOnboarding =>
      !user.onboardingCompleted || !user.profileCompleted;
}

class UserRepository {
  UserRepository({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  })  : _firestore = firestore,
        _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _seedProfilesCollection =>
      _firestore.collection('seed_profiles');

  CollectionReference<Map<String, dynamic>> get _discoveryCollection =>
      _firestore.collection('discovery');

  Future<UserSyncResult> syncUserFromAuth(User firebaseUser) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(firebaseUser.uid);
    if (kDebugMode) {
      debugPrint(
        '[Attra][UserSync] firestoreApp=${_firestore.app.name} '
        'databaseId=${_firestore.databaseId} path=${userDoc.path} '
        'authUid=${firebaseUser.uid}',
      );
    }
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();

    if (!snapshot.exists) {
      final String authProvider = _resolveAuthProvider(firebaseUser);
      final Map<String, dynamic> baseData = <String, dynamic>{
        ...UserDocumentDefaults.requiredFields(firebaseUser.uid),
        'email': firebaseUser.email,
        'displayName': firebaseUser.displayName,
        'photoUrl': firebaseUser.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'onboardingCompleted': false,
        'profileCompleted': false,
        'authProvider': authProvider,
        'isBot': false,
        'botProfileVersion': 0,
        'botScenario': '',
        'seedQualityScore': 0,
        'photos': <Map<String, dynamic>>[],
        'profileCompletionPercent': 0,
        'profileCompletionChecklist': <String>[],
        'pendingProfileTasks': <String>[],
        'profileCompletionRewardsClaimed': <String>[],
        'availableProfileRewards': <String>[],
      };
      await userDoc.set(baseData);

      final DocumentSnapshot<Map<String, dynamic>> createdDoc =
          await userDoc.get();
      return UserSyncResult(
        user: AppUser.fromDocument(createdDoc),
        isNewUser: true,
      );
    }

    final Map<String, dynamic> currentData = snapshot.data()!;
    final Map<String, dynamic> updateData = <String, dynamic>{
      'lastLoginAt': FieldValue.serverTimestamp(),
    };
    if (currentData['uid'] == null || currentData['uid'].toString().isEmpty) {
      updateData['uid'] = firebaseUser.uid;
    }
    if (!_isRequiredString(currentData['empresa'])) {
      updateData['empresa'] = UserDocumentDefaults.empresa;
    }
    if (!_isTimestampValue(currentData['createdAt'])) {
      updateData['createdAt'] = FieldValue.serverTimestamp();
    }
    if (currentData['authProvider'] == null ||
        currentData['authProvider'].toString().isEmpty) {
      updateData['authProvider'] = _resolveAuthProvider(firebaseUser);
    }
    if (currentData['onboardingCompleted'] is! bool) {
      updateData['onboardingCompleted'] = false;
    }
    if (currentData['profileCompleted'] is! bool) {
      updateData['profileCompleted'] = false;
    }

    // El email SI se sincroniza desde el proveedor (auth es la fuente de
    // verdad del email). El nombre y la foto, NO: los elige el usuario en el
    // onboarding (profile.visibleName / profilePhotoUrl). Sincronizarlos desde
    // Google los sobreescribia en cada login.
    _setFieldIfChanged(
      updateData,
      currentData,
      key: 'email',
      newValue: firebaseUser.email,
    );

    // Auto-reparacion: el displayName y photoUrl de primer nivel deben reflejar
    // el nombre/foto ELEGIDOS por el usuario, no los de Google. El resolver cae
    // a displayName actual si el perfil no tiene nombre (=> no-op seguro).
    final String publicName = resolvePublicDisplayName(currentData);
    if (publicName.isNotEmpty && currentData['displayName'] != publicName) {
      updateData['displayName'] = publicName;
    }
    final String profilePhotoUrl =
        (currentData['profilePhotoUrl'] as String?)?.trim() ?? '';
    if (profilePhotoUrl.isNotEmpty &&
        currentData['photoUrl'] != profilePhotoUrl) {
      updateData['photoUrl'] = profilePhotoUrl;
    }

    _setDefaultIfMissing(updateData, currentData, 'isBot', false);
    _setDefaultIfMissing(updateData, currentData, 'botProfileVersion', 0);
    _setDefaultIfMissing(updateData, currentData, 'botScenario', '');
    _setDefaultIfMissing(updateData, currentData, 'seedQualityScore', 0);
    _setDefaultIfMissing(
      updateData,
      currentData,
      'photos',
      <Map<String, dynamic>>[],
    );
    _setDefaultIfMissing(
        updateData, currentData, 'profileCompletionPercent', 0);
    _setDefaultIfMissing(
      updateData,
      currentData,
      'profileCompletionChecklist',
      <String>[],
    );
    _setDefaultIfMissing(
      updateData,
      currentData,
      'pendingProfileTasks',
      <String>[],
    );
    _setDefaultIfMissing(
      updateData,
      currentData,
      'profileCompletionRewardsClaimed',
      <String>[],
    );
    _setDefaultIfMissing(
      updateData,
      currentData,
      'availableProfileRewards',
      <String>[],
    );
    await userDoc.set(
      _withRequiredUserFields(firebaseUser.uid, updateData),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(firebaseUser.uid);

    final DocumentSnapshot<Map<String, dynamic>> updatedDoc =
        await userDoc.get();
    return UserSyncResult(
      user: AppUser.fromDocument(updatedDoc),
      isNewUser: false,
    );
  }

  Future<AppUser> fetchByUid(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _usersCollection.doc(uid).get();
    if (!snapshot.exists) {
      throw StateError('No existe documento de usuario para uid: $uid');
    }
    return AppUser.fromDocument(snapshot);
  }

  /// Prompts de perfil del usuario (preguntas + respuestas).
  Future<List<ProfilePrompt>> fetchProfilePrompts(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _usersCollection.doc(uid).get();
    final List<dynamic> raw =
        (snap.data()?['profilePrompts'] as List<dynamic>?) ?? <dynamic>[];
    final List<ProfilePrompt> prompts = raw
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => ProfilePrompt.fromMap(
            e.map((dynamic k, dynamic v) => MapEntry(k.toString(), v))))
        .toList(growable: true)
      ..sort((ProfilePrompt a, ProfilePrompt b) => a.order.compareTo(b.order));
    return prompts;
  }

  /// Guarda los prompts completos (reemplaza la lista). Además espeja las
  /// respuestas activas en `profile.prompts` (strings) para mantener el cálculo
  /// de completitud legacy, y re-sincroniza discovery (perfil público).
  Future<void> saveProfilePrompts({
    required String uid,
    required List<ProfilePrompt> prompts,
  }) async {
    final List<Map<String, dynamic>> payload = prompts
        .asMap()
        .entries
        .map((MapEntry<int, ProfilePrompt> e) =>
            e.value.copyWith(order: e.key).toMap())
        .toList(growable: false);
    final List<String> legacyMirror = prompts
        .where((ProfilePrompt p) => p.isActive)
        .map((ProfilePrompt p) => '${p.question} ${p.answer}')
        .toList(growable: false);

    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _usersCollection.doc(uid).get();
    final Map<String, dynamic> profile =
        _asStringMap(snap.data()?['profile']);

    await _usersCollection.doc(uid).set(
      _withRequiredUserFields(uid, <String, dynamic>{
        'profilePrompts': payload,
        'profile': <String, dynamic>{...profile, 'prompts': legacyMirror},
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
  }

  /// Concede/retira el consentimiento de IA visual (dato biométrico, RGPD).
  Future<void> setAiVisualConsent({
    required String uid,
    required bool granted,
  }) async {
    await _usersCollection.doc(uid).set(
      _withRequiredUserFields(uid, <String, dynamic>{
        'aiVisualConsent': granted,
        'aiVisualConsentVersion': granted ? 1 : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );
  }

  /// Datos crudos del documento de usuario (para editar rasgos/visibilidad).
  Future<Map<String, dynamic>> fetchUserData(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await _usersCollection.doc(uid).get();
    return snap.data() ?? <String, dynamic>{};
  }

  Future<void> completeOnboarding(String uid) async {
    await _usersCollection.doc(uid).set(
          _withRequiredUserFields(
            uid,
            <String, dynamic>{
              'onboardingCompleted': true,
              'profileCompleted': true,
            },
          ),
          SetOptions(merge: true),
        );
    await refreshProfileCompletion(uid);
  }

  Future<void> refreshProfileCompletion(String uid) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final ProfileCompletionResult result =
        ProfileCompletionCalculator.calculate(data);

    await userDoc.set(
      _withRequiredUserFields(
        uid,
        <String, dynamic>{
          'profileCompletionPercent': result.percent,
          'profileCompletionChecklist': result.pendingTaskLabels,
          'pendingProfileTasks': result.pendingTaskIds,
          'availableProfileRewards': result.availableRewards,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
      SetOptions(merge: true),
    );

    // Publica/actualiza el perfil publico para el feed de descubrimiento.
    await _syncDiscoveryProfile(uid, data);
  }

  /// Espeja los campos PUBLICOS del usuario en `discovery/{uid}` (colección
  /// legible por todos) para que aparezca en el feed de otros. Si el usuario no
  /// es descubrible (onboarding incompleto o bot), borra su doc. Best-effort:
  /// nunca rompe el login si las reglas aun no permiten escribir.
  Future<void> _syncDiscoveryProfile(
      String uid, Map<String, dynamic> data) async {
    try {
      final bool discoverable = data['onboardingCompleted'] == true &&
          data['profileCompleted'] == true &&
          data['isBot'] != true;
      final DocumentReference<Map<String, dynamic>> ref =
          _discoveryCollection.doc(uid);
      if (!discoverable) {
        await ref.delete();
        return;
      }
      // El payload público (respetando visibilidad/consentimiento por campo) se
      // construye en DiscoveryPublisher: nunca email/nombre legal/tokens/selfie/
      // lat-lng, y los rasgos sensibles solo si visibleInProfile=true.
      final Map<String, dynamic> payload =
          DiscoveryPublisher.buildPayload(uid, data);
      // `set` sin merge: reconstruye el doc para que ocultar/borrar un campo lo
      // elimine de discovery (no quedan restos de un valor revocado).
      await ref.set(<String, dynamic>{
        ...payload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Attra][Discovery] sync fallo (se ignora): $error');
      }
    }
  }

  /// Perfiles reales publicados en `discovery`, excluyendo al propio usuario.
  Future<List<SeedProfile>> fetchDiscoveryProfiles({
    required String excludeUid,
    int limit = 50,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _discoveryCollection.limit(limit).get();
    return snapshot.docs
        .where((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            d.id != excludeUid)
        .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            SeedProfile.fromMap(d.id, d.data()))
        .toList(growable: false);
  }

  /// Escribe (o borra si vacío/null) un rasgo de perfil en
  /// `users/{uid}.[group].[field]`. Nunca infiere ni autorrellena: solo guarda
  /// lo que el usuario introduce. Tras escribir re-sincroniza discovery.
  Future<void> setProfileTrait({
    required String uid,
    required ProfileTraitDefinition def,
    required Object? value,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        _usersCollection.doc(uid);
    final bool empty = value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is List && value.isEmpty);
    if (empty) {
      // Borrar el campo lo elimina de users (y luego de discovery al re-sync).
      await ref.update(<String, Object?>{
        '${def.group}.${def.field}': FieldValue.delete(),
      });
    } else {
      await ref.set(
        _withRequiredUserFields(uid, <String, dynamic>{
          def.group: <String, dynamic>{def.field: value},
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        SetOptions(merge: true),
      );
    }
    await refreshProfileCompletion(uid);
  }

  /// Actualiza el consentimiento por campo en
  /// `users/{uid}.profileVisibility.fields.{traitKey}`. Re-sincroniza discovery
  /// (ocultar un campo lo retira de discovery).
  Future<void> setTraitVisibility({
    required String uid,
    required String traitKey,
    required bool visibleInProfile,
    required bool useForMatching,
    required bool useForFilters,
  }) async {
    await _usersCollection.doc(uid).set(
      _withRequiredUserFields(uid, <String, dynamic>{
        'profileVisibility': <String, dynamic>{
          'fields': <String, dynamic>{
            traitKey: <String, dynamic>{
              'visibleInProfile': visibleInProfile,
              'useForMatching': useForMatching,
              'useForFilters': useForFilters,
            },
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
  }

  Future<ProfileCompletionState> fetchProfileCompletionState(String uid) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _usersCollection.doc(uid).get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final ProfileCompletionResult result =
        ProfileCompletionCalculator.calculate(data);
    final List<dynamic> rawPhotos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> rawPrompts =
        (_asStringMap(data['profile'])['prompts'] as List<dynamic>?) ??
            <dynamic>[];
    final Map<String, dynamic> location = _asStringMap(data['location']);
    final List<dynamic> claimedRewards =
        (data['profileCompletionRewardsClaimed'] as List<dynamic>?) ??
            <dynamic>[];

    return ProfileCompletionState(
      percent: result.percent,
      pendingTasks: result.pendingTaskLabels,
      availableRewards: result.availableRewards,
      claimedRewards:
          claimedRewards.whereType<String>().toList(growable: false),
      additionalPhotos: rawPhotos
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) => AdditionalPhoto.fromMap(
                e.map((dynamic key, dynamic value) =>
                    MapEntry(key.toString(), value)),
              ))
          .toList(growable: false)
        ..sort((AdditionalPhoto a, AdditionalPhoto b) =>
            a.order.compareTo(b.order)),
      prompts: rawPrompts.whereType<String>().toList(growable: false),
      locationPermissionStatus:
          (location['permissionStatus'] as String?) ?? 'unknown',
      locationGranted: (location['permissionGranted'] as bool?) ?? false,
    );
  }

  Future<AdditionalPhoto> uploadAdditionalPhoto({
    required String uid,
    required Uint8List bytes,
    required String fileExtension,
    required String source,
  }) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final List<dynamic> rawPhotos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    final List<AdditionalPhoto> currentPhotos = rawPhotos
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => AdditionalPhoto.fromMap(
              e.map((dynamic key, dynamic value) =>
                  MapEntry(key.toString(), value)),
            ))
        .toList(growable: true)
      ..sort(
          (AdditionalPhoto a, AdditionalPhoto b) => a.order.compareTo(b.order));

    if (currentPhotos.length >= 5) {
      throw StateError('Solo puedes subir hasta 5 fotos adicionales.');
    }

    final String normalizedExt =
        fileExtension.toLowerCase().replaceAll('.', '').trim();
    final String extension = normalizedExt.isEmpty ? 'jpg' : normalizedExt;
    final String fileName =
        '${DateTime.now().millisecondsSinceEpoch}.$extension';
    final Reference photoRef =
        _storage.ref().child('users/$uid/public/additional/$fileName');
    final String contentType = _contentTypeFor(extension);

    await photoRef.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: <String, String>{
          'assetType': 'additional_photo',
          'assetVisibility': 'public',
          'uploadedBy': uid,
          'source': source,
        },
      ),
    );

    final String downloadUrl = await photoRef.getDownloadURL();
    final AdditionalPhoto newPhoto = AdditionalPhoto(
      url: downloadUrl,
      storagePath: photoRef.fullPath,
      source: source,
      order: currentPhotos.length,
      createdAtIso: DateTime.now().toIso8601String(),
    );
    currentPhotos.add(newPhoto);

    await userDoc.set(
      _withRequiredUserFields(
        uid,
        <String, dynamic>{
          'photos': currentPhotos
              .asMap()
              .entries
              .map((MapEntry<int, AdditionalPhoto> e) =>
                  e.value.copyWith(order: e.key).toMap())
              .toList(growable: false),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
      SetOptions(merge: true),
    );

    await refreshProfileCompletion(uid);
    return newPhoto;
  }

  Future<void> deleteAdditionalPhoto({
    required String uid,
    required String storagePath,
  }) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final List<dynamic> rawPhotos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    final List<AdditionalPhoto> currentPhotos = rawPhotos
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => AdditionalPhoto.fromMap(
              e.map((dynamic key, dynamic value) =>
                  MapEntry(key.toString(), value)),
            ))
        .toList(growable: true);

    final List<AdditionalPhoto> remaining = currentPhotos
        .where((AdditionalPhoto photo) => photo.storagePath != storagePath)
        .toList(growable: true);

    if (remaining.length == currentPhotos.length) {
      return;
    }

    try {
      await _storage.ref().child(storagePath).delete();
    } catch (_) {
      // If the file doesn't exist, continue cleaning Firestore state.
    }

    await userDoc.set(
      _withRequiredUserFields(
        uid,
        <String, dynamic>{
          'photos': remaining
              .asMap()
              .entries
              .map((MapEntry<int, AdditionalPhoto> e) =>
                  e.value.copyWith(order: e.key).toMap())
              .toList(growable: false),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
  }

  Future<void> reorderAdditionalPhotos({
    required String uid,
    required List<String> orderedStoragePaths,
  }) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final List<dynamic> rawPhotos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, AdditionalPhoto> photoByPath = rawPhotos
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => AdditionalPhoto.fromMap(
              e.map((dynamic key, dynamic value) =>
                  MapEntry(key.toString(), value)),
            ))
        .where((AdditionalPhoto p) => p.storagePath.isNotEmpty)
        .fold<Map<String, AdditionalPhoto>>(
      <String, AdditionalPhoto>{},
      (Map<String, AdditionalPhoto> map, AdditionalPhoto item) {
        map[item.storagePath] = item;
        return map;
      },
    );

    final List<AdditionalPhoto> reordered = <AdditionalPhoto>[];
    for (final String path in orderedStoragePaths) {
      final AdditionalPhoto? photo = photoByPath.remove(path);
      if (photo != null) {
        reordered.add(photo);
      }
    }
    reordered.addAll(photoByPath.values);

    await userDoc.set(
      _withRequiredUserFields(
        uid,
        <String, dynamic>{
          'photos': reordered
              .asMap()
              .entries
              .map((MapEntry<int, AdditionalPhoto> e) =>
                  e.value.copyWith(order: e.key).toMap())
              .toList(growable: false),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
      SetOptions(merge: true),
    );
  }

  // ── Media de presentación: audio (voice prompt) + vídeo corto ────────────
  // Públicos (los ve cualquiera que vea el perfil). Anidados en
  // `profile.introAudio` / `profile.introVideo` (no tocan reglas de Firestore).

  /// Sube el audio de presentación y lo guarda en `profile.introAudio`.
  /// Reemplaza el anterior (borra su archivo) si existía.
  Future<IntroAudio> uploadIntroAudio({
    required String uid,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snap = await userDoc.get();
    final Map<String, dynamic> profile = _asStringMap(snap.data()?['profile']);

    // Borra el archivo anterior si lo hay (no dejar huérfanos en Storage).
    final IntroAudio? prev = IntroAudio.fromMap(profile['introAudio']);
    if (prev != null && prev.storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(prev.storagePath).delete();
      } catch (_) {/* si no existe, seguimos */}
    }

    final String ext = extension.replaceAll('.', '').trim();
    final String fileName =
        'audio_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'm4a' : ext}';
    final Reference ref =
        _storage.ref().child('users/$uid/public/intro/$fileName');
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType.isEmpty ? 'audio/mp4' : contentType,
        customMetadata: <String, String>{
          'assetType': 'intro_audio',
          'assetVisibility': 'public',
          'uploadedBy': uid,
        },
      ),
    );

    final IntroAudio audio = IntroAudio(
      url: await ref.getDownloadURL(),
      storagePath: ref.fullPath,
      durationMs: durationMs,
    );

    await userDoc.set(
      _withRequiredUserFields(uid, <String, dynamic>{
        'profile': <String, dynamic>{...profile, 'introAudio': audio.toMap()},
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
    return audio;
  }

  /// Elimina el audio de presentación (archivo + campo).
  Future<void> deleteIntroAudio({required String uid}) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snap = await userDoc.get();
    final Map<String, dynamic> profile = _asStringMap(snap.data()?['profile']);
    final IntroAudio? prev = IntroAudio.fromMap(profile['introAudio']);
    if (prev != null && prev.storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(prev.storagePath).delete();
      } catch (_) {/* si no existe, seguimos */}
    }
    await userDoc.set(
      _withRequiredUserFields(uid, <String, dynamic>{
        'profile': <String, dynamic>{
          ...profile,
          'introAudio': FieldValue.delete(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
  }

  /// Sube el vídeo de presentación (ya comprimido por el cliente) y lo guarda
  /// en `profile.introVideo`. Reemplaza el anterior si existía.
  Future<IntroVideo> uploadIntroVideo({
    required String uid,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    required int durationMs,
  }) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snap = await userDoc.get();
    final Map<String, dynamic> profile = _asStringMap(snap.data()?['profile']);

    final IntroVideo? prev = IntroVideo.fromMap(profile['introVideo']);
    if (prev != null && prev.storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(prev.storagePath).delete();
      } catch (_) {/* si no existe, seguimos */}
    }

    final String ext = extension.replaceAll('.', '').trim();
    final String fileName =
        'video_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'mp4' : ext}';
    final Reference ref =
        _storage.ref().child('users/$uid/public/intro/$fileName');
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: contentType.isEmpty ? 'video/mp4' : contentType,
        customMetadata: <String, String>{
          'assetType': 'intro_video',
          'assetVisibility': 'public',
          'uploadedBy': uid,
        },
      ),
    );

    final IntroVideo video = IntroVideo(
      url: await ref.getDownloadURL(),
      storagePath: ref.fullPath,
      durationMs: durationMs,
    );

    await userDoc.set(
      _withRequiredUserFields(uid, <String, dynamic>{
        'profile': <String, dynamic>{...profile, 'introVideo': video.toMap()},
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
    return video;
  }

  /// Elimina el vídeo de presentación (archivo + campo).
  Future<void> deleteIntroVideo({required String uid}) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snap = await userDoc.get();
    final Map<String, dynamic> profile = _asStringMap(snap.data()?['profile']);
    final IntroVideo? prev = IntroVideo.fromMap(profile['introVideo']);
    if (prev != null && prev.storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(prev.storagePath).delete();
      } catch (_) {/* si no existe, seguimos */}
    }
    await userDoc.set(
      _withRequiredUserFields(uid, <String, dynamic>{
        'profile': <String, dynamic>{
          ...profile,
          'introVideo': FieldValue.delete(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
  }

  Future<void> addPrompt({
    required String uid,
    required String prompt,
  }) async {
    final String cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) {
      return;
    }

    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final Map<String, dynamic> profile = _asStringMap(data['profile']);
    final List<String> prompts =
        ((profile['prompts'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<String>()
            .toList(growable: true);

    if (!prompts.contains(cleanPrompt)) {
      prompts.add(cleanPrompt);
    }
    if (prompts.length > 5) {
      prompts.removeRange(0, prompts.length - 5);
    }

    await userDoc.set(
      _withRequiredUserFields(
        uid,
        <String, dynamic>{
          'profile': <String, dynamic>{
            ...profile,
            'prompts': prompts,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
      SetOptions(merge: true),
    );

    await refreshProfileCompletion(uid);
  }

  Future<void> claimProfileReward({
    required String uid,
    required String rewardId,
  }) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final ProfileCompletionResult result =
        ProfileCompletionCalculator.calculate(data);
    if (!result.availableRewards.contains(rewardId)) {
      return;
    }

    final List<String> claimed =
        ((data['profileCompletionRewardsClaimed'] as List<dynamic>?) ??
                <dynamic>[])
            .whereType<String>()
            .toList(growable: true);
    if (!claimed.contains(rewardId)) {
      claimed.add(rewardId);
    }

    await userDoc.set(
      _withRequiredUserFields(
        uid,
        <String, dynamic>{
          'profileCompletionRewardsClaimed': claimed,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
      SetOptions(merge: true),
    );
    await refreshProfileCompletion(uid);
  }

  Future<List<SeedProfile>> fetchSeedProfiles({int limit = 30}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _seedProfilesCollection
            .where('isBot', isEqualTo: true)
            .limit(limit)
            .get();
    return snapshot.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
            SeedProfile.fromMap(doc.id, doc.data()))
        .toList(growable: false);
  }

  /// Perfil completo de un usuario por uid para verlo (desde chats/matches):
  /// primero `discovery` (perfiles reales), luego `seed_profiles` (mocks).
  Future<SeedProfile?> fetchProfileByUid(String uid) async {
    if (uid.isEmpty) return null;
    final DocumentSnapshot<Map<String, dynamic>> disc =
        await _discoveryCollection.doc(uid).get();
    if (disc.exists) {
      return SeedProfile.fromMap(disc.id, disc.data()!);
    }
    final DocumentSnapshot<Map<String, dynamic>> seed =
        await _seedProfilesCollection.doc(uid).get();
    if (seed.exists) {
      return SeedProfile.fromMap(seed.id, seed.data()!);
    }
    return null;
  }

  Future<void> deleteUserData(String uid) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    if (!snapshot.exists) {
      return;
    }

    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final List<String> storagePaths = <String>[];

    final Map<String, dynamic> verification =
        _asStringMap(data['verification']);
    _collectPathIfPresent(
        storagePaths, verification['liveSelfiePublicStoragePath']);
    _collectPathIfPresent(
        storagePaths, verification['liveSelfiePrivateStoragePath']);

    final List<dynamic> photos =
        (data['photos'] as List<dynamic>?) ?? <dynamic>[];
    for (final dynamic photo in photos) {
      final Map<String, dynamic> mapped = _asStringMap(photo);
      _collectPathIfPresent(storagePaths, mapped['storagePath']);
    }

    for (final String path in storagePaths.toSet()) {
      try {
        await _storage.ref().child(path).delete();
      } catch (_) {
        // Ignore best-effort cleanup errors.
      }
    }

    await _deleteStorageFolderBestEffort('users/$uid/public/additional');
    await _deleteStorageFolderBestEffort('users/$uid/public/profile');
    await _deleteStorageFolderBestEffort('users/$uid/private/live_selfie');

    await userDoc.delete();
  }

  void _setFieldIfChanged(
    Map<String, dynamic> updateData,
    Map<String, dynamic> currentData, {
    required String key,
    required String? newValue,
  }) {
    if (newValue == null || newValue.isEmpty) {
      return;
    }

    if (currentData[key] != newValue) {
      updateData[key] = newValue;
    }
  }

  void _setDefaultIfMissing(
    Map<String, dynamic> updateData,
    Map<String, dynamic> currentData,
    String key,
    dynamic defaultValue,
  ) {
    if (!currentData.containsKey(key) || currentData[key] == null) {
      updateData[key] = defaultValue;
    }
  }

  Map<String, dynamic> _withRequiredUserFields(
    String uid,
    Map<String, dynamic> data,
  ) {
    return <String, dynamic>{
      ...UserDocumentDefaults.requiredFields(uid),
      ...data,
    };
  }

  String _resolveAuthProvider(User firebaseUser) {
    for (final UserInfo info in firebaseUser.providerData) {
      if (info.providerId == 'google.com') {
        return 'google';
      }
      if (info.providerId == 'phone') {
        return 'phone';
      }
    }
    return 'unknown';
  }

  String _contentTypeFor(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((dynamic key, dynamic val) {
        return MapEntry(key.toString(), val);
      });
    }
    return <String, dynamic>{};
  }

  bool _isTimestampValue(dynamic value) {
    return value is Timestamp;
  }

  bool _isRequiredString(dynamic value) {
    return value is String && value.trim().isNotEmpty;
  }

  void _collectPathIfPresent(List<String> target, dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      target.add(value.trim());
    }
  }

  Future<void> _deleteStorageFolderBestEffort(String folderPath) async {
    try {
      final ListResult listResult = await _storage.ref(folderPath).listAll();
      for (final Reference item in listResult.items) {
        try {
          await item.delete();
        } catch (_) {
          // Ignore best-effort cleanup errors.
        }
      }
    } catch (_) {
      // Ignore best-effort cleanup errors.
    }
  }
}

extension on AdditionalPhoto {
  AdditionalPhoto copyWith({
    String? url,
    String? storagePath,
    String? source,
    int? order,
    String? createdAtIso,
  }) {
    return AdditionalPhoto(
      url: url ?? this.url,
      storagePath: storagePath ?? this.storagePath,
      source: source ?? this.source,
      order: order ?? this.order,
      createdAtIso: createdAtIso ?? this.createdAtIso,
    );
  }
}

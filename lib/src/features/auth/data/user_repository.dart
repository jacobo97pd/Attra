import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../profile/domain/profile_completion.dart';
import '../../profile/domain/profile_state.dart';
import '../domain/app_user.dart';

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

  Future<UserSyncResult> syncUserFromAuth(User firebaseUser) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(firebaseUser.uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();

    if (!snapshot.exists) {
      final String authProvider = _resolveAuthProvider(firebaseUser);
      final Map<String, dynamic> baseData = <String, dynamic>{
        'uid': firebaseUser.uid,
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

    _setFieldIfChanged(
      updateData,
      currentData,
      key: 'displayName',
      newValue: firebaseUser.displayName,
    );
    _setFieldIfChanged(
      updateData,
      currentData,
      key: 'email',
      newValue: firebaseUser.email,
    );
    _setFieldIfChanged(
      updateData,
      currentData,
      key: 'photoUrl',
      newValue: firebaseUser.photoURL,
    );

    updateData.putIfAbsent('isBot', () => false);
    updateData.putIfAbsent('botProfileVersion', () => 0);
    updateData.putIfAbsent('botScenario', () => '');
    updateData.putIfAbsent('seedQualityScore', () => 0);
    updateData.putIfAbsent('photos', () => <Map<String, dynamic>>[]);
    updateData.putIfAbsent('profileCompletionPercent', () => 0);
    updateData.putIfAbsent('profileCompletionChecklist', () => <String>[]);
    updateData.putIfAbsent('pendingProfileTasks', () => <String>[]);
    updateData.putIfAbsent('profileCompletionRewardsClaimed', () => <String>[]);
    updateData.putIfAbsent('availableProfileRewards', () => <String>[]);

    await userDoc.set(updateData, SetOptions(merge: true));
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

  Future<void> completeOnboarding(String uid) async {
    await _usersCollection.doc(uid).update(<String, dynamic>{
      'onboardingCompleted': true,
      'profileCompleted': true,
    });
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
      <String, dynamic>{
        'profileCompletionPercent': result.percent,
        'profileCompletionChecklist': result.pendingTaskLabels,
        'pendingProfileTasks': result.pendingTaskIds,
        'availableProfileRewards': result.availableRewards,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
      <String, dynamic>{
        'photos': currentPhotos
            .asMap()
            .entries
            .map((MapEntry<int, AdditionalPhoto> e) =>
                e.value.copyWith(order: e.key).toMap())
            .toList(growable: false),
        'updatedAt': FieldValue.serverTimestamp(),
      },
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
      <String, dynamic>{
        'photos': remaining
            .asMap()
            .entries
            .map((MapEntry<int, AdditionalPhoto> e) =>
                e.value.copyWith(order: e.key).toMap())
            .toList(growable: false),
        'updatedAt': FieldValue.serverTimestamp(),
      },
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
      <String, dynamic>{
        'photos': reordered
            .asMap()
            .entries
            .map((MapEntry<int, AdditionalPhoto> e) =>
                e.value.copyWith(order: e.key).toMap())
            .toList(growable: false),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
      <String, dynamic>{
        'profile': <String, dynamic>{
          ...profile,
          'prompts': prompts,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
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
      <String, dynamic>{
        'profileCompletionRewardsClaimed': claimed,
        'updatedAt': FieldValue.serverTimestamp(),
      },
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

  Future<void> deleteUserData(String uid) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _usersCollection.doc(uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await userDoc.get();
    if (!snapshot.exists) {
      return;
    }

    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    final List<String> storagePaths = <String>[];

    final Map<String, dynamic> verification = _asStringMap(data['verification']);
    _collectPathIfPresent(storagePaths, verification['liveSelfiePublicStoragePath']);
    _collectPathIfPresent(storagePaths, verification['liveSelfiePrivateStoragePath']);

    final List<dynamic> photos = (data['photos'] as List<dynamic>?) ?? <dynamic>[];
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

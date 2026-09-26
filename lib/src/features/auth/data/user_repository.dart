import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/config/legal_links.dart';
import '../../geo/domain/travel_destination_resolver.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../../profile/domain/intro_media.dart';
import '../../profile/domain/profile_completion.dart';
import '../../profile/domain/profile_prompt.dart';
import '../../profile/domain/profile_state.dart';
import '../../profile/domain/profile_trait.dart';
import '../../profile/domain/public_identity.dart';
import '../domain/app_user.dart';
import 'user_document_defaults.dart';
import '../domain/resolved_place.dart';

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

  /// Guideline 1.2: deja constancia de que el usuario acepto el EULA en el
  /// login (donde la casilla es obligatoria).
  ///
  /// Se guarda en el consent ledger `users/{uid}/consentRecords`, NO en
  /// `users/{uid}`: las reglas limitan el documento de usuario a una lista
  /// cerrada de claves de primer nivel, asi que anadir campos nuevos ahi
  /// tumbaria TODA la escritura con permission-denied.
  ///
  /// Id determinista por version: el ledger es inmutable (`update` prohibido).
  /// La transacción evita que dos dispositivos intenten modificar el mismo
  /// consentimiento. El acceso espera la confirmación del servidor y permite
  /// reintentar si no se pudo guardar.
  Future<void> recordTermsAcceptance(String uid) async {
    if (uid.isEmpty) throw ArgumentError.value(uid, 'uid');
    final DocumentReference<Map<String, dynamic>> ref = _termsRecord(uid);
    await _firestore.runTransaction<void>((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(ref);
      if (snapshot.exists) {
        if (_isCurrentTermsAcceptance(snapshot.data())) return;
        throw StateError('El registro de aceptación existente no es válido.');
      }
      transaction.set(ref, <String, dynamic>{
        'purpose': 'terms_of_use',
        'granted': true,
        // Mismo vocabulario que LegalBasis del catalogo de ajustes.
        'legalBasis': 'contract',
        'settingKey': 'terms_of_use',
        'termsVersion': LegalLinks.termsVersion,
        'recordedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  DocumentReference<Map<String, dynamic>> _termsRecord(String uid) =>
      _usersCollection
          .doc(uid)
          .collection('consentRecords')
          .doc('terms_${LegalLinks.termsVersion}');

  Future<bool> hasAcceptedCurrentTerms(String uid) async {
    final Map<String, dynamic>? record = (await _termsRecord(uid).get()).data();
    return _isCurrentTermsAcceptance(record);
  }

  bool _isCurrentTermsAcceptance(Map<String, dynamic>? record) =>
      record?['granted'] == true &&
      record?['purpose'] == 'terms_of_use' &&
      record?['termsVersion'] == LegalLinks.termsVersion;

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
    final Map<String, dynamic> profile = _asStringMap(snap.data()?['profile']);

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

  /// Concede/retira el consentimiento para que la IA lea la conversación y
  /// proponga respuestas.
  ///
  /// Va SEPARADO del de la IA visual a propósito: son dos tratamientos
  /// distintos (una cara frente a los mensajes de dos personas) y quien acepta
  /// uno no tiene por qué aceptar el otro. Mezclarlos en un único interruptor
  /// convertiría un consentimiento en un cheque en blanco.
  Future<void> setChatSuggestionsConsent({
    required String uid,
    required bool granted,
  }) async {
    await _usersCollection.doc(uid).set(
          _withRequiredUserFields(uid, <String, dynamic>{
            'chatSuggestionsConsent': granted,
            'chatSuggestionsConsentVersion': granted ? 1 : 0,
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

    // `discovery/{uid}` lo publica SOLO el backend (trigger
    // onUserWrittenSyncDiscovery), que salta con la escritura de arriba. El
    // cliente ya no escribe su propia ficha: eran dos escritores con lógica
    // distinta y ganaba el último (una usuaria en modo Amigos volvía a salir
    // en feeds de citas si el `set` del cliente llegaba después del trigger).
  }

  /// Pide al backend que vuelva a publicar `discovery/{uid}`. Lo llama Ajustes
  /// al cambiar una opción de visibilidad/ubicación.
  ///
  /// La ficha pública la construye SOLO el trigger de backend (las reglas ya no
  /// dejan al cliente escribirla), y el trigger salta con cualquier escritura en
  /// `users/{uid}`: basta con tocar `updatedAt`. Normalmente el propio ajuste ya
  /// lo ha disparado; esto es la garantía de que se republica.
  Future<void> republishDiscovery(String uid) async {
    try {
      await _usersCollection.doc(uid).set(
            _withRequiredUserFields(uid, <String, dynamic>{
              'updatedAt': FieldValue.serverTimestamp(),
            }),
            SetOptions(merge: true),
          );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Attra][Discovery] republish fallo (se ignora): $error');
      }
    }
  }

  /// Tope por país de la consulta de discovery. Holgado para que el feed no
  /// se vacíe tras unos cuantos swipes, acotado para que cada carga no lea la
  /// colección entera.
  static const int discoveryCountryLimit = 200;

  /// Corte de la consulta SIN filtro, la de siempre. Se mantiene mientras haya
  /// fichas sin `countryIso2` (hasta que corra tool/backfill_country_iso2.py
  /// y todas pasen por el trigger): sin ella esas fichas no saldrían nunca.
  static const int discoveryLegacyLimit = 50;

  /// Perfiles reales publicados en `discovery`, excluyendo al propio usuario.
  ///
  /// El pool ERA `discovery.limit(50)` sin orden ni filtro: los 50 primeros por
  /// id de documento, los mismos para todo el mundo. Con más de 50 fichas,
  /// quien cayera detrás no salía en el feed de nadie (tampoco en el de quien
  /// viaja a su ciudad). Ahora se consulta por país ([countryIso2s]: el de
  /// casa, y el de destino si se viaja) con un tope por país, más el corte
  /// antiguo mientras queden fichas sin código. Deduplicado por uid.
  ///
  /// Cada documento se lee por separado: uno mal formado se salta y no se
  /// lleva por delante la carga entera.
  Future<List<SeedProfile>> fetchDiscoveryProfiles({
    required String excludeUid,
    Iterable<String> countryIso2s = const <String>[],
    int limit = discoveryLegacyLimit,
  }) async {
    final Set<String> codes = <String>{
      for (final String c in countryIso2s)
        if (c.trim().length == 2) c.trim().toUpperCase(),
    };
    final List<Future<QuerySnapshot<Map<String, dynamic>>>> queries =
        <Future<QuerySnapshot<Map<String, dynamic>>>>[
      for (final String code in codes)
        _discoveryCollection
            .where('countryIso2', isEqualTo: code)
            .limit(discoveryCountryLimit)
            .get(),
      _discoveryCollection.limit(limit).get(),
    ];
    // Una consulta que falla (índice aún no creado, red) no puede vaciar las
    // demás: se recogen las que vuelvan.
    final List<QuerySnapshot<Map<String, dynamic>>?> snapshots =
        await Future.wait(queries.map(
      (Future<QuerySnapshot<Map<String, dynamic>>> q) => q
          .then<QuerySnapshot<Map<String, dynamic>>?>(
              (QuerySnapshot<Map<String, dynamic>> s) => s,
              onError: (Object error) {
        debugPrint('[Attra][Discovery] consulta fallida: $error');
        return null;
      }),
    ));
    return mergeDiscoveryPages(
      <List<MapEntry<String, Map<String, dynamic>>>?>[
        for (final QuerySnapshot<Map<String, dynamic>>? snap in snapshots)
          snap?.docs
              .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                  MapEntry<String, Map<String, dynamic>>(d.id, d.data()))
              .toList(growable: false),
      ],
      excludeUid: excludeUid,
    );
  }

  /// Junta las páginas de las consultas de discovery (una por país y la
  /// antigua sin filtro): sin duplicados, sin el propio usuario y saltando la
  /// ficha que no se pueda leer. `null` = esa consulta falló; si fallan TODAS,
  /// lanza (quien llama se queda con los seeds, como antes).
  @visibleForTesting
  static List<SeedProfile> mergeDiscoveryPages(
    List<List<MapEntry<String, Map<String, dynamic>>>?> pages, {
    required String excludeUid,
  }) {
    if (pages.every(
        (List<MapEntry<String, Map<String, dynamic>>>? page) => page == null)) {
      throw StateError('discovery no disponible');
    }
    final Map<String, SeedProfile> byUid = <String, SeedProfile>{};
    for (final List<MapEntry<String, Map<String, dynamic>>>? page in pages) {
      if (page == null) continue;
      for (final MapEntry<String, Map<String, dynamic>> d in page) {
        if (d.key == excludeUid || byUid.containsKey(d.key)) continue;
        final SeedProfile? p = parseRealDiscoveryDoc(d.key, d.value);
        if (p != null) byUid[d.key] = p;
      }
    }
    return byUid.values.toList(growable: false);
  }

  /// Parsea UNA ficha de discovery/seed. null si está tan rota que ni el
  /// parser tolerante puede con ella: se salta esa ficha, no la carga entera.
  @visibleForTesting
  static SeedProfile? parseDiscoveryDoc(String id, Map<String, dynamic> data) {
    try {
      return SeedProfile.fromMap(id, data);
    } catch (error) {
      debugPrint('[Attra][Discovery] ficha $id ilegible, se salta: $error');
      return null;
    }
  }

  /// Como [parseDiscoveryDoc], pero para `discovery`, que SOLO publica personas
  /// reales (el backend escribe `isBot: false` y no publica cuentas bot). Se
  /// fuerza aquí por si una ficha antigua trae otra cosa: el respaldo de
  /// muestra del feed (`FeedFilter.sampleProfiles`) enseña semillas de
  /// cualquier país, y una persona real nunca puede entrar por esa puerta.
  @visibleForTesting
  static SeedProfile? parseRealDiscoveryDoc(
    String id,
    Map<String, dynamic> data,
  ) =>
      parseDiscoveryDoc(id, <String, dynamic>{...data, 'isBot': false});

  /// Perfiles de `discovery` por UID concreto, en lotes de 10 (límite de
  /// `whereIn`). Se usa para meter en el feed a gente que NO entró en el corte
  /// general: hoy, los que tienen un Boost pagado activo.
  Future<List<SeedProfile>> fetchDiscoveryProfilesByUids(
    List<String> uids, {
    required String excludeUid,
  }) async {
    final List<String> wanted =
        uids.where((String id) => id.isNotEmpty && id != excludeUid).toList();
    if (wanted.isEmpty) return const <SeedProfile>[];

    final List<SeedProfile> out = <SeedProfile>[];
    for (int i = 0; i < wanted.length; i += 10) {
      final List<String> chunk =
          wanted.sublist(i, i + 10 > wanted.length ? wanted.length : i + 10);
      try {
        final QuerySnapshot<Map<String, dynamic>> snap =
            await _discoveryCollection
                .where(FieldPath.documentId, whereIn: chunk)
                .get();
        // Ficha a ficha: una mal formada ya no tira las otras nueve del lote.
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
          final SeedProfile? p = parseRealDiscoveryDoc(d.id, d.data());
          if (p != null) out.add(p);
        }
      } catch (error) {
        // Un lote fallido no puede vaciar el feed.
        debugPrint('[Attra][Discovery] lote por uid fallo: $error');
      }
    }
    return out;
  }

  /// MODO VIAJES (Plus/Pro): fija (o desactiva) el destino en
  /// `users/{uid}.settings.travel`; el trigger de backend republica la ficha
  /// para que el perfil aparezca allí "de viaje". El gate de tier se valida en
  /// la capa superior (y el backend lo vuelve a exigir al publicar).
  /// Duración de un viaje. Sin caducidad, un usuario que cancelara su plan se
  /// quedaba "en Tokio" para siempre. El backend la respeta al publicar la
  /// ficha (functions/src/discovery.ts -> travelExpired) y en su barrido horario.
  static const Duration travelDuration = Duration(days: 30);

  /// [latitude]/[longitude] son el CENTRO de la ciudad de destino (nunca la
  /// ubicación real) y [geoSource] de dónde salió. Sin centro, el viaje se
  /// guarda igual y funciona a nivel de país.
  ///
  /// Al apagarlo se CONSERVAN país, ciudad e ISO2 (quien llama los manda): así
  /// la hoja reabre con el destino puesto y se reactiva de un toque. Antes se
  /// guardaba el ISO2 sin el nombre y la hoja enseñaba el país elegido con
  /// "Viajar aquí" desactivado. Todo lo que mira el viaje exige `active`.
  static Map<String, dynamic> buildTravelPatch({
    required bool active,
    String iso2 = '',
    String city = '',
    String country = '',
    double? latitude,
    double? longitude,
    TravelGeoSource geoSource = TravelGeoSource.none,
    DateTime? now,
  }) {
    final bool located =
        active && TravelDestination.isValid(latitude, longitude);
    final DateTime? until =
        active ? (now ?? DateTime.now()).toUtc().add(travelDuration) : null;
    return <String, dynamic>{
      'active': active,
      'iso2': iso2.trim().toUpperCase(),
      'city': city.trim(),
      'country': country.trim(),
      // 4 decimales (~11 m) bastan para el centro de una ciudad.
      'lat': located ? _round4(latitude!) : null,
      'lng': located ? _round4(longitude!) : null,
      // Para QUÉ destino se resolvió el centro. Las versiones anteriores
      // cambian ciudad o país sin tocar lat/lng: con esto el centro viejo deja
      // de valer en vez de publicarse como si fuera el del destino nuevo
      // (TravelRules.centerMatchesDestination / travelCenter del backend).
      'geoCity': located ? city.trim() : null,
      'geoIso2': located ? iso2.trim().toUpperCase() : null,
      'geoSource': located ? geoSource.wireName : TravelGeoSource.none.wireName,
      // `until` (ISO) lo siguen leyendo las versiones anteriores de la app;
      // `untilAt` (Timestamp) es el que usan el barrido y el backend.
      'until': until?.toIso8601String(),
      'untilAt': until == null ? null : Timestamp.fromDate(until),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static double _round4(double v) => (v * 10000).roundToDouble() / 10000;

  Future<void> setTravelLocation({
    required String uid,
    required bool active,
    String iso2 = '',
    String city = '',
    String country = '',
    double? latitude,
    double? longitude,
    TravelGeoSource geoSource = TravelGeoSource.none,
  }) async {
    // Vive bajo `settings.travel`: `settings` ya es escribible por el dueño, así
    // que NO requiere desplegar reglas (igual que el ajuste de Slow Dating).
    // La ficha pública la republica el trigger de backend con esta escritura.
    await _usersCollection.doc(uid).set(
          _withRequiredUserFields(uid, <String, dynamic>{
            'settings': <String, dynamic>{
              'travel': buildTravelPatch(
                active: active,
                iso2: iso2,
                city: city,
                country: country,
                latitude: latitude,
                longitude: longitude,
                geoSource: geoSource,
              ),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          }),
          SetOptions(merge: true),
        );
  }

  /// Añade el centro del destino a un viaje YA activo, sin tocar nada más
  /// (ni `active` ni la fecha de fin): es la auto-reparación de los viajes
  /// guardados antes de que existieran las coordenadas. El trigger republica
  /// entonces la ficha en el destino.
  ///
  /// [city]/[iso2] son el destino para el que se resolvió el centro y se
  /// guardan con él (`geoCity`/`geoIso2`). Si mientras tanto el viaje cambió
  /// (otro dispositivo, una versión antigua), este centro no casa con el
  /// destino nuevo y nadie lo usa, en vez de publicar el viaje en la ciudad
  /// vieja.
  Future<void> patchTravelGeo({
    required String uid,
    required double latitude,
    required double longitude,
    required TravelGeoSource source,
    required String city,
    required String iso2,
  }) async {
    if (!TravelDestination.isValid(latitude, longitude)) return;
    if (city.trim().isEmpty) return;
    await _usersCollection.doc(uid).set(
          _withRequiredUserFields(uid, <String, dynamic>{
            'settings': <String, dynamic>{
              'travel': <String, dynamic>{
                'lat': _round4(latitude),
                'lng': _round4(longitude),
                'geoCity': city.trim(),
                'geoIso2': iso2.trim().toUpperCase(),
                'geoSource': source.wireName,
              },
            },
          }),
          SetOptions(merge: true),
        );
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

  /// Persiste la ubicación del dispositivo en `users/{uid}.location` (lat/lng +
  /// estado del permiso). Así la completitud del perfil reconoce que hay
  /// ubicación y el feed calcula distancia.
  ///
  /// `location.updatedAt` es la MARCA DE FRESCURA y no es decorativa: es lo que
  /// permite saber si la ubicación es de hoy o de hace tres meses. Sin ella el
  /// cliente solo podía preguntarse "¿hay coordenadas?", y por eso la ubicación
  /// se quedaba congelada desde el registro. `location` ya está en
  /// `allowedTopLevelKeys()` de firestore.rules, así que esto no toca reglas.
  ///
  /// `location.fixedAt` es cuándo se MIDIÓ la posición, que no es lo mismo que
  /// cuándo se escribe: `updatedAt` es un `serverTimestamp()` y sin cobertura la
  /// escritura se confirma horas después (una posición del kilómetro 300 quedaba
  /// sellada como "medida ahora" al llegar a destino con WiFi, y la política la
  /// daba por fresquísima). La frescura se decide con `fixedAt`.
  ///
  /// `permissionGranted` se escribía SOLO en el onboarding: Ajustes leía
  /// `location.permissionGranted` y veía `false` aunque el permiso estuviera
  /// concedido desde el feed. Va como opcional porque "no se pudo determinar" NO
  /// es "denegado": escribir `unknown`/false por un fallo pasajero del canal
  /// nativo volvería a romper Ajustes.
  Future<void> setDeviceLocation({
    required String uid,
    required double latitude,
    required double longitude,
    required DateTime fixedAt,
    String? permissionStatus,
    bool? permissionGranted,
    ResolvedPlace? place,
  }) async {
    // Ciudad y pais viajan en la MISMA escritura que las coordenadas. Iban por
    // libre: los escribia solo el selector manual del onboarding, asi que al
    // hacer que las coordenadas se refrescaran solas quedaban desfasados. Y eso
    // es peor que tenerlo todo rancio: cruzas una frontera, tus coordenadas
    // dicen Lisboa y tu pais sigue diciendo España, la regla de pais te enseña
    // españoles y la de radio los descarta a todos. Ademas dejas de ser visible
    // para los de alrededor, porque el pais que publicas es de otro sitio.
    //
    // Si no se pudo resolver (sin red, geocodificador pasado de tasa) NO se
    // toca nada: se conserva el sitio anterior entero.
    final ({
      Map<String, dynamic> profile,
      Map<String, dynamic> location
    }) patch = buildDeviceLocationPatch(
      latitude: latitude,
      longitude: longitude,
      fixedAt: fixedAt,
      permissionStatus: permissionStatus,
      permissionGranted: permissionGranted,
      place: place,
    );
    await _usersCollection.doc(uid).set(
          _withRequiredUserFields(uid, <String, dynamic>{
            if (patch.profile.isNotEmpty) 'profile': patch.profile,
            'location': patch.location,
            'updatedAt': FieldValue.serverTimestamp(),
          }),
          SetOptions(merge: true),
        );
    // Republicar `discovery/{uid}` es imprescindible: guardar la ubicación nueva
    // en `users` sin republicar deja a los demás viéndote donde estabas, que es
    // exactamente el síntoma que se venía a arreglar. Lo hace el trigger de
    // backend `onUserWrittenSyncDiscovery` (Admin SDK), que se dispara con la
    // escritura de arriba.
    await refreshProfileCompletion(uid);
  }

  /// Lo que [setDeviceLocation] escribe (puro, para poder probarlo).
  ///
  /// - El ISO2 va a las DOS claves (`currentCountryIso2`, del geocodificador,
  ///   y `currentCountryCode`, del onboarding): si solo se actualizara una, al
  ///   cruzar una frontera quedaría un nombre nuevo con un código viejo según
  ///   quién leyera.
  /// - `location.placeLat/placeLng` apuntan dónde se resolvió el sitio. Sin
  ///   sitio no se tocan: que se queden atrás es lo que delata que el país
  ///   guardado es el de antes y hay que volver a preguntarlo.
  static ({Map<String, dynamic> profile, Map<String, dynamic> location})
      buildDeviceLocationPatch({
    required double latitude,
    required double longitude,
    required DateTime fixedAt,
    String? permissionStatus,
    bool? permissionGranted,
    ResolvedPlace? place,
  }) {
    final bool placeUsable = place != null && place.isUsable;
    final Map<String, dynamic> profilePlace = <String, dynamic>{
      if (place != null && place.isUsable) ...<String, dynamic>{
        if (place.city.isNotEmpty) 'currentCity': place.city,
        'currentCountryName': place.countryName,
        if (place.countryIso2.isNotEmpty) ...<String, dynamic>{
          'currentCountryIso2': place.countryIso2,
          'currentCountryCode': place.countryIso2,
        },
      },
    };
    return (
      profile: profilePlace,
      location: <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        if (permissionStatus != null) 'permissionStatus': permissionStatus,
        if (permissionGranted != null) 'permissionGranted': permissionGranted,
        if (placeUsable) ...<String, dynamic>{
          'placeLat': latitude,
          'placeLng': longitude,
        },
        'fixedAt': Timestamp.fromDate(fixedAt.toUtc()),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Guarda los filtros del feed en `users/{uid}.preferences`: el radio y el
  /// rango de edad en sus claves de siempre (las que escribe el onboarding y
  /// lee el directo) y el resto en `preferences.feedFilters`.
  ///
  /// `update` con rutas punteadas y no `set(merge)`: con merge, un mapa
  /// anidado se FUSIONA clave a clave, así que quitar un filtro no borraba el
  /// valor guardado; y el resto de `preferences` (`interestedIn`...) no se
  /// toca. El trigger de backend republica la ficha pública (el rango de edad
  /// va en discovery para la reciprocidad).
  Future<void> saveFeedPreferences({
    required String uid,
    int? maxDistanceKm,
    required int preferredAgeMin,
    required int preferredAgeMax,
    required Map<String, dynamic> feedFilters,
  }) async {
    await _usersCollection.doc(uid).update(buildFeedPreferencesPatch(
          maxDistanceKm: maxDistanceKm,
          preferredAgeMin: preferredAgeMin,
          preferredAgeMax: preferredAgeMax,
          feedFilters: feedFilters,
        ));
  }

  /// Lo que escribe [saveFeedPreferences] (puro, para poder probarlo).
  ///
  /// Sin radio NO se borra `preferences.maxDistanceKm`: la completitud del
  /// perfil lo exige y "sin radio" ya es el radio por defecto del feed.
  static Map<String, Object?> buildFeedPreferencesPatch({
    int? maxDistanceKm,
    required int preferredAgeMin,
    required int preferredAgeMax,
    required Map<String, dynamic> feedFilters,
  }) {
    return <String, Object?>{
      if (maxDistanceKm != null) 'preferences.maxDistanceKm': maxDistanceKm,
      'preferences.preferredAgeMin': preferredAgeMin,
      'preferences.preferredAgeMax': preferredAgeMax,
      'preferences.feedFilters': feedFilters,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Modo Amigos: guarda la intención en `users/{uid}.profile.intentMode`
  /// (misma vía que los rasgos, con los campos requeridos por las reglas). El
  /// re-sync a discovery lo hace la Cloud Function al escribir el user.
  Future<void> setIntentMode({
    required String uid,
    required String intentModeWire,
  }) async {
    await _usersCollection.doc(uid).set(
          _withRequiredUserFields(uid, <String, dynamic>{
            'profile': <String, dynamic>{'intentMode': intentModeWire},
            'updatedAt': FieldValue.serverTimestamp(),
          }),
          SetOptions(merge: true),
        );
  }

  /// Modo Amigos: preferencias sociales (intereses/tamaño de grupo/disponible).
  Future<void> setSocialPreferences({
    required String uid,
    List<String>? socialInterests,
    int? preferredGroupSize,
    bool? availableForPlans,
  }) async {
    final Map<String, dynamic> profile = <String, dynamic>{
      if (socialInterests != null) 'socialInterests': socialInterests,
      if (preferredGroupSize != null) 'preferredGroupSize': preferredGroupSize,
      if (availableForPlans != null) 'availableForPlans': availableForPlans,
    };
    if (profile.isEmpty) return;
    await _usersCollection.doc(uid).set(
          _withRequiredUserFields(uid, <String, dynamic>{
            'profile': profile,
            'updatedAt': FieldValue.serverTimestamp(),
          }),
          SetOptions(merge: true),
        );
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

  /// Perfiles semilla (mocks) para rellenar el feed.
  ///
  /// El tope era 30 y la consulta NO lleva `orderBy`, asi que Firestore
  /// devolvia los 30 primeros por id de documento y siempre LOS MISMOS: con la
  /// coleccion por encima de 30 documentos, todo lo que ordenara despues no
  /// existia para el feed. Los perfiles sembrados para cubrir identidades,
  /// orientaciones y modos (tool/seed_identity_matrix.py, prefijo `mock_ix_`)
  /// caian justo ahi, detras de los `mock_fm_*` y los `mock_giulia_*`.
  ///
  /// `seed_profiles` es una coleccion de demo, de documentos pequenos y de
  /// tamano controlado, asi que se lee entera y el filtrado real lo hace
  /// FeedFilter. El tope se mantiene por seguridad, no por coste.
  Future<List<SeedProfile>> fetchSeedProfiles({int limit = 150}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _seedProfilesCollection
            .where('isBot', isEqualTo: true)
            .limit(limit)
            .get();
    // Ficha a ficha, igual que discovery: un seed mal formado no vacía el feed.
    return snapshot.docs
        .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
            parseDiscoveryDoc(doc.id, doc.data()))
        .whereType<SeedProfile>()
        .toList(growable: false);
  }

  /// Perfil completo de un usuario por uid para verlo (desde chats, matches y
  /// likes): `discovery` (perfiles reales), `seed_profiles` (mocks) y, si no
  /// sale en el feed, su `profileCards` (ver [kPublicProfileCollections]).
  /// Antes un match o un like de alguien con el perfil oculto, la cuenta
  /// pausada o el incógnito daba "No se pudo cargar el perfil.".
  Future<SeedProfile?> fetchProfileByUid(String uid) =>
      profileByUid(uid, firestoreProfileDocReader(_firestore));

  /// Núcleo de [fetchProfileByUid] con el lector inyectable (tests).
  @visibleForTesting
  static Future<SeedProfile?> profileByUid(
    String uid,
    PublicProfileDocReader read,
  ) async {
    final MapEntry<String, Map<String, dynamic>>? found =
        await findPublicProfileDoc(uid, read);
    if (found == null) return null;
    return SeedProfile.fromMap(uid, found.value);
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

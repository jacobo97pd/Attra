import 'package:cloud_firestore/cloud_firestore.dart';

import '../../feed/domain/feed_filter.dart';
import '../../geo/domain/travel_rules.dart';
import '../domain/profile_trait.dart';
import '../domain/profile_traits_catalog.dart';
import '../domain/profile_visibility.dart';
import '../domain/public_identity.dart';

/// Construye el documento PUBLICO de `discovery/{uid}` a partir de
/// `users/{uid}`, respetando visibilidad/consentimiento. PURO (sin I/O) para
/// ser testeable.
///
/// Quien ESCRIBE la ficha es solo el backend (functions/src/discovery.ts,
/// `buildDiscoveryDoc`): las reglas ya no dejan al cliente escribirla. Esto es
/// su espejo en Dart y tiene que decidir LO MISMO (se prueba contra el feed):
/// si divergen, los tests del cliente dejan de describir lo que ven los demás.
///
/// Garantias:
/// - NUNCA publica email, nombre legal/Auth, tokens, selfie privada ni lat/lng
///   exactas; viajando, nunca las coordenadas reales (solo el centro del
///   destino).
/// - El nombre es el PUBLICO elegido ([resolvePublicDisplayName]).
/// - Un rasgo sensible solo se publica si visibleInProfile=true.
/// - Un valor `prefer_not_to_say` (o vacío) no se publica.
class DiscoveryPublisher {
  const DiscoveryPublisher._();

  /// [isPaid] = plan de pago activo (el viaje es Plus/Pro: sin él se ignora,
  /// igual que en el backend). [now] fija el reloj para la caducidad (tests).
  static Map<String, dynamic> buildPayload(
    String uid,
    Map<String, dynamic> userData, {
    bool isPaid = true,
    DateTime? now,
  }) {
    final Map<String, dynamic> profile = _map(userData['profile']);
    final Map<String, dynamic> prefs = _map(userData['preferences']);
    final ProfileVisibility vis = ProfileVisibility.fromUserData(userData);
    final DateTime? birthDate =
        _asDate(profile['birthDate']) ?? _asDate(userData['birthDate']);
    final int? age = _asInt(profile['age']) ??
        _asInt(userData['age']) ??
        _ageFromBirthDate(birthDate);

    // Modo viajes: si está activo, el perfil aparece en el DESTINO elegido (no
    // en su ciudad real) y se marca `traveling` para mostrar el distintivo.
    // Vive bajo `settings.travel` (compat: o `travel` arriba en docs antiguos).
    final Map<String, dynamic> settings = _map(userData['settings']);
    final Map<String, dynamic> travel = _map(settings['travel']).isNotEmpty
        ? _map(settings['travel'])
        : _map(userData['travel']);
    // Mismas condiciones que el backend: activo, con país, con plan de pago y
    // sin caducar (el más tardío entre `untilAt` y el ISO `until` de
    // versiones anteriores; una fecha imposible cuenta como caducada).
    final DateTime? travelUntil = TravelRules.effectiveUntil(
        _asDate(travel['untilAt']), _asDate(travel['until']));
    final bool travelOver =
        TravelRules.isOver(travelUntil, (now ?? DateTime.now()).toUtc());
    final bool traveling = travel['active'] == true &&
        (travel['country'] ?? '').toString().trim().isNotEmpty &&
        isPaid &&
        !travelOver;
    final String realCity =
        (profile['currentCity'] ?? profile['city'] ?? '').toString();
    final String realCountry = (profile['currentCountryName'] ?? '').toString();
    // País COMPARABLE (ISO2): el de destino viajando; si no, el del
    // geocodificador, el del onboarding o, como último recurso, el deducido del
    // nombre. Es lo que el feed compara: el nombre sale en el idioma de cada
    // teléfono.
    final String countryIso2 = traveling
        ? _iso2(travel['iso2'])
        : <String>[
            _iso2(profile['currentCountryIso2']),
            _iso2(profile['currentCountryCode']),
            _iso2(FeedFilter.canonCountry(realCountry)),
          ].firstWhere((String s) => s.isNotEmpty, orElse: () => '');

    // Ajustes de privacidad/ubicación que afectan a lo que se publica.
    // - location.showOnProfile=false → no exponer la ciudad (sí el país, que se
    //   usa para filtrar por país; la ciudad es lo identificativo).
    // - privacy.showDistance / showActiveStatus → banderas que el feed respeta.
    final bool showCity = settings['location.showOnProfile'] != false;
    final bool showDistance = settings['privacy.showDistance'] != false;
    final bool showActiveStatus = settings['privacy.showActiveStatus'] != false;

    final String pubCity =
        traveling ? (travel['city'] ?? '').toString() : realCity;

    // Núcleo público no sensible (identidad/matching mínimos).
    final Map<String, dynamic> out = <String, dynamic>{
      'uid': uid,
      'isBot': false,
      'displayName': resolvePublicDisplayName(userData),
      'photoUrl': userData['photoUrl'] ?? userData['profilePhotoUrl'] ?? '',
      'photos': userData['photos'] ?? <dynamic>[],
      'gender': profile['gender'] ?? '',
      'interestedIn': prefs['interestedIn'] ?? <dynamic>[],
      'age': age,
      'bio': profile['bio'] ?? '',
      'currentCity': showCity ? pubCity : '',
      'currentCountryName': traveling ? (travel['country'] ?? '') : realCountry,
      if (countryIso2.isNotEmpty) 'countryIso2': countryIso2,
      'traveling': traveling,
      // Viajando se publica el fin del viaje: así el feed de los demás puede
      // dejar de enseñarlo "de viaje" aunque el barrido del backend no haya
      // pasado todavía.
      if (traveling && travelUntil != null)
        'travelUntil': Timestamp.fromDate(travelUntil),
      'showDistance': showDistance,
      'showActiveStatus': showActiveStatus,
      // Modo Amigos: intención + intereses sociales (default dating si falta),
      // como el backend.
      'intentMode': (profile['intentMode'] is String &&
              (profile['intentMode'] as String).isNotEmpty)
          ? profile['intentMode']
          : 'dating',
      'socialInterests': profile['socialInterests'] is List
          ? profile['socialInterests']
          : <dynamic>[],
    };

    // Rasgos del catálogo: se publican bajo su `field` si son utilizables y
    // visibles (los sensibles requieren visibleInProfile explícito).
    // Además, los SENSIBLES con consentimiento useForFilters se publican en un
    // mapa aparte `filterTraits` (para poder filtrar por ellos sin exponerlos
    // si solo se quería matching).
    final Map<String, dynamic> filterTraits = <String, dynamic>{};
    for (final ProfileTraitDefinition def in ProfileTraitsCatalog.all) {
      final Object? value = _map(userData[def.group])[def.field];
      if (!isUsableTraitValue(value)) continue;
      final FieldVisibility fv = vis.effectiveFor(def);
      if (fv.visibleInProfile) {
        out[def.field] = _clean(value);
      }
      if (def.sensitive && fv.useForFilters && value is String) {
        filterTraits[def.field] = value;
      }
    }
    if (filterTraits.isNotEmpty) out['filterTraits'] = filterTraits;

    // Prompts de perfil (pregunta+respuesta): públicos por diseño, solo los
    // activos y con campos mínimos (sin metadatos internos).
    final List<dynamic> rawPrompts =
        (userData['profilePrompts'] as List<dynamic>?) ?? <dynamic>[];
    final List<Map<String, dynamic>> publicPrompts = rawPrompts
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) =>
            e.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)))
        .where((Map<String, dynamic> m) => (m['isActive'] as bool?) ?? true)
        .map((Map<String, dynamic> m) => <String, dynamic>{
              'id': m['id'] ?? '',
              'question': m['question'] ?? '',
              'answer': m['answer'] ?? '',
            })
        .where((Map<String, dynamic> m) =>
            (m['question'] as String).isNotEmpty &&
            (m['answer'] as String).isNotEmpty)
        .toList(growable: false);
    if (publicPrompts.isNotEmpty) out['profilePrompts'] = publicPrompts;

    // Media de presentación (audio/vídeo): pública por diseño. Se publica el
    // mapa tal cual (url/storagePath/durationMs) si existe.
    final Object? introAudio = profile['introAudio'];
    if (introAudio is Map && (introAudio['url'] ?? '').toString().isNotEmpty) {
      out['introAudio'] = introAudio;
    }
    final Object? introVideo = profile['introVideo'];
    if (introVideo is Map && (introVideo['url'] ?? '').toString().isNotEmpty) {
      out['introVideo'] = introVideo;
    }

    // Instagram (enlace, sin API de Meta): publica el @usuario si está activado.
    if (settings['integrations.instagram'] == true) {
      final String ig =
          (settings['integrations.instagramHandle'] ?? '').toString().trim();
      if (ig.isNotEmpty) out['instagram'] = ig;
    }

    // Verificación (selfie/identidad) — bool público.
    final Map<String, dynamic> verification = _map(userData['verification']);
    final String selfie =
        (verification['liveSelfiePublicPhotoUrl'] as String?)?.trim() ?? '';
    if (selfie.isNotEmpty) out['verified'] = true;

    // Ubicación APROXIMADA (coords redondeadas ~1.1km) para distancia. NUNCA
    // exacta. Solo si el usuario tiene ubicación.
    //
    // MODO VIAJE: las coordenadas REALES nunca se publican viajando (junto al
    // país de destino dejaban al viajero invisible en todos los feeds). Se
    // publica el CENTRO de la ciudad de destino si el viaje lo tiene: así solo
    // lo ve quien está alrededor del destino (antes, sin `geo`, lo veía el país
    // entero, su propia ciudad incluida). Sin centro (viaje a un país entero o
    // antiguo), sin `geo`: manda la regla de país, como antes.
    final Map<String, dynamic> location = _map(userData['location']);
    final double? travelLat = _asDouble(travel['lat']);
    final double? travelLng = _asDouble(travel['lng']);
    // Y tiene que ser el centro del destino ACTUAL (con ciudad y resuelto
    // para esa ciudad/ISO2), como `travelCenter` del backend.
    final bool travelCentered = traveling &&
        travelLat != null &&
        travelLng != null &&
        travelLat.isFinite &&
        travelLng.isFinite &&
        travelLat.abs() <= 90 &&
        travelLng.abs() <= 180 &&
        TravelRules.centerMatchesDestination(
          city: travel['city'],
          iso2: travel['iso2'],
          geoCity: travel['geoCity'],
          geoIso2: travel['geoIso2'],
        );
    final double? lat = traveling
        ? (travelCentered ? travelLat : null)
        : _asDouble(location['latitude']);
    final double? lng = traveling
        ? (travelCentered ? travelLng : null)
        : _asDouble(location['longitude']);
    if (lat != null && lng != null) {
      // Precisión: 'precise' redondea ~1.1km (2 decimales); 'approximate'
      // difumina a ~11km (1 decimal) para no revelar la zona exacta.
      final bool approx = (settings['location.precision'] ?? 'precise')
              .toString()
              .toLowerCase() ==
          'approximate';
      out['geo'] = <String, dynamic>{
        'lat': approx ? _round1(lat) : _round2(lat),
        'lng': approx ? _round1(lng) : _round2(lng),
      };
    }

    return out;
  }

  static String _iso2(Object? v) {
    final String s = v is String ? v.trim().toUpperCase() : '';
    return RegExp(r'^[A-Z]{2}$').hasMatch(s) ? s : '';
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int? _ageFromBirthDate(DateTime? birthDate) {
    if (birthDate == null) return null;
    final DateTime now = DateTime.now();
    final DateTime localBirthDate = birthDate.toLocal();
    int age = now.year - localBirthDate.year;
    final bool hasBirthdayPassed = now.month > localBirthDate.month ||
        (now.month == localBirthDate.month && now.day >= localBirthDate.day);
    if (!hasBirthdayPassed) age -= 1;
    if (age < 0 || age > 120) return null;
    return age;
  }

  /// Quita valores prefer_not_to_say de las listas antes de publicar.
  static Object? _clean(Object? value) {
    if (value is List) {
      return value
          .whereType<String>()
          .where((String e) => e.trim().isNotEmpty && e != 'prefer_not_to_say')
          .toList(growable: false);
    }
    return value;
  }

  static Map<String, dynamic> _map(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return v.map((dynamic k, dynamic val) => MapEntry(k.toString(), val));
    }
    return <String, dynamic>{};
  }
}

/// Resumen minimo de un perfil para listas (matches, chats, likes): nombre +
/// foto y unos pocos datos públicos opcionales (edad, profesión, ubicación,
/// verificación, intereses) para pintar tarjetas más ricas sin cargar el perfil
/// completo. Todos los extra son opcionales y degradan con elegancia.
class ProfileSummary {
  const ProfileSummary({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    this.age,
    this.headline = '',
    this.city = '',
    this.country = '',
    this.verified = false,
    this.interests = const <String>[],
  });

  final String uid;
  final String displayName;
  final String photoUrl;

  /// Edad pública (si se publicó). Null = desconocida.
  final int? age;

  /// Titular corto: puesto/ocupación pública. Vacío = sin dato.
  final String headline;

  /// Ubicación pública aproximada.
  final String city;
  final String country;

  /// Verificación (selfie/identidad) pública.
  final bool verified;

  /// Intereses públicos (para afinidad). Vacío = sin dato.
  final List<String> interests;

  static const ProfileSummary unknown = ProfileSummary(
    uid: '',
    displayName: 'Alguien',
    photoUrl: '',
  );

  /// Ubicación legible: "Ciudad, País" (omite las partes vacías).
  String get location {
    final List<String> parts = <String>[
      city.trim(),
      country.trim(),
    ].where((String s) => s.isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  ProfileSummary copyWith({
    String? uid,
    String? displayName,
    String? photoUrl,
    int? age,
    String? headline,
    String? city,
    String? country,
    bool? verified,
    List<String>? interests,
  }) {
    return ProfileSummary(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      age: age ?? this.age,
      headline: headline ?? this.headline,
      city: city ?? this.city,
      country: country ?? this.country,
      verified: verified ?? this.verified,
      interests: interests ?? this.interests,
    );
  }
}

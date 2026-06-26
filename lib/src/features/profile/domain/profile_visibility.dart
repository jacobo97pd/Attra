import 'profile_trait.dart';
import 'profile_traits_catalog.dart';

/// Consentimiento de un campo: separa mostrar en perfil, usar en matching y
/// usar en filtros futuros (RGPD: granular y revocable).
class FieldVisibility {
  const FieldVisibility({
    required this.visibleInProfile,
    required this.useForMatching,
    required this.useForFilters,
  });

  final bool visibleInProfile;
  final bool useForMatching;
  final bool useForFilters;

  /// Por defecto un campo NO sensible es visible y utilizable; uno sensible
  /// queda OPT-IN (todo en false hasta que el usuario lo active).
  static const FieldVisibility defaultNonSensitive = FieldVisibility(
      visibleInProfile: true, useForMatching: true, useForFilters: true);
  static const FieldVisibility defaultSensitive = FieldVisibility(
      visibleInProfile: false, useForMatching: false, useForFilters: false);

  FieldVisibility copyWith({
    bool? visibleInProfile,
    bool? useForMatching,
    bool? useForFilters,
  }) {
    return FieldVisibility(
      visibleInProfile: visibleInProfile ?? this.visibleInProfile,
      useForMatching: useForMatching ?? this.useForMatching,
      useForFilters: useForFilters ?? this.useForFilters,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'visibleInProfile': visibleInProfile,
        'useForMatching': useForMatching,
        'useForFilters': useForFilters,
      };

  factory FieldVisibility.fromMap(
      Map<String, dynamic> m, FieldVisibility fallback) {
    return FieldVisibility(
      visibleInProfile:
          (m['visibleInProfile'] as bool?) ?? fallback.visibleInProfile,
      useForMatching: (m['useForMatching'] as bool?) ?? fallback.useForMatching,
      useForFilters: (m['useForFilters'] as bool?) ?? fallback.useForFilters,
    );
  }
}

/// Visibilidad de todos los campos (de `users/{uid}.profileVisibility`).
class ProfileVisibility {
  const ProfileVisibility(
      {this.byKey = const <String, FieldVisibility>{}, this.updatedAt});

  final Map<String, FieldVisibility> byKey;
  final DateTime? updatedAt;

  /// Visibilidad efectiva de un rasgo: la guardada o el default por sensibilidad.
  FieldVisibility effectiveFor(ProfileTraitDefinition def) {
    return byKey[def.key] ??
        (def.sensitive
            ? FieldVisibility.defaultSensitive
            : FieldVisibility.defaultNonSensitive);
  }

  factory ProfileVisibility.fromUserData(Map<String, dynamic> userData) {
    final dynamic raw = userData['profileVisibility'];
    if (raw is! Map) return const ProfileVisibility();
    final Map<String, dynamic> map =
        raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
    final dynamic fields = map['fields'];
    final Map<String, FieldVisibility> byKey = <String, FieldVisibility>{};
    if (fields is Map) {
      fields.forEach((dynamic k, dynamic v) {
        if (v is Map) {
          final ProfileTraitDefinition? def =
              ProfileTraitsCatalog.byKey(k.toString());
          final FieldVisibility fallback = def?.sensitive == true
              ? FieldVisibility.defaultSensitive
              : FieldVisibility.defaultNonSensitive;
          byKey[k.toString()] = FieldVisibility.fromMap(
              v.map((dynamic kk, dynamic vv) => MapEntry(kk.toString(), vv)),
              fallback);
        }
      });
    }
    return ProfileVisibility(byKey: byKey);
  }
}

/// Un valor de rasgo es "utilizable" si está presente y no es prefer_not_to_say.
bool isUsableTraitValue(Object? value) {
  if (value == null) return false;
  if (value is String) {
    final String v = value.trim();
    return v.isNotEmpty && v != 'prefer_not_to_say';
  }
  if (value is num) return true;
  if (value is List) {
    return value
        .whereType<String>()
        .any((String e) => e.trim().isNotEmpty && e != 'prefer_not_to_say');
  }
  return false;
}

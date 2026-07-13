import 'package:cloud_firestore/cloud_firestore.dart';

/// Lugar público recomendado (`safePlaces/{id}`). Arquitectura preparada, función
/// desactivada por defecto (`feature_safedate_safe_places_enabled`).
///
/// NUNCA se etiqueta un lugar como "absolutamente seguro". Solo:
/// "Lugar público recomendado", "Establecimiento colaborador",
/// "Personal informado del protocolo Attra".
class SafePlace {
  const SafePlace({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.isPartner = false,
    this.staffProtocolEnabled = false,
    this.safetyFeatures = const <String>[],
    this.verificationStatus = 'unverified',
    this.updatedAt,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;
  final bool isPartner;
  final bool staffProtocolEnabled;
  final List<String> safetyFeatures;
  final String verificationStatus;
  final DateTime? updatedAt;

  /// Etiqueta a mostrar (nunca "seguro al 100%").
  String get badgeLabel {
    if (staffProtocolEnabled) return 'Personal informado del protocolo Attra';
    if (isPartner) return 'Establecimiento colaborador';
    return 'Lugar público recomendado';
  }

  factory SafePlace.fromMap(String id, Map<String, dynamic> map) {
    double d(Object? v) => v is num ? v.toDouble() : 0.0;
    return SafePlace(
      id: id,
      name: (map['name'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      latitude: d(map['latitude']),
      longitude: d(map['longitude']),
      category: (map['category'] ?? '').toString(),
      isPartner: map['isPartner'] == true,
      staffProtocolEnabled: map['staffProtocolEnabled'] == true,
      safetyFeatures: map['safetyFeatures'] is List
          ? (map['safetyFeatures'] as List)
              .map((Object? e) => e.toString())
              .toList()
          : const <String>[],
      verificationStatus: (map['verificationStatus'] ?? 'unverified').toString(),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}

// Attra Plans — modelo de dominio (PURO/testeable, sin Flutter).
//
// Una PROPUESTA de plan (`matches/{matchId}/datePlans/{planId}`) agrupa hasta 3
// OPCIONES reales de cita y su ciclo de voto/confirmación entre ambos usuarios.
// El backend es la única vía que crea/actualiza estos documentos; el cliente
// solo lee y vota vía Cloud Functions.
//
// Privacidad: NUNCA se guarda ni expone la ubicación exacta de un usuario. Solo
// ciudad/zona/barrio elegidos y, como mucho, la geo del LUGAR público sugerido.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Origen de la propuesta.
enum DatePlanSource {
  manual('manual'),
  aiSuggested('ai_suggested'),
  autoNudge('auto_nudge');

  const DatePlanSource(this.wireName);
  final String wireName;

  static DatePlanSource fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final DatePlanSource s in DatePlanSource.values) {
      if (s.wireName == raw || s.name.toLowerCase() == raw) return s;
    }
    return DatePlanSource.manual;
  }
}

/// Nivel de precisión geográfica que se comparte con el match. Ninguno expone
/// la ubicación exacta del usuario.
enum DatePlanPrivacyMode {
  city('city'), // solo ciudad
  zone('zone'), // barrio/zona elegida manualmente
  midpoint('midpoint'); // punto medio aproximado (ambos consintieron)

  const DatePlanPrivacyMode(this.wireName);
  final String wireName;

  static DatePlanPrivacyMode fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final DatePlanPrivacyMode m in DatePlanPrivacyMode.values) {
      if (m.wireName == raw || m.name.toLowerCase() == raw) return m;
    }
    return DatePlanPrivacyMode.city;
  }
}

/// Estado del ciclo de vida de una propuesta. Los valores de wire siguen la
/// especificación de Attra Plans. `acceptedByUserA/B` reflejan quién ha aceptado
/// (a = users[0], b = users[1], orden determinista del match).
enum DatePlanStatus {
  pending('pending'),
  acceptedByUserA('accepted_by_user_a'),
  acceptedByUserB('accepted_by_user_b'),
  confirmed('confirmed'),
  rejected('rejected'),
  expired('expired'),
  changed('changed');

  const DatePlanStatus(this.wireName);
  final String wireName;

  bool get isOpen =>
      this == pending || this == acceptedByUserA || this == acceptedByUserB;

  bool get isConfirmed => this == confirmed;

  static DatePlanStatus fromValue(Object? v) {
    final String raw = (v ?? '').toString().trim().toLowerCase();
    for (final DatePlanStatus s in DatePlanStatus.values) {
      if (s.wireName == raw || s.name.toLowerCase() == raw) return s;
    }
    return DatePlanStatus.pending;
  }
}

/// Una OPCIÓN concreta de plan. Los lugares reales provienen de Places API
/// (server-side); la IA nunca inventa `placeId`/`placeName`. Los campos de lugar
/// son opcionales para permitir opciones "solo tipo de plan" (fallback).
class DatePlanOption {
  const DatePlanOption({
    required this.id,
    required this.title,
    this.description = '',
    this.placeName = '',
    this.placeId = '',
    this.placeType = '',
    this.address = '',
    this.area = '',
    this.rating,
    this.reviewCount,
    this.priceLevel,
    this.mapsUrl = '',
    this.suggestedDateTime,
    this.whyItFits = '',
    this.tags = const <String>[],
    this.sourceApi = '',
  });

  final String id;
  final String title;
  final String description;

  /// Datos del lugar real (Places). Vacíos si es una opción genérica (fallback).
  final String placeName;
  final String placeId;
  final String placeType;
  final String address;
  final String area;
  final double? rating;
  final int? reviewCount;

  /// 0-4 (Google price_level). null si no disponible.
  final int? priceLevel;
  final String mapsUrl;

  /// Fecha/hora sugerida para esta opción.
  final DateTime? suggestedDateTime;

  /// Explicación humana de por qué encaja (la genera la IA o las reglas).
  final String whyItFits;
  final List<String> tags;

  /// De dónde salió el lugar: 'google_places' | 'fallback' | ''.
  final String sourceApi;

  bool get hasRealPlace => placeId.isNotEmpty && placeName.isNotEmpty;

  factory DatePlanOption.fromMap(Map<String, dynamic> map) {
    double? asDouble(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    int? asInt(Object? v) =>
        v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    return DatePlanOption(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      placeName: (map['placeName'] ?? '').toString(),
      placeId: (map['placeId'] ?? '').toString(),
      placeType: (map['placeType'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      area: (map['area'] ?? '').toString(),
      rating: asDouble(map['rating']),
      reviewCount: asInt(map['reviewCount']),
      priceLevel: asInt(map['priceLevel']),
      mapsUrl: (map['mapsUrl'] ?? '').toString(),
      suggestedDateTime: _asDate(map['suggestedDateTime']),
      whyItFits: (map['whyItFits'] ?? '').toString(),
      tags: map['tags'] is List
          ? (map['tags'] as List).map((Object? e) => e.toString()).toList()
          : const <String>[],
      sourceApi: (map['sourceApi'] ?? '').toString(),
    );
  }

  /// Para crear una opción manual desde el cliente (sin geo exacta).
  Map<String, dynamic> toCreateMap() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'placeName': placeName,
        'placeId': placeId,
        'placeType': placeType,
        'address': address,
        'area': area,
        if (rating != null) 'rating': rating,
        if (reviewCount != null) 'reviewCount': reviewCount,
        if (priceLevel != null) 'priceLevel': priceLevel,
        'mapsUrl': mapsUrl,
        if (suggestedDateTime != null)
          'suggestedDateTime': suggestedDateTime!.toUtc().toIso8601String(),
        'whyItFits': whyItFits,
        'tags': tags,
        'sourceApi': sourceApi,
      };

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}

/// La propuesta completa (documento `datePlans/{planId}`).
class DatePlanProposal {
  const DatePlanProposal({
    required this.id,
    required this.matchId,
    required this.createdBy,
    required this.users,
    required this.status,
    required this.source,
    required this.options,
    this.acceptedBy = const <String>[],
    this.rejectedBy = const <String>[],
    this.votesByUser = const <String, String>{},
    this.selectedOptionId = '',
    this.commonInterests = const <String>[],
    this.generatedReason = '',
    this.city = '',
    this.zone = '',
    this.privacyMode = DatePlanPrivacyMode.city,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
  });

  final String id;
  final String matchId;
  final String createdBy;
  final List<String> users;
  final DatePlanStatus status;
  final DatePlanSource source;
  final List<DatePlanOption> options;

  /// Uids que han aceptado (autoritativo, independiente del orden a/b).
  final List<String> acceptedBy;
  final List<String> rejectedBy;

  /// Voto por usuario: uid -> optionId elegido.
  final Map<String, String> votesByUser;

  /// Opción confirmada (cuando ambos coinciden).
  final String selectedOptionId;

  final List<String> commonInterests;
  final String generatedReason;

  /// Geo compartida: nunca la exacta del usuario.
  final String city;
  final String zone;
  final DatePlanPrivacyMode privacyMode;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isActionable => status.isOpen && !isExpired;

  bool hasVoted(String uid) => votesByUser.containsKey(uid);

  bool hasAccepted(String uid) => acceptedBy.contains(uid);

  DatePlanOption? get selectedOption {
    if (selectedOptionId.isEmpty) return null;
    for (final DatePlanOption o in options) {
      if (o.id == selectedOptionId) return o;
    }
    return null;
  }

  factory DatePlanProposal.fromMap(String id, Map<String, dynamic> map) {
    List<String> strList(Object? v) => v is List
        ? v.map((Object? e) => e.toString()).toList()
        : const <String>[];
    return DatePlanProposal(
      id: id,
      matchId: (map['matchId'] ?? '').toString(),
      createdBy: (map['createdBy'] ?? '').toString(),
      users: strList(map['users']),
      status: DatePlanStatus.fromValue(map['status']),
      source: DatePlanSource.fromValue(map['source']),
      options: map['options'] is List
          ? (map['options'] as List)
              .whereType<Map<dynamic, dynamic>>()
              .map((Map<dynamic, dynamic> e) => DatePlanOption.fromMap(
                    e.map((dynamic k, dynamic v) => MapEntry(k.toString(), v)),
                  ))
              .toList()
          : const <DatePlanOption>[],
      acceptedBy: strList(map['acceptedBy']),
      rejectedBy: strList(map['rejectedBy']),
      votesByUser: map['votesByUser'] is Map
          ? (map['votesByUser'] as Map).map(
              (dynamic k, dynamic v) => MapEntry(k.toString(), v.toString()))
          : const <String, String>{},
      selectedOptionId: (map['selectedOptionId'] ?? '').toString(),
      commonInterests: strList(map['commonInterests']),
      generatedReason: (map['generatedReason'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      zone: (map['zone'] ?? '').toString(),
      privacyMode: DatePlanPrivacyMode.fromValue(map['privacyMode']),
      createdAt: DatePlanOption._asDate(map['createdAt']),
      updatedAt: DatePlanOption._asDate(map['updatedAt']),
      expiresAt: DatePlanOption._asDate(map['expiresAt']),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'pair_id.dart';

/// Descarte unilateral de A hacia B (pass). Sirve para no volver a mostrar el
/// perfil durante un periodo configurable. No afecta a los likes recibidos.
class Dislike {
  const Dislike({
    required this.fromUid,
    required this.toUid,
    this.createdAt,
  });

  final String fromUid;
  final String toUid;
  final DateTime? createdAt;

  /// ID determinista del documento en `dislikes/`.
  static String idFor(String fromUid, String toUid) =>
      directedId(fromUid, toUid);

  String get id => idFor(fromUid, toUid);

  factory Dislike.fromMap(Map<String, dynamic> map) {
    return Dislike(
      fromUid: (map['fromUid'] as String?) ?? '',
      toUid: (map['toUid'] as String?) ?? '',
      createdAt: _asDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      'fromUid': fromUid,
      'toUid': toUid,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}

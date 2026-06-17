import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Registro ligero de eventos de Attra Spark. Fire-and-forget: nunca bloquea ni
/// rompe el juego si falla. Escribe en `sparkAnalytics/{autoId}` (append-only).
class SparkAnalytics {
  SparkAnalytics({required FirebaseFirestore firestore})
      : _col = firestore.collection('sparkAnalytics');

  final CollectionReference<Map<String, dynamic>> _col;

  static const String invited = 'spark_invited';
  static const String accepted = 'spark_accepted';
  static const String started = 'spark_started';
  static const String roundCompleted = 'spark_round_completed';
  static const String completed = 'spark_completed';
  static const String abandoned = 'spark_abandoned';
  static const String chatOpenedAfter = 'spark_chat_opened_after';
  static const String planSuggestedAfter = 'spark_plan_suggested_after';

  void log(
    String event, {
    required String uid,
    String? matchId,
    String? sessionId,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    // No await: no debe ralentizar la UI del juego.
    _col.add(<String, dynamic>{
      'event': event,
      'uid': uid,
      if (matchId != null) 'matchId': matchId,
      if (sessionId != null) 'sessionId': sessionId,
      ...extra,
      'at': FieldValue.serverTimestamp(),
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('SparkAnalytics: $event falló -> $e');
      return _col.doc(); // valor de relleno (ignorado).
    });
  }
}

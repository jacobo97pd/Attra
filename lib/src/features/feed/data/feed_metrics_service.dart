import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Telemetría del feed/embudo + registro de impresiones (frecuencia de
/// aparición). Fire-and-forget: NUNCA bloquea ni rompe la UI si falla.
///
/// Dos destinos:
///   - `feedEvents/{id}`         eventos discretos del embudo (append-only).
///   - `seenProfiles/{uid}/seen/{otherUid}`  contador de impresiones (en BATCH
///     para no escribir por cada tarjeta vista).
///
/// `profileShown` se captura de forma AGREGADA como impresiones en seenProfiles
/// (no como un evento por tarjeta, que saturaría). Los eventos de feedEvents son
/// las interacciones de baja frecuencia y alto valor (like/attra/nope/match…).
class FeedMetricsService {
  FeedMetricsService({required FirebaseFirestore firestore})
      : _db = firestore;

  final FirebaseFirestore _db;

  // --- Nombres de evento (única fuente de verdad) ---
  static const String profileOpened = 'profileOpened';
  static const String likeSent = 'likeSent';
  static const String attraSent = 'attraSent';
  static const String nopeSent = 'nopeSent';
  static const String matchCreated = 'matchCreated';
  static const String messageSent = 'messageSent';
  static const String conversationStarted = 'conversationStarted';
  static const String dateProposed = 'dateProposed';

  /// Cuántas impresiones acumulamos antes de volcar a Firestore.
  static const int _flushThreshold = 8;

  final Set<String> _impressionBuffer = <String>{};
  String? _bufferUid;

  /// Registra un evento del embudo (append-only). No await.
  void log(
    String event, {
    required String uid,
    String? targetUid,
    Map<String, dynamic> meta = const <String, dynamic>{},
  }) {
    _db.collection('feedEvents').add(<String, dynamic>{
      'event': event,
      'uid': uid,
      if (targetUid != null) 'targetUid': targetUid,
      ...meta,
      'at': FieldValue.serverTimestamp(),
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('FeedMetrics: $event falló -> $e');
      return _db.collection('feedEvents').doc(); // relleno ignorado
    });
  }

  /// Acumula una impresión (perfil mostrado). Vuelca en batch al llegar al
  /// umbral. Llama [flush] al salir del feed para no perder las pendientes.
  void recordImpression(String uid, String shownUid) {
    if (shownUid.isEmpty) return;
    _bufferUid = uid;
    if (_impressionBuffer.add(shownUid) &&
        _impressionBuffer.length >= _flushThreshold) {
      flush();
    }
  }

  /// Vuelca las impresiones acumuladas a `seenProfiles` (incrementa contador).
  Future<void> flush() async {
    final String? uid = _bufferUid;
    if (uid == null || _impressionBuffer.isEmpty) return;
    final List<String> batchUids = _impressionBuffer.toList(growable: false);
    _impressionBuffer.clear();

    final WriteBatch batch = _db.batch();
    final CollectionReference<Map<String, dynamic>> seen =
        _db.collection('seenProfiles').doc(uid).collection('seen');
    for (final String other in batchUids) {
      batch.set(
        seen.doc(other),
        <String, dynamic>{
          'lastShownAt': FieldValue.serverTimestamp(),
          'impressions': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }
    try {
      await batch.commit();
    } catch (e) {
      if (kDebugMode) debugPrint('FeedMetrics: flush impresiones falló -> $e');
    }
  }
}

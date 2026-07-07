import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/date_plan.dart';

/// Lecturas en vivo de Attra Plans. SOLO lectura: crear/votar pasa por Cloud
/// Functions (DatePlanService). Los planes viven en `matches/{matchId}/datePlans`.
class DatePlanRepository {
  DatePlanRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _plans(String matchId) =>
      _firestore.collection('matches').doc(matchId).collection('datePlans');

  /// Propuestas de un match, más recientes primero (orderBy de campo único: no
  /// requiere índice compuesto).
  Stream<List<DatePlanProposal>> observePlans(String matchId) {
    return _plans(matchId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
            .map((QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                DatePlanProposal.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

  Stream<DatePlanProposal?> observePlan(String matchId, String planId) {
    return _plans(matchId).doc(planId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            d.exists ? DatePlanProposal.fromMap(d.id, d.data()!) : null);
  }
}

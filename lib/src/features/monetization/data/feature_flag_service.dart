import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/monetization_feature_flags.dart';

/// Fuente remota de feature flags / kill switch de monetizacion e IA.
///
/// Implementacion actual: documento Firestore `config/featureFlags`
/// (read-only para el cliente). Se modela como interfaz para poder migrar a
/// Firebase Remote Config sin tocar la UI ni el controller.
abstract class FeatureFlagService {
  /// Lee los flags una vez. Si el documento no existe, devuelve los defaults
  /// seguros de [MonetizationFeatureFlags].
  Future<MonetizationFeatureFlags> fetchFlags();

  /// Observa cambios en vivo (permite kill switch en caliente).
  Stream<MonetizationFeatureFlags> watchFlags();
}

class FirestoreFeatureFlagService implements FeatureFlagService {
  FirestoreFeatureFlagService({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('config').doc('featureFlags');

  @override
  Future<MonetizationFeatureFlags> fetchFlags() async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _doc.get();
    return _fromSnapshot(snapshot);
  }

  @override
  Stream<MonetizationFeatureFlags> watchFlags() {
    return _doc.snapshots().map(_fromSnapshot);
  }

  MonetizationFeatureFlags _fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic>? data = snapshot.data();
    if (!snapshot.exists || data == null) {
      // Defaults seguros: monetizacion on, IA on pero sin kill switch.
      return const MonetizationFeatureFlags();
    }
    return MonetizationFeatureFlags.fromMap(data);
  }
}

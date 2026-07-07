import 'package:cloud_functions/cloud_functions.dart';

import '../domain/date_plan.dart';
import 'date_plan_repository.dart';

class DatePlanServiceException implements Exception {
  const DatePlanServiceException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'DatePlanServiceException($code): $message';
}

/// Fachada de Attra Plans para la UI. Escrituras vía Cloud Functions (backend
/// autoritativo), lecturas vía [DatePlanRepository].
///
/// Fase 1: solo creación MANUAL (`createDatePlanProposal`). La generación con
/// reglas/Places (Fase 2) e IA (Fase 3) y la votación (Fase 4) se añaden después
/// como métodos nuevos, sin romper esta API.
class DatePlanService {
  DatePlanService({
    required DatePlanRepository repository,
    required FirebaseFunctions functions,
  })  : _repository = repository,
        _functions = functions;

  final DatePlanRepository _repository;
  final FirebaseFunctions _functions;

  // --- Escrituras (backend) ---

  /// Crea una propuesta MANUAL (sin IA ni Places). Cada opción la ha compuesto
  /// el usuario. Devuelve el id de la propuesta creada.
  Future<String> createManualProposal({
    required String chatId,
    required List<DatePlanOption> options,
    String city = '',
    String zone = '',
    DatePlanPrivacyMode privacyMode = DatePlanPrivacyMode.city,
  }) async {
    final Map<String, dynamic> data =
        await _call('createDatePlanProposal', <String, dynamic>{
      'chatId': chatId,
      'source': DatePlanSource.manual.wireName,
      'city': city,
      'zone': zone,
      'privacyMode': privacyMode.wireName,
      'options': options.map((DatePlanOption o) => o.toCreateMap()).toList(),
    });
    return (data['planId'] as String?) ?? '';
  }

  /// Genera hasta 3 opciones con reglas + Google Places (Fase 2). El backend
  /// decide si usa lugares reales o fallback. Devuelve el id de la propuesta.
  /// [dateRange]: 'this_week' | 'weekend'. [timeWindow]: 'afternoon' | 'evening'
  /// | 'flexible'. [budget]: 'bajo' | 'medio' | 'alto'. [planType]: categoría
  /// opcional a forzar. [zone]: barrio/zona (nunca ubicación exacta).
  Future<String> generatePlans({
    required String chatId,
    String zone = '',
    String dateRange = '',
    String timeWindow = 'flexible',
    String budget = '',
    String planType = '',
  }) async {
    final Map<String, dynamic> data =
        await _call('generateDatePlanSuggestions', <String, dynamic>{
      'chatId': chatId,
      if (zone.isNotEmpty) 'zone': zone,
      if (dateRange.isNotEmpty) 'dateRange': dateRange,
      if (timeWindow.isNotEmpty) 'timeWindow': timeWindow,
      if (budget.isNotEmpty) 'budget': budget,
      if (planType.isNotEmpty) 'planType': planType,
    });
    return (data['planId'] as String?) ?? '';
  }

  /// Vota una opción como favorita (Fase 4). Cuando ambos eligen la misma, la
  /// propuesta queda confirmada. Devuelve el estado resultante.
  Future<String> voteOption({
    required String chatId,
    required String planId,
    required String optionId,
  }) async {
    final Map<String, dynamic> data =
        await _call('voteDatePlan', <String, dynamic>{
      'chatId': chatId,
      'planId': planId,
      'voteType': 'like',
      'optionId': optionId,
    });
    return (data['status'] as String?) ?? '';
  }

  /// Rechaza la propuesta entera ("no me interesa"). La cierra.
  Future<void> rejectProposal({
    required String chatId,
    required String planId,
  }) async {
    await _call('voteDatePlan', <String, dynamic>{
      'chatId': chatId,
      'planId': planId,
      'voteType': 'reject',
    });
  }

  // --- Lecturas ---

  Stream<List<DatePlanProposal>> observePlans(String matchId) =>
      _repository.observePlans(matchId);

  Stream<DatePlanProposal?> observePlan(String matchId, String planId) =>
      _repository.observePlan(matchId, planId);

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable(name).call<dynamic>(data);
      final dynamic raw = result.data;
      if (raw is Map) {
        return raw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (error) {
      throw DatePlanServiceException(error.message ?? error.code,
          code: error.code);
    }
  }
}

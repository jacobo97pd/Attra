import 'package:cloud_functions/cloud_functions.dart';

import '../domain/like.dart';
import '../domain/match_flow_result.dart';
import '../domain/user_match.dart';
import 'match_repository.dart';

/// Error de una operacion de match (envuelve FirebaseFunctionsException).
class MatchServiceException implements Exception {
  const MatchServiceException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'MatchServiceException($code): $message';
}

/// Fachada del sistema de match para la UI/controladores: escrituras via Cloud
/// Functions (seguras, transaccionales) + lecturas en vivo via MatchRepository.
class MatchService {
  MatchService({
    required MatchRepository repository,
    required FirebaseFunctions functions,
  })  : _repository = repository,
        _functions = functions;

  final MatchRepository _repository;
  final FirebaseFunctions _functions;

  // --- Escrituras (backend) ---

  /// Like al perfil, a una foto concreta ([targetPhotoId]) o a un prompt
  /// ([promptQuestion]/[promptAnswer]) con comentario opcional. Sin objetivo se
  /// comporta como un like normal al perfil.
  Future<MatchFlowResult> sendLike(
    String toUid, {
    String? targetPhotoId,
    String? comment,
    String? promptId,
    String? promptQuestion,
    String? promptAnswer,
  }) async {
    final Map<String, dynamic> data = await _call('sendLike', <String, dynamic>{
      'toUid': toUid,
      ..._targetArgs(targetPhotoId, promptId, promptQuestion, promptAnswer),
      if (comment != null && comment.trim().isNotEmpty) 'commentText': comment.trim(),
    });
    return MatchFlowResult.fromMap(data);
  }

  Future<MatchFlowResult> sendAttra(
    String toUid, {
    String? targetPhotoId,
    String? comment,
    String? promptId,
    String? promptQuestion,
    String? promptAnswer,
  }) async {
    final Map<String, dynamic> data = await _call('sendAttra', <String, dynamic>{
      'toUid': toUid,
      ..._targetArgs(targetPhotoId, promptId, promptQuestion, promptAnswer),
      if (comment != null && comment.trim().isNotEmpty) 'commentText': comment.trim(),
    });
    return MatchFlowResult.fromMap(data);
  }

  /// Argumentos del objetivo del like (foto o prompt) para el backend.
  Map<String, dynamic> _targetArgs(String? targetPhotoId, String? promptId,
      String? promptQuestion, String? promptAnswer) {
    if (promptQuestion != null && promptQuestion.trim().isNotEmpty) {
      return <String, dynamic>{
        'targetType': 'prompt',
        if (promptId != null) 'targetPromptId': promptId,
        'targetPromptQuestion': promptQuestion.trim(),
        if (promptAnswer != null) 'targetPromptAnswer': promptAnswer.trim(),
      };
    }
    if (targetPhotoId != null) {
      return <String, dynamic>{
        'targetType': 'photo',
        'targetPhotoId': targetPhotoId,
      };
    }
    return const <String, dynamic>{};
  }

  Future<void> passProfile(String toUid) async {
    await _call('passProfile', <String, dynamic>{'toUid': toUid});
  }

  Future<void> unmatch(String matchId) async {
    await _call('unmatch', <String, dynamic>{'matchId': matchId});
  }

  Future<void> blockUser(String blockedUid) async {
    await _call('blockUser', <String, dynamic>{'blockedUid': blockedUid});
  }

  Future<String> reportUser({
    required String reportedUid,
    required String reason,
    String details = '',
    String? matchId,
    String? chatId,
    String? messageId,
  }) async {
    final Map<String, dynamic> data = await _call('reportUser', <String, dynamic>{
      'reportedUid': reportedUid,
      'reason': reason,
      'details': details,
      if (matchId != null) 'matchId': matchId,
      if (chatId != null) 'chatId': chatId,
      if (messageId != null) 'messageId': messageId,
    });
    return (data['reportId'] as String?) ?? '';
  }

  // --- Lecturas (delegadas al repositorio) ---

  Stream<List<UserMatch>> observeMatches(String uid) =>
      _repository.observeMatches(uid);

  Stream<UserMatch?> observeMatchById(String matchId) =>
      _repository.observeMatchById(matchId);

  Stream<List<Like>> observeReceivedLikes(String uid) =>
      _repository.observeReceivedLikes(uid);

  /// Uids ya likeados/pasados/matcheados/bloqueados, para excluir del feed.
  Future<Set<String>> fetchExcludedUids(String uid) =>
      _repository.fetchExcludedUids(uid);

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
      throw MatchServiceException(error.message ?? error.code, code: error.code);
    }
  }
}

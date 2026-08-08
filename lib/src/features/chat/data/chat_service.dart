import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../../chat_game/domain/chat_game.dart';
import '../domain/chat.dart';
import '../domain/chat_message.dart';
import 'chat_repository.dart';

class ChatServiceException implements Exception {
  const ChatServiceException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'ChatServiceException($code): $message';
}

/// Lado mayor maximo de una imagen de chat tras redimensionar (px).
const int kMaxChatImageDimension = 1600;

/// Resultado de procesar una imagen antes de subirla.
class ProcessedChatImage {
  const ProcessedChatImage({
    required this.bytes,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Recodifica unos bytes con el decodificador NATIVO del móvil.
///
/// Devuelve `null` si el sistema tampoco supo leerlos. Separado en un typedef
/// para poder falsearlo: la implementación real habla por canal nativo y no
/// existe en los tests.
typedef ChatImageTranscoder = Future<Uint8List?> Function(
  Uint8List bytes,
  int maxSide,
);

/// Fachada de chat para la UI: enviar/leer/typing via Cloud Functions +
/// streams de lectura via ChatRepository.
class ChatService {
  ChatService({
    required ChatRepository repository,
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
    ChatImageTranscoder? transcodeImage,
  })  : _repository = repository,
        _functions = functions,
        _storage = storage,
        _transcodeImage = transcodeImage ?? _compressWithSystem;

  final ChatRepository _repository;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  final ChatImageTranscoder _transcodeImage;

  // --- Escrituras (backend) ---

  /// Devuelve el id del mensaje creado.
  Future<String> sendMessage({
    required String chatId,
    required String text,
    String? gameSessionId,
  }) async {
    final Map<String, dynamic> data =
        await _call('sendMessage', <String, dynamic>{
      'chatId': chatId,
      'text': text,
      if (gameSessionId != null) 'gameSessionId': gameSessionId,
    });
    return (data['messageId'] as String?) ?? '';
  }

  /// Envia una FOTO: redimensiona, VACIA EL EXIF (incluido el GPS) y recomprime
  /// a JPEG, sube a Storage en ruta segura por uid y crea el mensaje via
  /// `sendMediaMessage` (que valida tamaño/MIME real del objeto). Devuelve el id.
  Future<String> sendImage({
    required String chatId,
    required String senderUid,
    required Uint8List bytes,
    String? fileName,
  }) async {
    final ProcessedChatImage processed =
        await processChatImageBytes(bytes, transcode: _transcodeImage);
    final String messageId = _genId();
    final String path = 'chats/$chatId/images/$senderUid/$messageId.jpg';
    final String url =
        await _uploadToStorage(path, processed.bytes, 'image/jpeg');
    await _call('sendMediaMessage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'type': 'image',
      'storagePath': path,
      'downloadUrl': url,
      'mimeType': 'image/jpeg',
      'width': processed.width,
      'height': processed.height,
      if (fileName != null) 'fileName': fileName,
    });
    return messageId;
  }

  /// Envia una FOTO BOMBA: se procesa igual que una foto normal, pero se sube a
  /// una ruta sin lectura directa y el mensaje no guarda downloadUrl. El
  /// receptor la abre con [openBombImage], que consume la unica vista.
  Future<String> sendBombImage({
    required String chatId,
    required String senderUid,
    required Uint8List bytes,
    String? fileName,
  }) async {
    final ProcessedChatImage processed =
        await processChatImageBytes(bytes, transcode: _transcodeImage);
    final String messageId = _genId();
    final String path = 'chats/$chatId/bombs/$senderUid/$messageId.jpg';
    await _uploadToStorage(
      path,
      processed.bytes,
      'image/jpeg',
      returnDownloadUrl: false,
    );
    await _call('sendMediaMessage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'type': 'bomb_image',
      'storagePath': path,
      'mimeType': 'image/jpeg',
      'width': processed.width,
      'height': processed.height,
      if (fileName != null) 'fileName': fileName,
    });
    return messageId;
  }

  /// Envia una NOTA DE VOZ: sube el audio grabado a Storage y crea el mensaje.
  Future<String> sendVoiceNote({
    required String chatId,
    required String senderUid,
    required Uint8List bytes,
    required int durationMs,
    String contentType = 'audio/mp4',
    String extension = 'm4a',
  }) async {
    final String messageId = _genId();
    final String path = 'chats/$chatId/voice/$senderUid/$messageId.$extension';
    final String url = await _uploadToStorage(path, bytes, contentType);
    await _call('sendMediaMessage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'type': 'voice_note',
      'storagePath': path,
      'downloadUrl': url,
      'mimeType': contentType,
      'durationMs': durationMs,
    });
    return messageId;
  }

  /// Sube bytes a Storage y devuelve la downloadUrl. Traduce los errores de
  /// Storage (reglas, CORS, red…) a un ChatServiceException legible para la UI.
  Future<String> _uploadToStorage(
    String path,
    Uint8List bytes,
    String contentType, {
    bool returnDownloadUrl = true,
  }) async {
    try {
      final Reference ref = _storage.ref().child(path);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      if (!returnDownloadUrl) return '';
      return await ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw ChatServiceException(
        'Error al subir a Storage: ${e.code}${e.message != null ? ' — ${e.message}' : ''}',
        code: e.code,
      );
    }
  }


  String _genId() {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    // 0x7FFFFFFF (2^31-1) es seguro en web; `1 << 32` desborda a 0 en dart2js.
    final Random rng = Random();
    final String a = rng.nextInt(0x7FFFFFFF).toRadixString(16);
    final String b = rng.nextInt(0x7FFFFFFF).toRadixString(16);
    return '${ts}_$a$b';
  }

  Future<void> markAsRead(String chatId) async {
    await _call('markMessagesAsRead', <String, dynamic>{'chatId': chatId});
  }

  /// Marca el chat como no leido solo para el usuario actual (no toca mensajes).
  Future<void> markAsUnread(String chatId) async {
    await _call('markChatAsUnread', <String, dynamic>{'chatId': chatId});
  }

  /// Consume una foto bomba y devuelve sus BYTES (una sola vez). El backend
  /// envía la imagen en base64 y borra el fichero; si ya fue abierta, rechaza.
  Future<Uint8List> openBombImage({
    required String chatId,
    required String messageId,
  }) async {
    final Map<String, dynamic> data =
        await _call('openBombImage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
    });
    final String b64 = (data['imageBase64'] as String?) ?? '';
    if (b64.isEmpty) {
      throw const ChatServiceException('No se pudo abrir la foto bomba.');
    }
    return base64Decode(b64);
  }

  /// Crea una propuesta de cita (mensaje `date_proposal`) en el chat.
  Future<String> sendDateProposal({
    required String chatId,
    required String proposedDate,
    required String proposedTime,
    required String placeName,
    String placeAddress = '',
    String note = '',
  }) async {
    final Map<String, dynamic> data =
        await _call('sendDateProposal', <String, dynamic>{
      'chatId': chatId,
      'proposedDate': proposedDate,
      'proposedTime': proposedTime,
      'placeName': placeName,
      if (placeAddress.isNotEmpty) 'placeAddress': placeAddress,
      if (note.isNotEmpty) 'note': note,
    });
    return (data['messageId'] as String?) ?? '';
  }

  /// El receptor responde a una propuesta: accepted | declined | countered.
  Future<void> respondDateProposal({
    required String chatId,
    required String messageId,
    required String response,
  }) async {
    await _call('respondDateProposal', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'response': response,
    });
  }

  Future<String> startDoubleAnswer({
    required String chatId,
    required String question,
  }) async {
    final Map<String, dynamic> data =
        await _call('startDoubleAnswer', <String, dynamic>{
      'chatId': chatId,
      'question': question,
    });
    return (data['messageId'] as String?) ?? '';
  }

  Future<void> submitDoubleAnswer({
    required String chatId,
    required String messageId,
    required String answer,
  }) async {
    await _call('submitDoubleAnswer', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'answer': answer,
    });
  }

  Future<String> startTwoTruths({
    required String chatId,
    required List<String> statements,
    required int lieIndex,
  }) async {
    final Map<String, dynamic> data =
        await _call('startTwoTruths', <String, dynamic>{
      'chatId': chatId,
      'statements': statements,
      'lieIndex': lieIndex,
    });
    return (data['messageId'] as String?) ?? '';
  }

  Future<void> guessTwoTruths({
    required String chatId,
    required String messageId,
    required int guessIndex,
  }) async {
    await _call('guessTwoTruths', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'guessIndex': guessIndex,
    });
  }

  /// Cierra el chat con elegancia (Attra Clear §3): envía el mensaje de
  /// despedida [message] y marca el chat como cerrado con [reason]. Devuelve el
  /// id del mensaje de cierre.
  Future<String> closeConversation({
    required String chatId,
    required String reason,
    required String message,
  }) async {
    final Map<String, dynamic> data =
        await _call('closeConversationGracefully', <String, dynamic>{
      'chatId': chatId,
      'reason': reason,
      'message': message,
    });
    return (data['messageId'] as String?) ?? '';
  }

  /// Attra Clear §6: registra la respuesta al follow-up post-cita. El cierre o
  /// reporte posterior se encadena con [closeConversation] / reporte normal.
  Future<void> answerDateFollowUp({
    required String chatId,
    required String answer,
  }) async {
    await _call('answerDateFollowUp', <String, dynamic>{
      'chatId': chatId,
      'answer': answer,
    });
  }

  Future<void> setTyping(String chatId, bool isTyping) async {
    await _call('setTyping', <String, dynamic>{
      'chatId': chatId,
      'isTyping': isTyping,
    });
  }

  // --- Duelo de Química (reto de 5 min) ---

  /// Crea el reto e inserta la tarjeta de invitación en el chat. [mode] =
  /// 'normal' | 'coffee_challenge' (este último requiere consentimiento de ambos).
  /// Devuelve el id de la sesión.
  Future<String> startChatGame({
    required String chatId,
    String mode = 'normal',
  }) async {
    final Map<String, dynamic> data =
        await _call('startChatGame', <String, dynamic>{
      'chatId': chatId,
      'mode': mode,
    });
    return (data['sessionId'] as String?) ?? '';
  }

  /// El invitado acepta/rechaza. Si ambos aceptan, arranca el reto (tema + 5 min).
  /// Para 'coffee_challenge', [accept] true implica aceptar la regla del café.
  Future<void> respondChatGame({
    required String chatId,
    required String sessionId,
    required bool accept,
  }) async {
    await _call('respondChatGame', <String, dynamic>{
      'chatId': chatId,
      'sessionId': sessionId,
      'accept': accept,
    });
  }

  /// Cierra el reto al agotarse el tiempo: la IA analiza SOLO los mensajes de
  /// esos 5 minutos y emite el resultado. Idempotente (si ya está cerrado, no-op).
  Future<void> finishChatGame({
    required String chatId,
    required String sessionId,
  }) async {
    await _call('finishChatGame', <String, dynamic>{
      'chatId': chatId,
      'sessionId': sessionId,
    });
  }

  /// Abandona el reto en curso (sin penalización): lo deja en `abandoned`.
  Future<void> abandonChatGame({
    required String chatId,
    required String sessionId,
  }) async {
    await _call('abandonChatGame', <String, dynamic>{
      'chatId': chatId,
      'sessionId': sessionId,
    });
  }

  Stream<ChatGameSession?> observeGameSession(
          String chatId, String sessionId) =>
      _repository.observeGameSession(chatId, sessionId);

  // --- Lecturas ---

  Stream<List<Chat>> observeChats(String uid) => _repository.observeChats(uid);

  Stream<Chat?> observeChatById(String chatId) =>
      _repository.observeChatById(chatId);

  Stream<List<ChatMessage>> observeMessages(String chatId) =>
      _repository.observeMessages(chatId);

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
      throw ChatServiceException(error.message ?? error.code, code: error.code);
    }
  }
}

/// Recodificación real con el decodificador del sistema.
///
/// Solo se usa como SEGUNDO intento, cuando el paquete `image` no ha sabido leer
/// los bytes: transcodificar siempre pasaría por JPEG capturas de pantalla que
/// ahora salen intactas y las dejaría peor.
Future<Uint8List?> _compressWithSystem(Uint8List bytes, int maxSide) async {
  try {
    final Uint8List out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxSide,
      minHeight: maxSide,
      quality: 92,
      format: CompressFormat.jpeg,
      // Sin EXIF: es una foto que se le manda a otra persona y ahí viaja el GPS.
      keepExif: false,
    );
    return out.isEmpty ? null : out;
  } catch (_) {
    // Que el sistema tampoco pueda (o que no haya canal nativo, como en los
    // tests) no es un caso especial: es el mismo "no se puede leer esta foto".
    return null;
  }
}

/// Texto único del "no se puede leer esta foto".
///
/// Constante y no literal suelto para que la prueba pueda mirar EL mensaje que
/// se enseña de verdad. El anterior ("No se pudo procesar la imagen.") no
/// decía qué pasaba ni qué se podía hacer.
const String chatUnreadableImageMessage =
    'No hemos podido leer esta foto: puede estar dañada o en un formato que no '
    'reconocemos. Prueba con otra o haz una captura de pantalla de esta.';

/// Redimensiona (lado mayor <= [maxSide]), quita el EXIF y re-codifica a JPEG.
///
/// De primer nivel y pública a propósito: `ChatService` necesita Functions y
/// Storage reales, así que dentro de la clase esto no se podía probar con bytes
/// de verdad.
Future<ProcessedChatImage> processChatImageBytes(
  Uint8List bytes, {
  required ChatImageTranscoder transcode,
  int maxSide = kMaxChatImageDimension,
}) async {
  img.Image? decoded = _decodeChatImage(bytes);
  if (decoded == null) {
    // Segundo intento con el decodificador del SISTEMA. El paquete `image` de
    // Dart no sabe leer HEIC/HEIF ni AVIF, y por aquí sí pueden llegar: en
    // Android, `image_picker` devuelve el fichero ORIGINAL sin tocar cuando
    // BitmapFactory no supo abrirlo (ImageResizer.resizeImageIfNeeded), que es
    // lo que pasa con un HEIC recibido por WhatsApp o Drive. Es el mismo fallo
    // que rompía las historias, y aquí acababa en "No se pudo procesar la
    // imagen." sin salida posible.
    final Uint8List? converted =
        await transcode(bytes, maxSide);
    if (converted != null) decoded = _decodeChatImage(converted);
  }
  if (decoded == null) {
    throw const ChatServiceException(chatUnreadableImageMessage);
  }

  // `bakeOrientation` antes de nada: al vaciar el EXIF más abajo se pierde la
  // etiqueta de orientación, así que hay que dejar los píxeles ya derechos o
  // la foto llega girada. En Android pasa de verdad: `image_picker` entrega
  // los píxeles sin rotar y la orientación solo en la etiqueta.
  img.Image out = img.bakeOrientation(decoded);
  final int longest = out.width > out.height ? out.width : out.height;
  if (longest > maxSide) {
    // `interpolation` explícito: `copyResize` usa `nearest` por defecto, que
    // al reducir tira filas y columnas sin promediar y deja dentado y moiré.
    out = out.width >= out.height
        ? img.copyResize(
            out,
            width: maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            out,
            height: maxSide,
            interpolation: img.Interpolation.average,
          );
  }
  // Fuera los metadatos. Re-codificar NO los quita por sí solo: `encodeJpg`
  // vuelve a escribir el EXIF de la imagen decodificada, y el que trae una
  // foto del carrete incluye las coordenadas GPS de dónde se hizo. Mandársela
  // a alguien no puede ser mandarle también dónde vives.
  out.exif = img.ExifData();
  final Uint8List jpeg = Uint8List.fromList(img.encodeJpg(out, quality: 80));
  return ProcessedChatImage(bytes: jpeg, width: out.width, height: out.height);
}

/// Decodifica sin morir en el intento.
///
/// `decodeImage` no siempre devuelve null cuando no puede: con datos
/// truncados, los decodificadores de PNG, JPEG y TIFF LANZAN ImageException.
img.Image? _decodeChatImage(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

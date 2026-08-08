/// Errores de historias que ya vienen con un texto pensado para la persona.
///
/// POR QUÉ existe: publicar fallaba enseñando literalmente
/// `StoryServiceException(null): No se pudo procesar la imagen`, porque la
/// pantalla interpolaba el error (`'... $error'`) y eso llama a `toString()`,
/// que incluye el nombre de la clase y un código nulo. La persona veía un
/// volcado interno que no dice qué pasa ni qué puede hacer.
library;

/// Excepción cuyo [message] se le puede enseñar a la persona tal cual.
///
/// Es un marcador a propósito: la pantalla no tiene que conocer cada tipo de
/// error de historias, solo si el error trae texto presentable o no.
abstract interface class StoryUserFacingError {
  String get message;
}

/// Qué se le dice a la persona cuando falla publicar.
///
/// Si el error trae texto propio se enseña ese (dice qué ha pasado y qué hacer).
/// Si no, se enseña algo genérico pero accionable en vez del volcado del objeto:
/// un `FirebaseException` o un fallo de red no tienen por qué acabar en pantalla
/// con su nombre de clase.
String storyPublishFailureMessage(Object error) {
  if (error is StoryUserFacingError && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return 'No hemos podido publicar tu historia. Revisa tu conexión y vuelve a '
      'intentarlo.';
}

/// Qué se le dice a la persona cuando falla COGER el medio del carrete.
///
/// Va aparte de [storyPublishFailureMessage] porque aquí todavía no se ha subido
/// nada: hablarle de publicar (y de su conexión) cuando lo que ha fallado es
/// abrir el fichero manda a mirar donde no es.
String storyMediaFailureMessage(Object error) {
  if (error is StoryUserFacingError && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return 'No hemos podido abrir esa foto. Vuelve a intentarlo o elige otra.';
}

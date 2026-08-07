/// Normas del feed en vivo que se muestran ANTES de encender la cámara.
///
/// PORQUÉ están en dominio y no escritas a mano en el widget:
/// 1. La app ya fue rechazada por Apple por la guideline 1.2 (contenido
///    generado por usuarios). El requisito no es "que haya un aviso", es que el
///    usuario sepa QUÉ está prohibido, QUE se le va a analizar el vídeo y QUÉ
///    consecuencias tiene, y que lo sepa antes de emitir. Un texto suelto
///    dentro de un `Column` se pierde en el primer rediseño; una lista tipada
///    se puede cubrir con un test.
/// 2. Los plazos de la sanción salen de [LiveConstants], que es el mismo
///    contrato que aplica el backend. Escribir "24 horas" a mano en la pantalla
///    garantizaba que el día que cambie la constante el aviso mienta.
library;

import 'live_constants.dart';

/// Identificador estable de cada norma. La presentación lo usa para elegir el
/// icono y los tests para comprobar que ninguna desaparece.
enum LiveRuleId {
  /// Nada de desnudos ni contenido sexual.
  nudity,

  /// Los fotogramas se analizan automáticamente.
  automatedReview,

  /// Escalera de sanciones (aviso → bloqueo temporal → permanente).
  sanctions,

  /// Se puede reportar en cualquier momento, también al terminar.
  reporting,

  /// Qué pasa con el vídeo (peer to peer, no se graba) y por qué hacen falta
  /// cámara y micrófono.
  privacy,
}

/// Una norma: titular corto + explicación.
class LiveRule {
  const LiveRule(this.id, this.title, this.body);

  final LiveRuleId id;
  final String title;
  final String body;
}

/// Catálogo de normas, en el orden en que se muestran.
///
/// El orden NO es decorativo: lo prohibido va primero porque es lo que la
/// mayoría no leerá entero.
class LiveRules {
  const LiveRules._();

  static List<LiveRule> get all => <LiveRule>[
        const LiveRule(
          LiveRuleId.nudity,
          'Nada de desnudos ni contenido sexual',
          'Ni desnudos, ni ropa interior, ni actos sexuales, ni gestos '
              'explícitos. Tampoco violencia, drogas ni menores en cámara. '
              'Es una conversación, no un espectáculo.',
        ),
        const LiveRule(
          LiveRuleId.automatedReview,
          'Analizamos fotogramas automáticamente',
          'Durante la llamada se capturan imágenes cada pocos segundos y las '
              'revisa un sistema automático de detección de contenido '
              'explícito. No las guardamos ni las ve nadie del equipo salvo '
              'que haya una denuncia.',
        ),
        LiveRule(
          LiveRuleId.sanctions,
          'Qué pasa si incumples',
          'A la primera cortamos la sesión y te avisamos. A la segunda '
              'pierdes el directo $_blockHours horas. A la '
              '${LiveConstants.maxStrikes}.ª pierdes el acceso al directo de '
              'forma permanente y tu caso pasa a revisión del equipo. El resto '
              'de la app sigue funcionando.',
        ),
        const LiveRule(
          LiveRuleId.reporting,
          'Puedes denunciar cuando quieras',
          'Tienes el botón de reportar visible durante toda la llamada y '
              'también después, en la pantalla final. Si alguien te enseña '
              'algo y cuelga, sigues pudiendo denunciarlo.',
        ),
        const LiveRule(
          LiveRuleId.privacy,
          'Necesitamos cámara y micrófono',
          'El vídeo viaja directo entre los dos móviles: no pasa por nuestros '
              'servidores, no se graba y no se puede recuperar después. Sin '
              'cámara ni micrófono no hay directo posible.',
        ),
      ];

  static int get _blockHours => LiveConstants.strikeBlock.inHours;
}

/// ¿Ha aceptado el usuario las normas en esta ejecución de la app?
///
/// PORQUÉ solo en memoria y no en `users/{uid}`: añadir una clave de primer
/// nivel al documento del usuario obliga a tocar `allowedTopLevelKeys()` en
/// firestore.rules, y una clave no declarada hace que se RECHACE la escritura
/// entera (así se rompió el onboarding una vez). Para un aviso que cuesta dos
/// segundos leer no compensa el riesgo: se vuelve a mostrar en cada arranque,
/// que además es lo más defendible de cara a revisión.
///
/// Dentro de la misma ejecución sí se recuerda, para que "buscar a otra
/// persona" no obligue a releerlo entre llamada y llamada.
class LiveRulesConsent {
  const LiveRulesConsent._();

  static bool _accepted = false;

  static bool get accepted => _accepted;

  static void accept() => _accepted = true;

  /// Solo para tests: devuelve el consentimiento a su estado de arranque.
  static void reset() => _accepted = false;
}

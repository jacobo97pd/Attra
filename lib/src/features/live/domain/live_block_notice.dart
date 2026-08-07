/// Por qué esta persona no puede entrar al directo, en términos que la UI
/// pueda explicar.
///
/// PORQUÉ existe: el backend rechaza a los sancionados con un
/// `permission-denied` (`assertLiveNotBlocked`), y la pantalla estaba pintando
/// el `message` crudo de esa excepción. Un veto es una decisión con
/// consecuencias distintas según sea temporal o permanente —en un caso hay que
/// esperar, en el otro no hay nada que esperar— y eso no se puede deducir de un
/// string de error. Este tipo separa "qué sanción es" de "cómo se cuenta".
library;

import 'live_strikes.dart';

class LiveBlockNotice {
  const LiveBlockNotice({required this.permanent, this.until});

  /// Bloqueo definitivo: solo lo levanta moderación. No hay cuenta atrás que
  /// mostrar, y ofrecer un "reintentar" sería engañar.
  final bool permanent;

  /// Fin del bloqueo temporal. `null` con [permanent] a `true`, y también
  /// cuando sabemos que hay veto pero no su duración (ver [unknown]).
  final DateTime? until;

  bool get temporary => !permanent;

  /// Sabemos que hay veto pero no de qué tipo: el backend nos ha cerrado la
  /// puerta y el documento de sanciones no era legible. Se cuenta en neutro,
  /// sin prometer un plazo que no conocemos.
  bool get durationUnknown => !permanent && until == null;

  /// Lo que queda de bloqueo temporal ([Duration.zero] si ya venció).
  Duration remaining(DateTime now) {
    final DateTime? end = until;
    if (permanent || end == null) return Duration.zero;
    final Duration left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Deriva el aviso de las sanciones leídas. Devuelve `null` si NO hay veto:
  /// así quien llama no puede pintar por error una pantalla de bloqueo a
  /// alguien que solo tiene un aviso.
  static LiveBlockNotice? fromStrikes(LiveStrikes strikes, DateTime now) {
    if (!strikes.isBlockedAt(now)) return null;
    return LiveBlockNotice(
      permanent: strikes.permanentlyBlocked,
      until: strikes.permanentlyBlocked ? null : strikes.blockedUntil,
    );
  }

  /// Veto confirmado por el backend del que no conocemos el detalle.
  static const LiveBlockNotice unknown = LiveBlockNotice(permanent: false);
}

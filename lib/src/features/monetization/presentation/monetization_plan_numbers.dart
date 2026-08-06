import '../domain/monetization_feature_flags.dart';
import '../domain/subscription_tier.dart';

/// Los NÚMEROS de la propuesta comercial (likes/día, Attras/mes, Boosts/mes y
/// cuánto cuesta un Superboost) tal y como los tiene que contar la UI.
///
/// Por qué existe, si los flags ya saben responder por tier:
/// - Antes los topes vivían hardcodeados en `EntitlementController`
///   (`freeDailyLikes = 25`, `expandedDailyLikes = 100`). Cambiar el producto
///   obligaba a publicar versión, y el paywall podía acabar anunciando un número
///   distinto del que aplicaba el servidor: eso es publicidad engañosa.
/// - Los valores vienen de un documento remoto que edita una persona. Un 0 mal
///   puesto en `free_daily_likes` dejaría a todo el mundo sin poder dar like, y
///   un negativo en un grant pintaría "-2 Attras al mes" en el paywall. Aquí se
///   filtran esos valores imposibles antes de que lleguen a la pantalla.
///
/// El cálculo por tier NO se repite: se delega en [MonetizationFeatureFlags],
/// que es quien manda. Esto es solo la capa de "y cómo se lo enseño al usuario".
class MonetizationPlanNumbers {
  const MonetizationPlanNumbers([
    this.flags = const MonetizationFeatureFlags(),
  ]);

  final MonetizationFeatureFlags flags;

  /// Valor de "sin tope" que ya usaba `EntitlementController.dailyLikeLimit`.
  static const int unlimited = -1;

  // Últimos valores buenos conocidos (los del contrato). Solo se usan cuando el
  // flag remoto trae algo imposible en un campo que NO puede ser cero.
  static const int defaultFreeDailyLikes = 25;
  static const int defaultPlusDailyLikes = 100;
  static const int defaultSuperboostCostBoosts = 3;

  /// Attras incluidos al mes en [tier]. Free ya no es 0: recibe
  /// `freeMonthlyAttras`, que es el gancho de conversión.
  int monthlyAttrasFor(SubscriptionTier tier) =>
      _atLeastZero(flags.monthlyAttrasForTier(tier));

  /// Boosts incluidos al mes en [tier]. Una sola moneda: ese saldo se reparte
  /// entre Boosts de 30 min (1 cada uno) y Superboosts de 24 h
  /// ([superboostCostBoosts] cada uno).
  int monthlyBoostsFor(SubscriptionTier tier) =>
      _atLeastZero(flags.monthlyBoostsForTier(tier));

  /// Likes diarios de [tier]. [unlimited] (-1) = sin tope.
  int dailyLikesFor(SubscriptionTier tier) {
    final int value = flags.dailyLikesForTier(tier);
    if (value == unlimited) return unlimited;
    // Un 0 o un negativo aquí no es "ilimitado": es una errata que dejaría al
    // usuario sin dar likes. Se cae al valor del contrato.
    if (value > 0) return value;
    return tier == SubscriptionTier.free
        ? defaultFreeDailyLikes
        : defaultPlusDailyLikes;
  }

  /// Cuántos Boosts del saldo cuesta un Superboost (24 h). Antes costaba lo
  /// mismo que el Boost de 30 min, así que el producto caro salía regalado.
  int get superboostCostBoosts {
    final int cost = flags.superboostCostBoosts;
    return cost > 0 ? cost : defaultSuperboostCostBoosts;
  }

  static int _atLeastZero(int value) => value < 0 ? 0 : value;
}

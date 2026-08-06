import 'package:flutter/foundation.dart';

import '../../auth/domain/app_user.dart';
import '../../match/domain/match_journey_gating.dart';
import '../data/entitlement_service.dart';
import '../data/feature_flag_service.dart';
import '../domain/monetization_feature_flags.dart';
import '../domain/premium_feature.dart';
import '../domain/subscription_tier.dart';
import '../domain/user_entitlements.dart';
import 'monetization_plan_numbers.dart';

/// Estado de monetizacion de la sesion actual, combinando la fuente
/// autoritativa (`userEntitlements`, escrita por backend) con los feature flags
/// remotos y el consentimiento IA del usuario.
///
/// El cliente SOLO lee. Ninguna ruta aqui concede tier ni saldo.
class EntitlementController extends ChangeNotifier {
  EntitlementController({
    required EntitlementService entitlementService,
    required FeatureFlagService featureFlagService,
    required String uid,
    AppUser? user,
  })  : _entitlementService = entitlementService,
        _featureFlagService = featureFlagService,
        _uid = uid,
        _user = user,
        _entitlements = UserEntitlements.free(uid: uid);

  final EntitlementService _entitlementService;
  final FeatureFlagService _featureFlagService;
  final String _uid;

  AppUser? _user;
  UserEntitlements _entitlements;
  MonetizationFeatureFlags _flags = const MonetizationFeatureFlags();
  bool _loading = true;

  bool get isLoading => _loading;
  MonetizationFeatureFlags get flags => _flags;
  UserEntitlements get entitlements => _entitlements;

  /// Números de la propuesta (likes/día, Attras/mes, Boosts/mes, coste del
  /// Superboost) leídos de los flags vigentes. La UI que necesite comparar
  /// planes (paywall) puede pedirlo aquí en vez de escribir cifras a mano.
  MonetizationPlanNumbers get planNumbers => MonetizationPlanNumbers(_flags);

  /// Attra Spark habilitado por flag remoto (`spark_enabled`). No depende del
  /// tier: es gratis para todos. Si es false, el juego no se ofrece en ningún
  /// sitio y la app va igual que siempre.
  bool get sparkEnabled => _flags.sparkEnabled;

  /// Límites del Match Journey según el tier REAL (Fase 10). Defaults seguros;
  /// nunca desbloquea Pro sin entitlement. Punto único de consulta para gating.
  JourneyLimits get journeyLimits => MatchJourneyPolicy.forTier(tier);

  /// Saldo de Attras (espejo de solo-lectura desde el doc de usuario; la
  /// fuente transaccional autoritativa es `attraWallets`, ver Fase 2).
  int get attrasBalance => _user?.attrasBalance ?? 0;

  bool get aiVisualConsent => _user?.aiVisualConsent ?? false;

  SubscriptionTier get tier => _entitlements.effectiveTierAt(DateTime.now());

  /// True si el tier efectivo es Plus o superior (Plus/Premium/Pro) y los flags
  /// lo habilitan. Lo consume el feed para gatear los comentarios (función Plus).
  bool get isPlusActive {
    final SubscriptionTier effective = tier;
    return effective.atLeast(SubscriptionTier.plus) &&
        _flags.isTierEnabled(effective);
  }

  /// True si el tier efectivo es Premium o superior y los flags lo habilitan.
  /// Lo consume el modulo de ajustes para los toggles Premium.
  bool get isPremiumActive {
    final SubscriptionTier effective = tier;
    return effective.atLeast(SubscriptionTier.premium) &&
        _flags.isTierEnabled(effective);
  }

  bool get isProActive {
    final SubscriptionTier effective = tier;
    return effective.atLeast(SubscriptionTier.pro) &&
        _flags.isTierEnabled(effective);
  }

  /// Gating central: combina tier efectivo + flags + consentimiento IA.
  bool hasFeature(PremiumFeature feature) {
    return _entitlements.hasFeature(
      feature,
      flags: _flags,
      aiVisualConsent: aiVisualConsent,
    );
  }

  // --- GATES CENTRALIZADOS (única fuente de verdad para las pantallas) ---
  // Las pantallas NO deben mirar el tier directamente: usan estos getters.

  /// Límite diario de likes para Free (alineado con backend FREE_DAILY_LIKES).
  ///
  /// Ya NO es el valor que se aplica: el efectivo sale del flag
  /// `freeDailyLikes` (ver [dailyLikeLimit]). Se queda como red de seguridad
  /// para cuando el flag remoto trae un valor imposible.
  static const int freeDailyLikes =
      MonetizationPlanNumbers.defaultFreeDailyLikes;

  /// Límite ampliado para quien tiene `expandedLikes` pero no ilimitado (Plus).
  /// Igual que el anterior: el efectivo sale del flag `plusDailyLikes`.
  static const int expandedDailyLikes =
      MonetizationPlanNumbers.defaultPlusDailyLikes;

  bool get canSeeAllLikes => hasFeature(PremiumFeature.seeAllLikes);
  bool get canUseAdvancedFilters =>
      hasFeature(PremiumFeature.plusFilters) ||
      hasFeature(PremiumFeature.advancedDeclaredFilters);
  bool get canCommentOnLike => isPlusActive;
  bool get canUseIncognito => hasFeature(PremiumFeature.incognitoMode);

  /// Modo viajes (Plus/Pro): cambiar tu ubicación para ver el feed de otra parte
  /// del mundo y aparecer allí "de viaje".
  bool get canUseTravelMode => hasFeature(PremiumFeature.travelMode);

  /// IA visual (solo Pro + consentimiento + flags). hasFeature ya exige consent.
  bool get canUseAiVisualMatching => hasFeature(PremiumFeature.aiVisualEngine);
  bool get canUsePriorityLikes => hasFeature(PremiumFeature.discoveryPriority);
  bool get canUseProfileInsights => hasFeature(PremiumFeature.aiExplanations);

  /// Likes diarios permitidos. -1 = ilimitado.
  ///
  /// El número sale de los flags, no del binario: si mañana Producto cambia
  /// `plusDailyLikes`, la app aplica el nuevo tope sin publicar versión y el
  /// paywall sigue diciendo la verdad. Se decide por FEATURE (no por tier)
  /// porque quien manda es el entitlement: `unlimitedLikes` gana a
  /// `expandedLikes`, y quien no tenga ninguna de las dos va con el tope Free.
  int get dailyLikeLimit {
    final MonetizationPlanNumbers numbers = planNumbers;
    if (hasFeature(PremiumFeature.unlimitedLikes)) {
      return MonetizationPlanNumbers.unlimited;
    }
    if (hasFeature(PremiumFeature.expandedLikes)) {
      return numbers.dailyLikesFor(SubscriptionTier.plus);
    }
    return numbers.dailyLikesFor(SubscriptionTier.free);
  }

  /// Attras incluidos al mes en el tier actual. Free ya NO es 0: recibe
  /// `freeMonthlyAttras` (1 por defecto), que es el gancho de conversión.
  int get monthlyIncludedAttras => planNumbers.monthlyAttrasFor(tier);

  /// Boosts incluidos al mes en el tier actual. `PremiumFeature.monthlyBoost`
  /// se anunciaba desde siempre pero no concedía nada; el grant lo hace el
  /// backend y aquí solo se expone el número para poder contarlo bien.
  int get monthlyIncludedBoosts => planNumbers.monthlyBoostsFor(tier);

  /// Cuántos Boosts del saldo cuesta activar un Superboost (24 h). Lo consume
  /// la tienda de Boosts para enseñar el precio ANTES de gastarlo.
  int get superboostCostBoosts => planNumbers.superboostCostBoosts;

  /// Sin anuncios: cualquier plan de pago. `remove_ads_forever` (consumible)
  /// NO concede Plus/Pro; si se compra por separado, se sumaría aquí en el
  /// futuro, pero por sí solo no desbloquea features de plan.
  bool get hasNoAds => tier.isPaid;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _entitlementService.getEntitlements(_uid),
        _featureFlagService.fetchFlags(),
      ]);
      _entitlements = results[0] as UserEntitlements;
      _flags = results[1] as MonetizationFeatureFlags;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Attra][Entitlements] load fallo: $error');
      }
      // Ante fallo, nos quedamos en free + defaults: nunca conceder de mas.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Actualiza el AppUser cacheado (consent/saldo espejo) cuando cambia la
  /// sesion, sin recargar entitlements de red.
  void updateUser(AppUser? user) {
    if (identical(_user, user)) return;
    _user = user;
    notifyListeners();
  }
}

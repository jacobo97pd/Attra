import '../domain/subscription_tier.dart';

/// Resultado de verificar una compra contra el backend.
class PurchaseVerificationResult {
  const PurchaseVerificationResult({
    required this.success,
    this.grantedTier,
    this.grantedAttras = 0,
    this.error,
  });

  const PurchaseVerificationResult.failure(String message)
      : success = false,
        grantedTier = null,
        grantedAttras = 0,
        error = message;

  final bool success;
  final SubscriptionTier? grantedTier;
  final int grantedAttras;
  final String? error;
}

/// Contrato de verificacion de compras (App Store / Play Store).
///
/// REGLA CRITICA: la verificacion es SIEMPRE server-side. El cliente nunca
/// concede tier ni saldo; solo envia el recibo para que el backend lo valide y
/// escriba `userEntitlements`/`attraWallets` con privilegios de admin.
///
/// La implementacion real (Cloud Function `verifyPurchase`) llega en la Fase 4.
abstract class PurchaseVerificationService {
  Future<PurchaseVerificationResult> verifyPurchase({
    required String platform, // 'app_store' | 'play_store'
    required String productId,
    required String purchaseToken,
  });
}

/// Placeholder de Fase 1: aun no hay Cloud Function de verificacion. Falla de
/// forma explicita para que ninguna ruta de compra conceda nada por error.
class UnavailablePurchaseVerificationService
    implements PurchaseVerificationService {
  const UnavailablePurchaseVerificationService();

  @override
  Future<PurchaseVerificationResult> verifyPurchase({
    required String platform,
    required String productId,
    required String purchaseToken,
  }) async {
    return const PurchaseVerificationResult.failure(
      'La verificacion de compras no esta disponible todavia (Fase 4).',
    );
  }
}

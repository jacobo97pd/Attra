import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/attra_buttons.dart';
import '../data/ads_service.dart';

/// Card de anuncio NATIVO en el feed (estilo Tinder). Plantilla de AdMob
/// estilada con los colores de marca + etiqueta "Patrocinado" (Play Store exige
/// que NO parezca un perfil real). Si el anuncio falla al cargar, se auto-salta
/// (llama a [onContinue]) para no bloquear el feed.
class FeedNativeAdCard extends StatefulWidget {
  const FeedNativeAdCard({super.key, required this.onContinue});

  /// Continúa al siguiente perfil (al pulsar "Siguiente" o si el ad falla).
  final VoidCallback onContinue;

  @override
  State<FeedNativeAdCard> createState() => _FeedNativeAdCardState();
}

class _FeedNativeAdCardState extends State<FeedNativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (!AdsService.instance.supported) {
      // En web/desktop no hay AdMob: salta directamente.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onContinue());
      return;
    }
    _ad = NativeAd(
      adUnitId: AdsService.instance.nativeAdUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: AppColors.surface,
        cornerRadius: 18,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: AppColors.attraRed,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          style: NativeTemplateFontStyle.bold,
          size: 16,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.textSecondary,
          backgroundColor: AppColors.surface,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.textMuted,
          backgroundColor: AppColors.surface,
          size: 11,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          ad.dispose();
          if (!mounted) return;
          setState(() => _failed = true);
          // Si no hay anuncio, no mostramos card rota: continuamos al perfil.
          WidgetsBinding.instance
              .addPostFrameCallback((_) => widget.onContinue());
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        children: <Widget>[
          // Cabecera: deja claro que es publicidad (política Play Store).
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(color: AppColors.surfaceLine),
                ),
                child: Text('Patrocinado',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11)),
              ),
              const Spacer(),
              Text('Anuncio',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          // El anuncio nativo (o placeholder mientras carga).
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: (_loaded && _ad != null && !_failed)
                  ? AdWidget(ad: _ad!)
                  : Container(
                      color: AppColors.surface,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                          color: AppColors.attraRed),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          AttraGhostButton(
            label: 'Siguiente',
            onPressed: widget.onContinue,
          ),
        ],
      ),
    );
  }
}

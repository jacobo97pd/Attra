import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_buttons.dart';
import '../../../widgets/attra_image.dart';
import '../../spark/data/spark_service.dart';
import '../../spark/presentation/spark_game_screen.dart';
import '../domain/like.dart';

/// Todo lo necesario para ofrecer Attra Spark desde la pantalla de match sin que
/// quien la abre tenga que repetir el flujo (invitar + abrir la sala).
///
/// Qué fallaba: la misma pantalla de match ofrecía "jugar 5 minutos" cuando
/// venías de Likes recibidos (que sí implementaba el flujo) y no lo ofrecía
/// cuando venías del feed, así que el juego aparecía o desaparecía según por
/// dónde hubieras hecho match.
class MatchSparkOffer {
  const MatchSparkOffer({
    required this.service,
    required this.matchId,
    required this.currentUid,
    required this.otherUid,
    required this.otherName,
    this.onOpenChat,
  });

  final SparkService service;

  /// Id del match/chat (Spark usa el mismo id determinista).
  final String matchId;
  final String currentUid;
  final String otherUid;
  final String otherName;

  /// Abre el chat normal al terminar o salir de la partida.
  final VoidCallback? onOpenChat;

  bool get isUsable =>
      matchId.isNotEmpty && currentUid.isNotEmpty && otherUid.isNotEmpty;
}

/// Pantalla "¡Es un match!" con los colores corporativos de Attra: dos fotos
/// circulares con halo coral, intereses en común y CTAs (enviar mensaje / seguir
/// viendo). Backward compatible: mantiene `showMatchCreatedDialog`.
Future<void> showMatchCreatedDialog(
  BuildContext context, {
  required String name,
  required String? photoUrl,
  required bool hasAttra,
  String? currentUserPhotoUrl,
  List<String> sharedInterests = const <String>[],
  String? originComment,
  String? originPhotoUrl,
  LikeTargetType? originType,
  VoidCallback? onOpenChat,
  VoidCallback? onPlaySpark,
  MatchSparkOffer? sparkOffer,
  Future<void> Function(String text)? onSendFirstMessage,
}) {
  for (final String? url in <String?>[photoUrl, currentUserPhotoUrl]) {
    AttraImage.precache(context, url);
  }
  // Transición rápida tipo "pop" (fade + escala) en vez del slide lento.
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, __, ___) => _MatchCelebrationScreen(
      name: name,
      photoUrl: photoUrl,
      hasAttra: hasAttra,
      currentUserPhotoUrl: currentUserPhotoUrl,
      sharedInterests: sharedInterests,
      onOpenChat: onOpenChat,
      onPlaySpark: onPlaySpark,
      sparkOffer: sparkOffer,
    ),
    transitionsBuilder: (_, Animation<double> animation, __, Widget child) {
      final Animation<double> curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  ));
}

class _MatchCelebrationScreen extends StatelessWidget {
  const _MatchCelebrationScreen({
    required this.name,
    required this.photoUrl,
    required this.hasAttra,
    this.currentUserPhotoUrl,
    this.sharedInterests = const <String>[],
    this.onOpenChat,
    this.onPlaySpark,
    this.sparkOffer,
  });

  final String name;
  final String? photoUrl;
  final bool hasAttra;
  final String? currentUserPhotoUrl;
  final List<String> sharedInterests;
  final VoidCallback? onOpenChat;
  final VoidCallback? onPlaySpark;
  final MatchSparkOffer? sparkOffer;

  void _close(BuildContext context) => Navigator.of(context).maybePop();

  /// Invita a Spark y abre la sala reemplazando esta pantalla (al salir del
  /// juego se vuelve a donde estabas, no a la celebración del match).
  Future<void> _startSpark(BuildContext context, MatchSparkOffer offer) async {
    final NavigatorState nav = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final String sessionId = await offer.service.invite(
        matchId: offer.matchId,
        hostUid: offer.currentUid,
        guestUid: offer.otherUid,
      );
      if (!nav.mounted) return;
      await nav.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => SparkGameScreen(
          service: offer.service,
          matchId: offer.matchId,
          sessionId: sessionId,
          currentUid: offer.currentUid,
          otherName: offer.otherName,
          onOpenChat: offer.onOpenChat,
        ),
      ));
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo iniciar Attra Spark.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> interests = sharedInterests
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .map(_capitalize)
        .toList(growable: false);
    final MatchSparkOffer? offer = sparkOffer;
    final VoidCallback? playSpark = onPlaySpark != null
        ? () {
            _close(context);
            onPlaySpark!();
          }
        : (offer != null && offer.isUsable)
            ? () => _startSpark(context, offer)
            : null;

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: <Widget>[
              const Spacer(flex: 2),
              // Corazones.
              const _HeartsTop(),
              const SizedBox(height: 14),
              // Título "¡Es un match!".
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.headlineMedium?.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w900),
                  children: const <TextSpan>[
                    TextSpan(text: '¡Es un '),
                    TextSpan(
                        text: 'match!',
                        style: TextStyle(color: AppColors.attraRed)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('A ti y a $name les gusta mutuamente',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.textSecondary)),
              const SizedBox(height: 28),
              // Fotos circulares con halo + badge de corazón.
              _MatchPhotos(
                currentUserPhotoUrl: currentUserPhotoUrl,
                matchedUserPhotoUrl: photoUrl,
                matchedName: name,
                hasAttra: hasAttra,
              ),
              const SizedBox(height: 28),
              // Info rows.
              if (interests.isNotEmpty)
                _InfoRow(
                  icon: Icons.favorite_rounded,
                  title:
                      'Tienen ${interests.length} ${interests.length == 1 ? "interés" : "intereses"} en común',
                  subtitle: _joinNatural(interests),
                ),
              if (interests.isNotEmpty) const SizedBox(height: 14),
              const _InfoRow(
                icon: Icons.chat_bubble_rounded,
                title: 'Listos para comenzar a chatear',
                subtitle: 'Conózcanse mejor y conecten 👋',
              ),
              const Spacer(flex: 3),
              // CTAs.
              AttraPrimaryButton(
                label: 'Enviar mensaje',
                icon: Icons.chat_bubble_rounded,
                onPressed: () {
                  _close(context);
                  onOpenChat?.call();
                },
              ),
              const SizedBox(height: 10),
              // Attra Spark: acepta el callback del llamante (Likes recibidos) o
              // resuelve el flujo aquí mismo con el servicio (feed), para que la
              // oferta sea idéntica vengas de donde vengas.
              if (playSpark != null) ...<Widget>[
                AttraSecondaryButton(
                  label: 'Jugar 5 min para romper el hielo',
                  onPressed: playSpark,
                ),
                const SizedBox(height: 10),
              ],
              AttraGhostButton(
                label: 'Seguir viendo',
                onPressed: () => _close(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _joinNatural(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }
}

class _HeartsTop extends StatelessWidget {
  const _HeartsTop();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          const Icon(Icons.favorite_rounded,
              color: AppColors.attraRed, size: 34),
          Positioned(
            right: MediaQuery.of(context).size.width / 2 - 60,
            top: 0,
            child: const Icon(Icons.favorite_rounded,
                color: AppColors.coral, size: 22),
          ),
        ],
      ),
    );
  }
}

/// Dos fotos CIRCULARES superpuestas con halo coral + badge de corazón.
class _MatchPhotos extends StatelessWidget {
  const _MatchPhotos({
    required this.currentUserPhotoUrl,
    required this.matchedUserPhotoUrl,
    required this.matchedName,
    required this.hasAttra,
  });

  final String? currentUserPhotoUrl;
  final String? matchedUserPhotoUrl;
  final String matchedName;
  final bool hasAttra;

  @override
  Widget build(BuildContext context) {
    const double d = 150;
    const double overlap = 26;
    return SizedBox(
      height: d + 8,
      width: d * 2 - overlap + 8,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            left: 0,
            child: _Bubble(url: currentUserPhotoUrl, fallback: 'Tú', size: d),
          ),
          Positioned(
            right: 0,
            child: _Bubble(
              url: matchedUserPhotoUrl,
              fallback:
                  matchedName.isNotEmpty ? matchedName[0].toUpperCase() : '?',
              size: d,
            ),
          ),
          // Badge de corazón al centro-abajo, entre las dos fotos.
          Positioned(
            bottom: 0,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: AppColors.action),
                border: Border.all(color: context.colors.bg, width: 3),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.attraRed.withValues(alpha: 0.55),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                hasAttra ? Icons.star_rounded : Icons.favorite_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.url, required this.fallback, required this.size});

  final String? url;
  final String fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? u = url?.trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.attraRed, width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.attraRed.withValues(alpha: 0.45),
            blurRadius: 26,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: AttraImage(url: u, fallbackInitial: fallback),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.attraRed.withValues(alpha: 0.14),
          ),
          child: Icon(icon, color: AppColors.attraRed, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: context.colors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

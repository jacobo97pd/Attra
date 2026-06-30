import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

/// Pagina del tutorial: icono en halo, titulo y descripcion.
class _TutorialPage {
  const _TutorialPage({
    required this.icon,
    required this.title,
    required this.body,
    this.accent = AppColors.attraRed,
    this.isWelcome = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  /// La primera pagina muestra el logo ATTRA en vez del icono.
  final bool isWelcome;
}

const List<_TutorialPage> _pages = <_TutorialPage>[
  _TutorialPage(
    icon: Icons.favorite_rounded,
    title: 'Bienvenido a Attra',
    body:
        'Conecta con personas que van en serio. Te ensenamos en 1 minuto como '
        'sacarle el maximo partido.',
    isWelcome: true,
  ),
  _TutorialPage(
    icon: Icons.explore_rounded,
    title: 'Descubre en el feed',
    body: 'Desliza la tarjeta a la derecha o pulsa like para mostrar interes. '
        'Desliza a la izquierda o pulsa pasar para seguir buscando. Desliza '
        'hacia arriba para ver todas las fotos y datos del perfil.',
  ),
  _TutorialPage(
    icon: Icons.star_rounded,
    title: 'Destaca con un Attra',
    body: 'Envia un Attra para que esa persona sepa que te interesa de verdad: '
        'apareceras destacado. Si pasaste a alguien sin querer, vuelve atras '
        'con el boton de deshacer en Plus o Pro.',
    accent: AppColors.gold,
  ),
  _TutorialPage(
    icon: Icons.auto_awesome_motion_rounded,
    title: 'Historias de 24h',
    body:
        'Comparte momentos en video que desaparecen a las 24 horas y mira las '
        'historias de las personas con las que has hecho match.',
  ),
  _TutorialPage(
    icon: Icons.chat_bubble_rounded,
    title: 'Matches y chats',
    body:
        'Cuando hay like mutuo, es un match. Habla en la pestana Chats, rompe '
        'el hielo con prompts y comparte audio, fotos y mas.',
    accent: AppColors.success,
  ),
  _TutorialPage(
    icon: Icons.person_rounded,
    title: 'Tu perfil lo es todo',
    body: 'Anade fotos, audio y video de presentacion, prompts e intereses. '
        'Cuanto mas completo y autentico sea tu perfil, mejores conexiones '
        'tendras.',
  ),
  _TutorialPage(
    icon: Icons.shield_rounded,
    title: 'Privacidad y seguridad',
    body:
        'Tu decides que se ve y con quien. Controla tu privacidad, protege tu '
        'cuenta y gestiona tu consentimiento desde Ajustes.',
    accent: AppColors.nightBlue,
  ),
  _TutorialPage(
    icon: Icons.workspace_premium_rounded,
    title: 'Attra Plus y Pro',
    body:
        'Desbloquea filtros avanzados, descubre quien te ha dado like, usa la '
        'IA visual para encontrar tu tipo y mucho mas con Plus y Pro.',
    accent: AppColors.gold,
  ),
];

/// Tutorial de bienvenida de Attra. Se muestra una vez a usuarios nuevos
/// tras el onboarding y se puede volver a ver desde Ajustes.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  /// Abre el tutorial como pantalla completa.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const TutorialScreen(),
      ),
    );
  }

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isLast ? 0 : 1,
                child: TextButton(
                  onPressed: _isLast ? null : _finish,
                  child: Text(
                    'Saltar',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext context, int i) =>
                    _TutorialPageView(page: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.attraRed
                          : context.colors.surfaceLine,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.attraRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  onPressed: _next,
                  child: Text(
                    _isLast ? 'Empezar a descubrir' : 'Siguiente',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialPageView extends StatelessWidget {
  const _TutorialPageView({required this.page});

  final _TutorialPage page;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  page.accent.withValues(alpha: 0.28),
                  Colors.transparent,
                ],
              ),
            ),
            alignment: Alignment.center,
            child: page.isWelcome
                ? Image.asset(
                    'assets/images/ATTRA.png',
                    height: 56,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  )
                : Icon(page.icon, size: 76, color: page.accent),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.colors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

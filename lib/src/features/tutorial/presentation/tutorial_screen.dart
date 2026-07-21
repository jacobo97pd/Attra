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
        'Haz planes, conoce gente y queda con tranquilidad. Attra no empieza '
        'por "quien te gusta", sino por "que te apetece hacer". Te guiamos en '
        'un minuto.',
    isWelcome: true,
  ),
  _TutorialPage(
    icon: Icons.home_rounded,
    title: 'Inicio: tu punto de partida',
    body:
        'Nada mas entrar veras planes cerca de ti, tus grupos y personas con '
        'tus mismos intereses. Elige una categoria (cafe, cultura, aire libre, '
        'cena, musica...) y empieza por lo que te apetece.',
  ),
  _TutorialPage(
    icon: Icons.explore_rounded,
    title: 'Planes y grupos',
    body:
        'Explora, unete o crea planes y grupos por ciudad e intereses. Ponle '
        'una foto al grupo, invita a gente y quedad en la vida real. Cada grupo '
        'tiene su propio chat.',
    accent: AppColors.success,
  ),
  _TutorialPage(
    icon: Icons.people_rounded,
    title: 'Personas: conoce gente',
    body:
        'Descubre personas compatibles por intereses y zona. En modo citas '
        'puedes dar like o enviar un Attra; en amistad, conectar. Y siempre '
        'tienes el boton diferencial: "Invitar a un plan".',
  ),
  _TutorialPage(
    icon: Icons.tune_rounded,
    title: 'Tu decides que buscas',
    body:
        'Citas, amistad, ambas o grupos y planes. Cambia tu intencion cuando '
        'quieras desde tu perfil: el feed y el lenguaje se adaptan a lo que '
        'buscas en cada momento.',
  ),
  _TutorialPage(
    icon: Icons.chat_bubble_rounded,
    title: 'Chats',
    body:
        'Tus conversaciones 1 a 1 y los chats de tus grupos, todo en un sitio. '
        'La accion principal del chat es "Proponer plan": pasa de hablar a '
        'quedar en un toque. Rompe el hielo con prompts y juegos.',
    accent: AppColors.success,
  ),
  _TutorialPage(
    icon: Icons.star_rounded,
    title: 'Destaca con un Attra',
    body:
        'Envia un Attra para que esa persona sepa que te interesa de verdad: '
        'apareceras destacado. Si pasaste a alguien sin querer, vuelve atras '
        'con deshacer (Plus o Pro).',
    accent: AppColors.gold,
  ),
  _TutorialPage(
    icon: Icons.shield_moon_rounded,
    title: 'Queda con tranquilidad',
    body:
        'Con SafeDate puedes avisar a un contacto de confianza, programar '
        'check-ins durante la cita y tener ayuda a un toque. Tu decides que '
        'compartes y durante cuanto tiempo: la ubicacion nunca se comparte '
        'sola.',
    accent: AppColors.nightBlue,
  ),
  _TutorialPage(
    icon: Icons.person_rounded,
    title: 'Tu perfil lo es todo',
    body:
        'Anade fotos, audio y video de presentacion, prompts e intereses. '
        'Cuanto mas completo y autentico sea tu perfil, mejores planes y '
        'conexiones tendras.',
  ),
  _TutorialPage(
    icon: Icons.lock_rounded,
    title: 'Privacidad y seguridad',
    body:
        'Tu controlas que se ve y con quien. Gestiona tu privacidad, protege '
        'tu cuenta con bloqueo y decide tu consentimiento desde Ajustes.',
    accent: AppColors.nightBlue,
  ),
  _TutorialPage(
    icon: Icons.workspace_premium_rounded,
    title: 'Attra Plus y Pro',
    body:
        'Desbloquea filtros avanzados, descubre quien te ha dado like, usa la '
        'IA para encontrar tu tipo y mucho mas con Plus y Pro. Opcional: la '
        'app funciona genial gratis.',
    accent: AppColors.gold,
  ),
  _TutorialPage(
    icon: Icons.rocket_launch_rounded,
    title: 'Ahora te enseñamos la app',
    body:
        'Ya lo tienes. Pulsa "Empezar" y te haremos un recorrido rapido por '
        'las pestañas para que sepas donde esta cada cosa.',
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

  // Cierre explícito: PopScope(canPop:false) solo bloquea el "atrás" del
  // sistema, no un pop imperativo. Así "Empezar" sí cierra el tutorial.
  void _finish() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    // Obligatorio: no se puede cerrar con "atrás" ni saltar. Solo se avanza.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 12),
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
                      _isLast ? 'Empezar' : 'Siguiente',
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

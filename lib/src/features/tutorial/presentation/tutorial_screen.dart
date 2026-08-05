import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/attra_colors.dart';

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
  final bool isWelcome;
}

const List<_TutorialPage> _pages = <_TutorialPage>[
  _TutorialPage(
    icon: Icons.favorite_rounded,
    title: 'Bienvenido a Attra',
    body:
        'Conoce personas con intención, rompe el hielo con naturalidad y lleva '
        'la conexión a la vida real cuando te apetezca.',
    isWelcome: true,
  ),
  _TutorialPage(
    icon: Icons.explore_rounded,
    title: 'Descubre a tu manera',
    body:
        'Explora perfiles compatibles, revisa quién te ha dado like y elige si '
        'buscas citas, amistad o ambas. Puedes cambiarlo cuando quieras.',
  ),
  _TutorialPage(
    icon: Icons.forum_rounded,
    title: 'Conecta de verdad',
    body: 'Un like puede abrir una conversación. Los prompts, el audio y '
        '«Proponer un plan» te ayudan a pasar del match a algo que apetezca de '
        'verdad.',
    accent: AppColors.success,
  ),
  _TutorialPage(
    icon: Icons.shield_rounded,
    title: 'Tú tienes el control',
    body: 'Decide qué muestras, bloquea o reporta cuando lo necesites y usa '
        'SafeDate al quedar. Tu ubicación nunca se comparte automáticamente.',
    accent: AppColors.nightBlue,
  ),
];

/// Introducción breve a Attra. Se muestra tras el onboarding y se puede volver
/// a abrir desde Ajustes.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

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
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Saltar tutorial'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (int index) => setState(() => _index = index),
                itemBuilder: (BuildContext context, int index) =>
                    _TutorialPageView(
                  page: _pages[index],
                  position: index + 1,
                  total: _pages.length,
                ),
              ),
            ),
            Semantics(
              label: 'Página ${_index + 1} de ${_pages.length}',
              container: true,
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    backgroundColor: AppColors.attraRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  onPressed: _next,
                  child: Text(
                    _isLast ? 'Entrar en Attra' : 'Continuar',
                    textAlign: TextAlign.center,
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
  const _TutorialPageView({
    required this.page,
    required this.position,
    required this.total,
  });

  final _TutorialPage page;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'Paso $position de $total',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                ExcludeSemantics(
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: <Color>[
                          page.accent.withValues(alpha: 0.26),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: page.isWelcome
                        ? Image.asset(
                            'assets/images/ATTRA.png',
                            height: 48,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          )
                        : Icon(page.icon, size: 62, color: page.accent),
                  ),
                ),
                const SizedBox(height: 28),
                Semantics(
                  header: true,
                  child: Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
          ),
        );
      },
    );
  }
}

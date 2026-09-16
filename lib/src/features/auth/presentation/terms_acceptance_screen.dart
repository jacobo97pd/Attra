import 'package:flutter/material.dart';

import '../../../widgets/legal_links_row.dart';

/// Recoge la aceptación de cuentas que conservan una sesión de una versión
/// anterior. No permite acceder a perfiles, chats ni publicar sin aceptarla.
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({
    super.key,
    required this.onAccept,
    required this.onSignOut,
    this.isLoading = false,
    this.errorMessage,
  });

  final VoidCallback onAccept;
  final VoidCallback onSignOut;
  final bool isLoading;
  final String? errorMessage;

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Condiciones de uso')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Antes de continuar en Attra',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  const Text(
                    'Lee las condiciones actualizadas. Attra tiene tolerancia '
                    'cero con el contenido ofensivo y con los usuarios '
                    'abusivos. Puedes denunciar contenido y bloquear usuarios '
                    'desde los menús de perfiles, historias y chats.',
                  ),
                  const SizedBox(height: 16),
                  const AttraLegalLinksRow(alignment: WrapAlignment.start),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    key: const ValueKey<String>('session-terms-checkbox'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _accepted,
                    onChanged: widget.isLoading
                        ? null
                        : (bool? value) =>
                            setState(() => _accepted = value ?? false),
                    title: const Text(
                      'Tengo 18 años o más y acepto las Condiciones de uso '
                      'y el EULA, y he leído la Política de privacidad.',
                    ),
                  ),
                  if (widget.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(widget.errorMessage!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey<String>('session-terms-continue'),
                    onPressed:
                        _accepted && !widget.isLoading ? widget.onAccept : null,
                    child: Text(widget.isLoading ? 'Guardando…' : 'Continuar'),
                  ),
                  TextButton(
                    onPressed: widget.isLoading ? null : widget.onSignOut,
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

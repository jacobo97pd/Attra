import 'package:flutter/material.dart';

import '../../match/data/match_service.dart';
import '../domain/report.dart';

/// Resultado de la hoja de seguridad, para que quien la abre pueda reaccionar
/// (p. ej. sacar del feed a la persona bloqueada).
enum SafetyActionResult { none, reported, blocked }

/// Acciones de seguridad sobre otra persona: REPORTAR contenido objetable y
/// BLOQUEAR usuarios abusivos.
///
/// App Store Guideline 1.2 exige que ambas estén disponibles de forma evidente
/// allí donde se ve contenido de otros usuarios, no solo dentro de un chat con
/// match previo. Por eso este módulo es compartido: feed, perfil y chat usan
/// exactamente el mismo flujo.
class SafetyActions {
  const SafetyActions._();

  /// Hoja con las dos acciones. Devuelve qué ha hecho el usuario.
  static Future<SafetyActionResult> showSheet(
    BuildContext context, {
    required MatchService matchService,
    required String uid,
    required String displayName,
    String? chatId,
    String? messageId,
  }) async {
    if (uid.isEmpty) return SafetyActionResult.none;
    final String name =
        displayName.trim().isEmpty ? 'esta persona' : displayName.trim();

    final _SafetyChoice? choice = await showModalBottomSheet<_SafetyChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const ValueKey<String>('safety-report'),
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Reportar'),
              subtitle: Text('Avisar de contenido o conducta de $name'),
              onTap: () => Navigator.of(sheetContext).pop(_SafetyChoice.report),
            ),
            ListTile(
              key: const ValueKey<String>('safety-block'),
              leading: const Icon(Icons.block),
              title: const Text('Bloquear'),
              subtitle: Text('$name no podrá verte ni escribirte'),
              onTap: () => Navigator.of(sheetContext).pop(_SafetyChoice.block),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !context.mounted) return SafetyActionResult.none;
    switch (choice) {
      case _SafetyChoice.report:
        return report(
          context,
          matchService: matchService,
          uid: uid,
          displayName: name,
          chatId: chatId,
          messageId: messageId,
        );
      case _SafetyChoice.block:
        return block(
          context,
          matchService: matchService,
          uid: uid,
          displayName: name,
        );
    }
  }

  /// Reporte con motivo. Los motivos son los de [ReportReason].
  static Future<SafetyActionResult> report(
    BuildContext context, {
    required MatchService matchService,
    required String uid,
    required String displayName,
    String? chatId,
    String? messageId,
  }) async {
    final ReportReason? reason = await showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '¿Qué ocurre con $displayName?',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            for (final ReportReason r in ReportReason.values)
              ListTile(
                title: Text(r.label),
                onTap: () => Navigator.of(sheetContext).pop(r),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (reason == null || !context.mounted) return SafetyActionResult.none;

    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    try {
      await matchService.reportUser(
        reportedUid: uid,
        reason: reason.wireName,
        chatId: chatId,
        messageId: messageId,
      );
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Gracias. Nuestro equipo lo revisa en menos de 24 horas.',
          ),
        ),
      );
      return SafetyActionResult.reported;
    } on MatchServiceException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
      return SafetyActionResult.none;
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('No se pudo enviar el reporte.')),
      );
      return SafetyActionResult.none;
    }
  }

  /// Bloqueo con confirmación previa.
  static Future<SafetyActionResult> block(
    BuildContext context, {
    required MatchService matchService,
    required String uid,
    required String displayName,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('¿Bloquear a $displayName?'),
        content: const Text(
          'No volveréis a veros en la app ni podréis escribiros. Se cerrará '
          'el match y el chat si los hubiera.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return SafetyActionResult.none;

    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    try {
      await matchService.blockUser(uid);
      messenger?.showSnackBar(
        SnackBar(content: Text('$displayName ha sido bloqueado.')),
      );
      return SafetyActionResult.blocked;
    } on MatchServiceException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
      return SafetyActionResult.none;
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('No se pudo bloquear.')),
      );
      return SafetyActionResult.none;
    }
  }
}

enum _SafetyChoice { report, block }

/// Botón de menú (⋮) con Reportar / Bloquear, para barras superiores.
class SafetyMenuButton extends StatelessWidget {
  const SafetyMenuButton({
    super.key,
    required this.matchService,
    required this.uid,
    required this.displayName,
    this.onResult,
    this.iconColor,
  });

  final MatchService matchService;
  final String uid;
  final String displayName;
  final ValueChanged<SafetyActionResult>? onResult;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SafetyChoice>(
      key: const ValueKey<String>('safety-menu-button'),
      tooltip: 'Seguridad',
      icon: Icon(Icons.more_vert, color: iconColor),
      onSelected: (_SafetyChoice choice) {
        // Sin `await` antes de usar `context`: se lanza el flujo y se notifica
        // el resultado cuando termine.
        final Future<SafetyActionResult> pending = switch (choice) {
          _SafetyChoice.report => SafetyActions.report(
              context,
              matchService: matchService,
              uid: uid,
              displayName: displayName,
            ),
          _SafetyChoice.block => SafetyActions.block(
              context,
              matchService: matchService,
              uid: uid,
              displayName: displayName,
            ),
        };
        pending.then((SafetyActionResult result) => onResult?.call(result));
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_SafetyChoice>>[
        const PopupMenuItem<_SafetyChoice>(
          value: _SafetyChoice.report,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.flag_outlined),
            title: Text('Reportar'),
          ),
        ),
        const PopupMenuItem<_SafetyChoice>(
          value: _SafetyChoice.block,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.block),
            title: Text('Bloquear'),
          ),
        ),
      ],
    );
  }
}

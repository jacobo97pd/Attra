import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../match/data/match_service.dart';
import '../../profile/data/profile_summary_repository.dart';
import '../data/live_service.dart';
import 'live_screen.dart';

/// Punto de entrada al FEED EN VIVO desde la navegación.
///
/// El resto del grafo de servicios se construye en `lib/app.dart` y baja por
/// `SessionController`. El directo se queda fuera de ese grafo A PROPÓSITO:
/// nace apagado por feature flag y con la flag off nada de esto se instancia,
/// así que colgarlo de la sesión significaría abrir listeners de Firestore y
/// mantener un servicio vivo para una función que la inmensa mayoría de las
/// sesiones no va a usar. `instanceFor` devuelve SIEMPRE el mismo singleton
/// para (app, databaseId), de modo que crearlo aquí no abre una segunda
/// conexión ni una segunda caché: es el mismo Firestore que usa el resto de la
/// app.
LiveService buildLiveService() {
  return LiveService(
    // OJO: base de datos CON NOMBRE. Con `FirebaseFirestore.instance` se
    // hablaría con `(default)`, que está vacía, y el directo fallaría en
    // producción sin dar ninguna pista.
    firestore: FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: _firestoreDatabaseId,
    ),
    // Mismas region y despliegue que el resto de callables (functions/).
    functions: FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
}

/// Debe coincidir con el de `lib/app.dart`: si divergen, el directo leería de
/// otra base de datos que el resto de la app.
const String _firestoreDatabaseId = String.fromEnvironment(
  'FIREBASE_FIRESTORE_DATABASE_ID',
  defaultValue: 'attra-database',
);

/// Abre la pantalla del directo.
///
/// [liveService] existe para los tests; en la app se construye aquí mismo.
Future<void> openLiveScreen(
  BuildContext context, {
  required String uid,
  required MatchService matchService,
  ProfileSummaryRepository? profileSummaryRepository,
  LiveService? liveService,
  void Function(String chatId, String peerUid)? onOpenChat,
}) {
  if (uid.isEmpty) return Future<void>.value();
  return Navigator.of(context).push(MaterialPageRoute<void>(
    // `fullscreenDialog`: el directo se abre ENCIMA de la app, no dentro de
    // una pestaña. Es una situación de la que hay que poder salir de un gesto,
    // y además así la barra de navegación no invita a cambiar de pestaña con
    // la cámara encendida.
    fullscreenDialog: true,
    builder: (_) => LiveScreen(
      liveService: liveService ?? buildLiveService(),
      matchService: matchService,
      uid: uid,
      profileSummaryRepository: profileSummaryRepository,
      onOpenChat: onOpenChat,
    ),
  ));
}

/// Acceso al directo desde la cabecera de Descubrir.
///
/// PORQUÉ un botón en Descubrir y NO una quinta pestaña:
/// - Hay cuatro pestañas y la barra ya va justa; una quinta encoge las cuatro
///   que se usan todos los días para meter una función que nace apagada.
/// - La barra se construye con `_HomeDestination.values[index]`: una pestaña
///   condicional desincronizaría el índice del `NavigationBar` con el del enum
///   y al pulsar una se abriría otra. Un dark launch no puede permitirse eso.
/// - Descubrir es el sitio: acaba de convertirse en un muro de historias, o
///   sea, en "gente que no conoces". Hablar con un desconocido en directo es
///   la misma intención, un paso más arriba.
/// - Y al ser una acción de cabecera, apagar la flag la hace desaparecer sin
///   dejar hueco ni mover nada de sitio.
class LiveEntryButton extends StatelessWidget {
  const LiveEntryButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Directo: vídeo con alguien nuevo',
      child: Tooltip(
        message: 'Directo',
        child: InkWell(
          key: const ValueKey<String>('live-entry-button'),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE53935),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Directo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

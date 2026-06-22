// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get navFeed => 'Feed';

  @override
  String get navLikes => 'Likes';

  @override
  String get navChats => 'Chats';

  @override
  String get navProfile => 'Perfil';

  @override
  String get feedTitle => 'Attra';

  @override
  String get feedEmptyTitle => 'No hay más personas por el momento';

  @override
  String get feedEmptyBody =>
      'Cuando entren nuevos perfiles compatibles aparecerán aquí. No volverás a ver a quien ya likeaste o pasaste.';

  @override
  String get feedReload => 'Recargar';

  @override
  String get likesTitle => 'Likes';

  @override
  String get chatsTitle => 'Chats';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get matchTitle => '¡Menudo match!';

  @override
  String get matchSubtitle =>
      'Habéis conectado. Rompe el hielo antes de que se enfríe ✨';

  @override
  String get matchOpenChat => 'Abrir chat';

  @override
  String get matchKeepBrowsing => 'Seguir descubriendo';

  @override
  String get matchSendHint => 'Envía un mensaje…';

  @override
  String get matchSuggestionLabel => 'Apertura sugerida';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonAccept => 'Aceptar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonLogout => 'Cerrar sesión';

  @override
  String get slowDatingTitle => 'Slow Dating';

  @override
  String get slowDatingSubtitle =>
      'Citas con calma: menos perfiles pero más afines a ti.';

  @override
  String get slowDatingActiveTag => 'Activo';

  @override
  String get slowDatingActivate => 'Activar';

  @override
  String get slowDatingNotNow => 'Ahora no';

  @override
  String get slowDatingEnabledToast =>
      'Slow Dating activado. Tu feed irá con calma 🌿';

  @override
  String get slowDatingDisabledToast => 'Slow Dating desactivado.';

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get notificationsMarkRead => 'Marcar leídas';

  @override
  String get notificationsEmptyTitle => 'Sin novedades por ahora';

  @override
  String get notificationsEmptyBody =>
      'Cuando alguien te dé like o te escriba, lo verás aquí 🔔';
}

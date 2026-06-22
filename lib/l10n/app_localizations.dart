import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// Etiqueta de la pestaña de descubrimiento
  ///
  /// In es, this message translates to:
  /// **'Feed'**
  String get navFeed;

  /// No description provided for @navLikes.
  ///
  /// In es, this message translates to:
  /// **'Likes'**
  String get navLikes;

  /// No description provided for @navChats.
  ///
  /// In es, this message translates to:
  /// **'Chats'**
  String get navChats;

  /// No description provided for @navProfile.
  ///
  /// In es, this message translates to:
  /// **'Perfil'**
  String get navProfile;

  /// No description provided for @feedTitle.
  ///
  /// In es, this message translates to:
  /// **'Attra'**
  String get feedTitle;

  /// No description provided for @feedEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'No hay más personas por el momento'**
  String get feedEmptyTitle;

  /// No description provided for @feedEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Cuando entren nuevos perfiles compatibles aparecerán aquí. No volverás a ver a quien ya likeaste o pasaste.'**
  String get feedEmptyBody;

  /// No description provided for @feedReload.
  ///
  /// In es, this message translates to:
  /// **'Recargar'**
  String get feedReload;

  /// No description provided for @likesTitle.
  ///
  /// In es, this message translates to:
  /// **'Likes'**
  String get likesTitle;

  /// No description provided for @chatsTitle.
  ///
  /// In es, this message translates to:
  /// **'Chats'**
  String get chatsTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get settingsTitle;

  /// No description provided for @matchTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Menudo match!'**
  String get matchTitle;

  /// No description provided for @matchSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Habéis conectado. Rompe el hielo antes de que se enfríe ✨'**
  String get matchSubtitle;

  /// No description provided for @matchOpenChat.
  ///
  /// In es, this message translates to:
  /// **'Abrir chat'**
  String get matchOpenChat;

  /// No description provided for @matchKeepBrowsing.
  ///
  /// In es, this message translates to:
  /// **'Seguir descubriendo'**
  String get matchKeepBrowsing;

  /// No description provided for @matchSendHint.
  ///
  /// In es, this message translates to:
  /// **'Envía un mensaje…'**
  String get matchSendHint;

  /// No description provided for @matchSuggestionLabel.
  ///
  /// In es, this message translates to:
  /// **'Apertura sugerida'**
  String get matchSuggestionLabel;

  /// No description provided for @commonCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// No description provided for @commonAccept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get commonAccept;

  /// No description provided for @commonSave.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get commonRetry;

  /// No description provided for @commonLogout.
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get commonLogout;

  /// No description provided for @slowDatingTitle.
  ///
  /// In es, this message translates to:
  /// **'Slow Dating'**
  String get slowDatingTitle;

  /// No description provided for @slowDatingSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Citas con calma: menos perfiles pero más afines a ti.'**
  String get slowDatingSubtitle;

  /// No description provided for @slowDatingActiveTag.
  ///
  /// In es, this message translates to:
  /// **'Activo'**
  String get slowDatingActiveTag;

  /// No description provided for @slowDatingActivate.
  ///
  /// In es, this message translates to:
  /// **'Activar'**
  String get slowDatingActivate;

  /// No description provided for @slowDatingNotNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get slowDatingNotNow;

  /// No description provided for @slowDatingEnabledToast.
  ///
  /// In es, this message translates to:
  /// **'Slow Dating activado. Tu feed irá con calma 🌿'**
  String get slowDatingEnabledToast;

  /// No description provided for @slowDatingDisabledToast.
  ///
  /// In es, this message translates to:
  /// **'Slow Dating desactivado.'**
  String get slowDatingDisabledToast;

  /// No description provided for @notificationsTitle.
  ///
  /// In es, this message translates to:
  /// **'Notificaciones'**
  String get notificationsTitle;

  /// No description provided for @notificationsMarkRead.
  ///
  /// In es, this message translates to:
  /// **'Marcar leídas'**
  String get notificationsMarkRead;

  /// No description provided for @notificationsEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Sin novedades por ahora'**
  String get notificationsEmptyTitle;

  /// No description provided for @notificationsEmptyBody.
  ///
  /// In es, this message translates to:
  /// **'Cuando alguien te dé like o te escriba, lo verás aquí 🔔'**
  String get notificationsEmptyBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

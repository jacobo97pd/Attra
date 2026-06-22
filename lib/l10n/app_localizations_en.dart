// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navFeed => 'Feed';

  @override
  String get navLikes => 'Likes';

  @override
  String get navChats => 'Chats';

  @override
  String get navProfile => 'Profile';

  @override
  String get feedTitle => 'Attra';

  @override
  String get feedEmptyTitle => 'No more people right now';

  @override
  String get feedEmptyBody =>
      'When new compatible profiles show up, they\'ll appear here. You won\'t see anyone you already liked or passed again.';

  @override
  String get feedReload => 'Reload';

  @override
  String get likesTitle => 'Likes';

  @override
  String get chatsTitle => 'Chats';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get matchTitle => 'It\'s a match!';

  @override
  String get matchSubtitle =>
      'You\'ve connected. Break the ice before it cools down ✨';

  @override
  String get matchOpenChat => 'Open chat';

  @override
  String get matchKeepBrowsing => 'Keep browsing';

  @override
  String get matchSendHint => 'Send a message…';

  @override
  String get matchSuggestionLabel => 'Suggested opener';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonAccept => 'Accept';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonLogout => 'Log out';

  @override
  String get slowDatingTitle => 'Slow Dating';

  @override
  String get slowDatingSubtitle =>
      'Dating with calm: fewer profiles but more aligned with you.';

  @override
  String get slowDatingActiveTag => 'On';

  @override
  String get slowDatingActivate => 'Turn on';

  @override
  String get slowDatingNotNow => 'Not now';

  @override
  String get slowDatingEnabledToast =>
      'Slow Dating on. Your feed will take it easy 🌿';

  @override
  String get slowDatingDisabledToast => 'Slow Dating off.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsMarkRead => 'Mark as read';

  @override
  String get notificationsEmptyTitle => 'Nothing new yet';

  @override
  String get notificationsEmptyBody =>
      'When someone likes you or messages you, you\'ll see it here 🔔';
}

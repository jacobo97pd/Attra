import 'package:flutter/material.dart';

/// Resuelve los nombres de icono del catalogo (strings) a [IconData] Material.
/// Mantener el catalogo libre de tipos de Flutter lo hace pilotable desde
/// backend en el futuro sin acoplarlo al cliente.
IconData settingsIcon(String? name) {
  switch (name) {
    case 'manage_accounts':
      return Icons.manage_accounts_outlined;
    case 'visibility':
      return Icons.visibility_outlined;
    case 'notifications':
      return Icons.notifications_outlined;
    case 'location_on':
      return Icons.location_on_outlined;
    case 'shield':
      return Icons.shield_outlined;
    case 'privacy_tip':
      return Icons.privacy_tip_outlined;
    case 'extension':
      return Icons.extension_outlined;
    case 'no_accounts':
      return Icons.no_accounts_outlined;
    case 'download':
      return Icons.download_outlined;
    case 'history':
      return Icons.history;
    case 'manage_history':
      return Icons.manage_history;
    case 'pause_circle':
      return Icons.pause_circle_outline;
    case 'delete_forever':
      return Icons.delete_forever_outlined;
    default:
      return Icons.tune;
  }
}

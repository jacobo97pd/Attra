import 'package:cloud_firestore/cloud_firestore.dart';

/// Contacto de confianza (`users/{uid}/trustedContacts/{id}`). PRIVADO del
/// dueño: nunca visible para otros usuarios ni para el match. Solo se guardan
/// contactos seleccionados explícitamente (no la agenda del dispositivo).
class TrustedContact {
  const TrustedContact({
    required this.id,
    required this.userId,
    required this.displayName,
    this.phone,
    this.email,
    this.isPrimary = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? phone;
  final String? email;
  final bool isPrimary;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasChannel =>
      (phone?.trim().isNotEmpty ?? false) || (email?.trim().isNotEmpty ?? false);

  factory TrustedContact.fromMap(String id, Map<String, dynamic> map) {
    return TrustedContact(
      id: id,
      userId: (map['userId'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      phone: (map['phone'] as String?)?.trim().isNotEmpty == true
          ? (map['phone'] as String).trim()
          : null,
      email: (map['email'] as String?)?.trim().isNotEmpty == true
          ? (map['email'] as String).trim()
          : null,
      isPrimary: map['isPrimary'] == true,
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}

/// Validación/normalización de un contacto (pura, testeable). No sube nada.
class TrustedContactInput {
  const TrustedContactInput({
    required this.displayName,
    this.phone,
    this.email,
    this.isPrimary = false,
  });

  final String displayName;
  final String? phone;
  final String? email;
  final bool isPrimary;

  /// Normaliza espacios y deja el teléfono/email en formato canónico simple.
  TrustedContactInput normalized() {
    String? p = phone?.trim();
    if (p != null) {
      // Conserva '+' inicial y dígitos; quita espacios/guiones/paréntesis.
      final bool plus = p.startsWith('+');
      final String digits = p.replaceAll(RegExp(r'[^0-9]'), '');
      p = digits.isEmpty ? null : (plus ? '+$digits' : digits);
    }
    final String? e = email?.trim().toLowerCase();
    return TrustedContactInput(
      displayName: displayName.trim(),
      phone: (p?.isNotEmpty ?? false) ? p : null,
      email: (e?.isNotEmpty ?? false) ? e : null,
      isPrimary: isPrimary,
    );
  }

  /// Mensaje de error si no es válido; null si es válido. Debe tener nombre y
  /// al menos un canal (teléfono o email) válido.
  String? validate() {
    final TrustedContactInput n = normalized();
    if (n.displayName.length < 2) return 'Escribe un nombre para el contacto.';
    if (n.phone == null && n.email == null) {
      return 'Añade un teléfono o un email de contacto.';
    }
    if (n.phone != null) {
      final String digits = n.phone!.replaceAll('+', '');
      if (digits.length < 6 || digits.length > 15) {
        return 'El teléfono no parece válido.';
      }
    }
    if (n.email != null &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(n.email!)) {
      return 'El email no parece válido.';
    }
    return null;
  }
}

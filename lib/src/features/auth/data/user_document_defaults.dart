class UserDocumentDefaults {
  UserDocumentDefaults._();

  static const String _configuredEmpresa = String.fromEnvironment(
    'ATTRA_FIRESTORE_EMPRESA',
  );

  static String get empresa {
    final String configured = _configuredEmpresa.trim();
    return configured.isEmpty ? 'Attra' : configured;
  }

  static Map<String, dynamic> requiredFields(String uid) {
    return <String, dynamic>{
      'uid': uid,
      'empresa': empresa,
    };
  }
}

import 'package:attra/src/features/ai_visual/domain/profile_insight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProfileInsight.fromMap parsea campos y default de severity', () {
    final ProfileInsight a = ProfileInsight.fromMap(<String, dynamic>{
      'id': 'more_photos',
      'severity': 'high',
      'text': 'Sube más fotos',
    });
    expect(a.id, 'more_photos');
    expect(a.severity, 'high');
    expect(a.text, 'Sube más fotos');

    final ProfileInsight b = ProfileInsight.fromMap(<String, dynamic>{});
    expect(b.severity, 'info'); // default
    expect(b.text, '');
  });
}

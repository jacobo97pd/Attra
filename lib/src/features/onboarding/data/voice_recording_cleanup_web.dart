import 'package:web/web.dart' as web;

Future<void> deleteTemporaryVoiceRecording(String path) async {
  final String cleanPath = path.trim();
  if (cleanPath.startsWith('blob:')) web.URL.revokeObjectURL(cleanPath);
}

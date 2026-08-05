import 'dart:io';

Future<void> deleteTemporaryVoiceRecording(String path) async {
  final String cleanPath = path.trim();
  if (cleanPath.isEmpty) return;
  final File file = File(cleanPath);
  if (await file.exists()) await file.delete();
}

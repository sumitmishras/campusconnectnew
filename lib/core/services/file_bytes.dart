import 'package:flutter/services.dart';

/// Byte sources for uploads that do not come from the platform file picker.
///
/// Chat attachments and profile photos chosen from the device are read by
/// `file_picker` itself. This is only used for the built-in avatar choices,
/// which are remote images the app re-uploads into a bucket it owns.
class FileBytes {
  const FileBytes._();

  /// Downloads an image so it can be re-uploaded into a bucket the app owns.
  /// Returns null on any failure — the caller falls back to keeping the URL it
  /// already had.
  static Future<Uint8List?> fromNetwork(String url) async {
    if (url.isEmpty) return null;
    try {
      final data = await NetworkAssetBundle(Uri.parse(url)).load('');
      final bytes = data.buffer.asUint8List();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }
}

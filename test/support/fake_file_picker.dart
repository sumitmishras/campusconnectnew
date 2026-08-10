import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';

/// Stands in for the device's file picker so a test can drive the real
/// attachment flow — sheet, validation, upload, bubble — without a platform
/// channel. The picker itself is a plugin; everything above it is ours.
class FakeFilePicker extends FilePickerPlatform {
  FakeFilePicker();

  /// What the next pick returns. Null means the student cancelled.
  PlatformFile? next;

  /// The type the sheet asked for, so a test can check photos and documents are
  /// requested with the right filter.
  FileType? lastType;
  List<String>? lastAllowedExtensions;
  int pickCount = 0;

  void offer(String name, Uint8List bytes) {
    next = PlatformFile(name: name, size: bytes.length, bytes: bytes);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    pickCount++;
    lastType = type;
    lastAllowedExtensions = allowedExtensions;

    final file = next;
    if (file == null) return null;
    return FilePickerResult([file]);
  }
}

/// A real 1x1 PNG, so the widget under test decodes actual image bytes.
final Uint8List tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
);

/// Bytes that only matter by their length.
Uint8List bytesOfSize(int size) => Uint8List(size);

/// A plausible document payload.
Uint8List textBytes(String content) =>
    Uint8List.fromList(utf8.encode(content));

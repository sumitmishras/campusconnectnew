import '../models/chat_model.dart';

/// Rules for chat attachments.
///
/// Campus Connect only allows photos and documents, and every file has to stay
/// under [maxBytes]. These checks are a courtesy to the student — the same
/// limits are enforced by `create_upload_ticket()`, by the constraints on
/// `message_attachments` and by the `chat-media` storage policy, so a patched
/// client gains nothing by skipping them.
class AttachmentService {
  static const int maxBytes = 5 * 1024 * 1024; // 5 MB
  static const String maxLabel = '5 MB';

  /// Extensions the picker will accept. Mirrors the mime allow-list in
  /// `0004_chat.sql`.
  static const photoExtensions = ['jpg', 'jpeg', 'png', 'heic', 'webp'];
  static const documentExtensions = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
  ];

  static bool isWithinLimit(int bytes) => bytes <= maxBytes;

  static bool isAllowed(Attachment file) {
    final ext = file.extension;
    return file.isPhoto
        ? photoExtensions.contains(ext)
        : documentExtensions.contains(ext);
  }

  /// `null` when the file can be sent, otherwise the reason it was blocked.
  static String? rejectionReason(Attachment file) {
    if (!isAllowed(file)) {
      return file.isPhoto
          ? 'Only ${photoExtensions.join(', ')} images can be shared'
          : 'That document type is not supported';
    }
    if (file.sizeBytes <= 0) {
      return '${file.name} is empty';
    }
    if (!isWithinLimit(file.sizeBytes)) {
      return '${file.name} is ${file.readableSize} — the limit is $maxLabel';
    }
    return null;
  }
}

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/chat_model.dart';

/// Bucket names, as created by `0009_storage.sql`.
class StorageBuckets {
  const StorageBuckets._();

  /// Public: Discover renders forty avatars per scroll and signing each one
  /// would be forty round trips.
  static const avatars = 'avatars';

  /// Private. Every object path starts with its conversation id and the read
  /// policy checks membership live, so removing someone from a group cuts off
  /// every file ever shared in it. Clients read through signed URLs.
  static const chatMedia = 'chat-media';

  /// Public: club logos, event covers, project covers.
  static const campusAssets = 'campus-assets';
}

/// Raised for anything the student should see a message about.
class StorageFailure implements Exception {
  final String message;
  const StorageFailure(this.message);
  @override
  String toString() => message;
}

/// A file that has been accepted into `chat-media` but is not yet attached to
/// a message. [objectPath] is the server-generated key from
/// `create_upload_ticket()`; `send_message()` copies everything trustworthy
/// from that same ticket rather than from this payload.
class PendingUpload {
  final String objectPath;
  final int? width;
  final int? height;

  const PendingUpload({required this.objectPath, this.width, this.height});

  Map<String, dynamic> toPayload() => {
        'object_path': objectPath,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

/// Everything the app does with Supabase Storage.
///
/// The three-step chat flow (ticket → upload → send) lives behind
/// [uploadChatAttachment] so no screen has to know about it. Avatars and
/// campus imagery are a single upload each, because their buckets are public
/// and the path is owned by the uploading student.
abstract class StorageRepository {
  /// Returns the public URL to store in `profiles.avatar_url`.
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  });

  /// Event covers and project covers. [folder] scopes the object, e.g.
  /// `events` or `projects`.
  Future<String> uploadCampusAsset({
    required Uint8List bytes,
    required String fileName,
    required String folder,
  });

  /// Validates, tickets and uploads a chat photo or document.
  Future<PendingUpload> uploadChatAttachment({
    required String conversationId,
    required Attachment file,
  });

  /// Short-lived URL for a private object. Returns an empty string for a
  /// bucket that is already public, or when signing fails.
  Future<String> signedUrl(String bucket, String objectPath);

  /// Signs many objects in one request — the media tab and a page of history
  /// would otherwise be one round trip per file.
  Future<Map<String, String>> signedUrls(String bucket, List<String> objectPaths);

  /// Public URL for an object in a public bucket.
  String publicUrl(String bucket, String objectPath);
}

/// How long a `chat-media` URL stays valid. Long enough to scroll a thread and
/// open a document, short enough that a leaked link is not a permanent grant.
const Duration kSignedUrlTtl = Duration(hours: 1);

// =====================================================================
// Supabase
// =====================================================================

class SupabaseStorageRepository implements StorageRepository {
  SupabaseStorageRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const StorageFailure('Sign in again to change your photo.');

    // avatars/{user_id}/{name} — the first path segment is what
    // `cc_avatars_write` checks against auth.uid().
    final path = '$me/${_stamp()}.${_extension(fileName, 'jpg')}';

    try {
      await _client.storage.from(StorageBuckets.avatars).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeTypeFor(fileName),
              // A student replacing their photo should not accumulate objects.
              upsert: true,
            ),
          );
    } on StorageException catch (e) {
      throw StorageFailure(_readable(e));
    }

    return publicUrl(StorageBuckets.avatars, path);
  }

  @override
  Future<String> uploadCampusAsset({
    required Uint8List bytes,
    required String fileName,
    required String folder,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const StorageFailure('Sign in again to upload an image.');

    final path = '$folder/$me/${_stamp()}.${_extension(fileName, 'jpg')}';

    try {
      await _client.storage.from(StorageBuckets.campusAssets).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeTypeFor(fileName)),
          );
    } on StorageException catch (e) {
      // cc_campus_assets_write is limited to trusted accounts, which comes
      // back as a policy failure with nothing else the student could act on.
      throw StorageFailure(
        e.statusCode == '403'
            ? 'Only trusted accounts can upload campus images yet.'
            : _readable(e),
      );
    }

    return publicUrl(StorageBuckets.campusAssets, path);
  }

  @override
  Future<PendingUpload> uploadChatAttachment({
    required String conversationId,
    required Attachment file,
  }) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const StorageFailure('That file could not be read.');
    }

    // 1. Ticket. Validates membership, size and rate limit before a single
    //    byte is accepted, and chooses the object path itself so a client
    //    cannot overwrite another thread's object.
    late final Map<String, dynamic> ticket;
    try {
      ticket = Map<String, dynamic>.from(
        await _client.rpc('create_upload_ticket', params: {
          'p_conversation_id': conversationId,
          'p_kind': file.isPhoto ? 'photo' : 'document',
          'p_file_name': file.name,
          'p_mime_type':
              file.mimeType.isEmpty ? mimeTypeFor(file.name) : file.mimeType,
          'p_size_bytes': bytes.length,
        }) as Map,
      );
    } on PostgrestException catch (e) {
      throw StorageFailure(_readablePostgrest(e));
    }

    final objectPath = ticket['object_path'] as String;

    // 2. Upload. `cc_chat_media_write` allows the INSERT only while that
    //    ticket is live and unconsumed.
    try {
      await _client.storage.from(StorageBuckets.chatMedia).uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              contentType: ticket['mime_type'] as String? ??
                  mimeTypeFor(file.name),
            ),
          );
    } on StorageException catch (e) {
      throw StorageFailure(_readable(e));
    }

    // 3. The caller passes this to send_message(), which consumes the ticket
    //    in the same transaction as the message.
    return PendingUpload(
      objectPath: objectPath,
      width: file.width,
      height: file.height,
    );
  }

  @override
  Future<String> signedUrl(String bucket, String objectPath) async {
    if (objectPath.isEmpty) return '';
    try {
      return await _client.storage
          .from(bucket)
          .createSignedUrl(objectPath, kSignedUrlTtl.inSeconds);
    } on StorageException {
      // A file the student is no longer entitled to read is not an error
      // worth surfacing — the bubble renders its placeholder instead.
      return '';
    }
  }

  @override
  Future<Map<String, String>> signedUrls(
    String bucket,
    List<String> objectPaths,
  ) async {
    final paths = objectPaths.where((p) => p.isNotEmpty).toSet().toList();
    if (paths.isEmpty) return const {};

    try {
      final signed = await _client.storage
          .from(bucket)
          .createSignedUrlsResult(paths, kSignedUrlTtl.inSeconds);

      final result = <String, String>{};
      for (final entry in signed) {
        // A path that cannot be signed is one whose object is gone — a
        // retention sweep, or a cleanup of an orphaned upload. The bubble
        // renders its placeholder rather than the whole page failing.
        if (entry is SignedUrlSuccess) result[entry.path] = entry.signedUrl;
      }
      return result;
    } on StorageException {
      return const {};
    }
  }

  @override
  String publicUrl(String bucket, String objectPath) =>
      objectPath.isEmpty ? '' : _client.storage.from(bucket).getPublicUrl(objectPath);

  static String _stamp() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  static String _extension(String fileName, String fallback) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return fallback;
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String _readable(StorageException e) {
    if (e.statusCode == '413') return 'That file is too large.';
    if (e.statusCode == '409') return 'That file has already been uploaded.';
    return e.message.isEmpty ? 'The upload failed. Please try again.' : e.message;
  }

  static String _readablePostgrest(PostgrestException e) =>
      e.message.isEmpty ? 'The upload could not be started.' : e.message;
}

// =====================================================================
// Mock
// =====================================================================

/// Keeps whatever URL the picker already had, so attachments and avatars work
/// with no credentials and no bytes ever leave the device.
class MockStorageRepository implements StorageRepository {
  const MockStorageRepository();

  @override
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async =>
      '';

  @override
  Future<String> uploadCampusAsset({
    required Uint8List bytes,
    required String fileName,
    required String folder,
  }) async =>
      '';

  /// Chat attachments have no offline path: the object key comes from
  /// `create_upload_ticket()` and `send_message()` will only accept one it
  /// issued, so there is nothing honest to return here.
  @override
  Future<PendingUpload> uploadChatAttachment({
    required String conversationId,
    required Attachment file,
  }) async =>
      throw const StorageFailure(
        'Sharing files needs a connection to Campus Connect.',
      );

  @override
  Future<String> signedUrl(String bucket, String objectPath) async => '';

  @override
  Future<Map<String, String>> signedUrls(
    String bucket,
    List<String> objectPaths,
  ) async =>
      const {};

  @override
  String publicUrl(String bucket, String objectPath) => '';
}

// =====================================================================
// Shared helpers
// =====================================================================

/// The mime types `attachments_mime_allowed` and the bucket allow-lists accept.
/// Sending anything else is rejected by the database, so the mapping has to
/// agree with `0004_chat.sql`.
String mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

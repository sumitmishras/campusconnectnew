import '../models/chat_model.dart';
import '../models/user_model.dart';
import 'repositories/storage_repository.dart';

/// Translates the chat RPC results into the models the UI already speaks.
///
/// `get_chat_list()` and `get_messages()` return flattened, pre-joined rows on
/// purpose — the chat list needs no N+1 and a page of history arrives with its
/// attachments as JSON. All the renaming between Postgres convention and Dart
/// convention happens here, once.
class ChatMapper {
  const ChatMapper._();

  // ------------------------------------------------------------- chat list

  static bool isGroupRow(Map<String, dynamic> row) => row['type'] == 'group';

  /// The other participant, built from the columns `get_chat_list()` flattens
  /// into the row. Used as-is when the full profile could not be fetched (the
  /// student deactivated, or RLS hid them), so a DM never renders blank.
  static User otherUserFromListRow(Map<String, dynamic> row) {
    final hidden = row['other_is_online'] == null;
    return User(
      id: row['other_user_id'] as String? ?? '',
      name: row['other_user_name'] as String? ?? 'Student',
      username: '',
      phoneNumber: '',
      department: '',
      course: '',
      year: '',
      bio: '',
      interests: const [],
      languages: const [],
      lookingFor: const [],
      profilePhotoUrl: row['other_user_avatar'] as String? ?? '',
      isOnline: row['other_is_online'] as bool? ?? false,
      lastActive: parseDate(row['other_last_active']) ?? DateTime.now(),
      // A null presence pair is exactly what `get_chat_list` returns for a
      // student who switched "hide active status" on.
      hideActiveStatus: hidden,
    );
  }

  static Chat chatFromListRow(Map<String, dynamic> row, {User? profile}) {
    return Chat(
      id: row['conversation_id'] as String,
      otherUser: profile ?? otherUserFromListRow(row),
      messages: const [],
      unreadCount: _int(row['unread_count']),
      previewText: row['last_message_preview'] as String? ?? '',
      lastActivity: parseDate(row['last_message_at']),
      isPinned: row['is_pinned'] as bool? ?? false,
      isMuted: _isMuted(row['muted_until']),
      lastSeq: _int(row['last_seq']),
    );
  }

  static GroupChat groupFromListRow(Map<String, dynamic> row) {
    return GroupChat(
      // The campus entity is what every screen navigates by; the thread is
      // what every RPC takes. `adhoc` groups have no source row, so they fall
      // back to the conversation id.
      id: (row['source_id'] as String?) ?? row['conversation_id'] as String,
      conversationId: row['conversation_id'] as String,
      name: row['title'] as String? ?? 'Group',
      kind: GroupKindWire.parse(row['source_type']),
      description: '',
      memberCount: _int(row['member_count']),
      members: const [],
      messages: const [],
      unreadCount: _int(row['unread_count']),
      photoUrl: row['photo_url'] as String? ?? '',
      previewText: _groupPreview(row),
      lastActivity: parseDate(row['last_message_at']),
      isMuted: _isMuted(row['muted_until']),
      lastSeq: _int(row['last_seq']),
    );
  }

  /// The group list prefixes the sender, and `get_chat_list()` gives the
  /// sender id rather than a name, so "You: …" is all that can be resolved
  /// before the thread is opened.
  static String _groupPreview(Map<String, dynamic> row) =>
      row['last_message_preview'] as String? ?? '';

  // -------------------------------------------------------------- messages

  /// [signedUrls] maps `object_path` to a short-lived URL for the private
  /// `chat-media` bucket; the caller signs a whole page in one request.
  static Message messageFromRow(
    Map<String, dynamic> row, {
    required String myId,
    Map<String, String> signedUrls = const {},
  }) {
    final senderId = row['sender_id'] as String? ?? '';
    final deleted = row['deleted_at'] != null;
    final attachments = row['attachments'];

    return Message(
      id: row['id'] as String,
      senderId: senderId,
      content: row['body'] as String? ?? '',
      timestamp: parseDate(row['created_at']) ?? DateTime.now(),
      // In a DM `seen_by_all` is precisely "the other member's last_read_seq
      // is at or past this message"; in a group it is the double tick.
      isSeen: row['seen_by_all'] as bool? ?? false,
      senderName: senderId == myId
          ? 'You'
          : (row['sender_name'] as String? ?? 'Student'),
      senderPhotoUrl: row['sender_avatar'] as String? ?? '',
      attachment: deleted
          ? null
          : _firstAttachment(attachments, signedUrls: signedUrls),
      seq: _int(row['seq']),
      isMine: senderId == myId,
      isDeleted: deleted,
    );
  }

  /// Every `object_path` in a page of history, so they can be signed together.
  static List<String> attachmentPaths(List<Map<String, dynamic>> rows) {
    final paths = <String>[];
    for (final row in rows) {
      final list = row['attachments'];
      if (list is! List) continue;
      for (final entry in list) {
        if (entry is! Map) continue;
        final path = entry['object_path'] as String?;
        if (path != null && path.isNotEmpty) paths.add(path);
      }
    }
    return paths;
  }

  /// The UI shows one attachment per bubble. `send_message()` accepts an array
  /// for future multi-file sends; until the UI offers that, the first is the
  /// one that matters.
  static Attachment? _firstAttachment(
    Object? value, {
    Map<String, String> signedUrls = const {},
  }) {
    if (value is! List || value.isEmpty) return null;
    final first = value.first;
    if (first is! Map) return null;
    return attachmentFromJson(
      Map<String, dynamic>.from(first),
      signedUrls: signedUrls,
    );
  }

  static Attachment attachmentFromJson(
    Map<String, dynamic> json, {
    Map<String, String> signedUrls = const {},
  }) {
    final objectPath = json['object_path'] as String? ?? '';
    final thumbPath = json['thumb_path'] as String? ?? '';
    final isPhoto = json['kind'] == 'photo';

    return Attachment(
      type: isPhoto ? AttachmentType.photo : AttachmentType.document,
      name: json['file_name'] as String? ?? 'file',
      sizeBytes: _int(json['size_bytes']),
      // Photos render from the thumbnail when one was generated; documents
      // never need a preview URL at all.
      previewUrl: isPhoto
          ? (signedUrls[thumbPath] ?? signedUrls[objectPath] ?? '')
          : '',
      bucket: json['bucket'] as String? ?? StorageBuckets.chatMedia,
      objectPath: objectPath,
      thumbPath: thumbPath,
      width: json['width'] as int?,
      height: json['height'] as int?,
      mimeType: json['mime_type'] as String? ?? '',
      scanStatus: _scanStatus(json['scan_status']),
    );
  }

  /// `send_message()` returns the `messages` row itself, which carries neither
  /// the sender's name nor the attachment rows — both are already known to the
  /// caller, so they are passed back in rather than re-fetched.
  static Message sentMessageFromRow(
    Map<String, dynamic> row, {
    required Attachment? attachment,
  }) {
    return Message(
      id: row['id'] as String,
      senderId: row['sender_id'] as String? ?? '',
      content: row['body'] as String? ?? '',
      timestamp: parseDate(row['created_at']) ?? DateTime.now(),
      isSeen: false,
      senderName: 'You',
      attachment: attachment,
      seq: _int(row['seq']),
      isMine: true,
      isDeleted: row['deleted_at'] != null,
      clientMsgId: row['client_msg_id'] as String? ?? '',
    );
  }

  // --------------------------------------------------------------- helpers

  static ScanStatus _scanStatus(Object? value) {
    switch (value) {
      case 'clean':
        return ScanStatus.clean;
      case 'infected':
        return ScanStatus.infected;
      case 'failed':
        return ScanStatus.failed;
      default:
        return ScanStatus.pending;
    }
  }

  static bool _isMuted(Object? mutedUntil) {
    final until = parseDate(mutedUntil);
    return until != null && until.isAfter(DateTime.now());
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    if (value is DateTime) return value.toLocal();
    return null;
  }
}

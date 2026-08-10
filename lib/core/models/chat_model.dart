import 'dart:typed_data';

import 'user_model.dart';

/// Only photos and documents can be shared in chats.
enum AttachmentType { photo, document }

/// Mirrors `public.scan_status`. The client should not offer a download until
/// a file is `clean` — see the malware note in `DATABASE.md`.
enum ScanStatus { pending, clean, infected, failed }

class Attachment {
  final AttachmentType type;
  final String name;
  final int sizeBytes;

  /// Thumbnail / full image for photos. Empty for documents.
  ///
  /// For `chat-media` this is a short-lived signed URL: the bucket is private
  /// and membership is re-checked on every read, so removing someone from a
  /// group cuts off every file ever shared in it.
  final String previewUrl;

  /// Where the bytes live in Supabase Storage. Empty until the upload has been
  /// accepted and `send_message()` has attached it.
  final String bucket;
  final String objectPath;

  /// Generated 400px preview, when one exists.
  final String thumbPath;

  final int? width;
  final int? height;
  final String mimeType;
  final ScanStatus scanStatus;

  /// Set only on an outgoing attachment, between the picker and the upload.
  /// Never populated by anything read back from the server.
  final Uint8List? bytes;

  const Attachment({
    required this.type,
    required this.name,
    required this.sizeBytes,
    this.previewUrl = '',
    this.bucket = '',
    this.objectPath = '',
    this.thumbPath = '',
    this.width,
    this.height,
    this.mimeType = '',
    this.scanStatus = ScanStatus.pending,
    this.bytes,
  });

  bool get isPhoto => type == AttachmentType.photo;

  /// True once the bytes are in Storage and a row points at them.
  bool get isStored => objectPath.isNotEmpty;

  /// `pdf`, `docx`, `jpg` … used to pick the right icon and colour.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String get readableSize {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).round()} KB';
    }
    return '$sizeBytes B';
  }

  Attachment copyWith({
    String? previewUrl,
    String? bucket,
    String? objectPath,
    ScanStatus? scanStatus,
    Uint8List? bytes,
    bool clearBytes = false,
  }) {
    return Attachment(
      type: type,
      name: name,
      sizeBytes: sizeBytes,
      previewUrl: previewUrl ?? this.previewUrl,
      bucket: bucket ?? this.bucket,
      objectPath: objectPath ?? this.objectPath,
      thumbPath: thumbPath,
      width: width,
      height: height,
      mimeType: mimeType,
      scanStatus: scanStatus ?? this.scanStatus,
      bytes: clearBytes ? null : (bytes ?? this.bytes),
    );
  }
}

/// Where a message is in its journey to the server. Only ever anything other
/// than [sent] for messages this student just typed.
enum MessageStatus { sending, sent, failed }

class Message {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final bool isSeen;

  /// Only used in group threads, where every bubble needs a name.
  final String senderName;
  final String senderPhotoUrl;

  /// Set when this message is a shared photo or document.
  final Attachment? attachment;

  /// Per-conversation sequence number — the ordering and pagination key, and
  /// what read receipts compare against. 0 for a message not yet acknowledged
  /// by the server.
  final int seq;

  /// Resolved when the row is mapped, so no screen needs to know the signed-in
  /// student's id.
  final bool isMine;

  /// Soft-deleted by its sender or a group admin. The row survives so replies
  /// pointing at it do not dangle.
  final bool isDeleted;

  /// Generated before the first send attempt and reused on every retry, so a
  /// dropped response over campus wifi cannot produce a duplicate bubble.
  final String clientMsgId;

  final MessageStatus status;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.isSeen = false,
    this.senderName = '',
    this.senderPhotoUrl = '',
    this.attachment,
    this.seq = 0,
    this.isMine = false,
    this.isDeleted = false,
    this.clientMsgId = '',
    this.status = MessageStatus.sent,
  });

  bool get hasAttachment => attachment != null;

  /// What the chat list shows as the preview line.
  String get preview {
    if (isDeleted) return 'This message was deleted';
    final a = attachment;
    if (a == null) return content;
    return a.isPhoto ? '📷 Photo' : '📄 ${a.name}';
  }

  Message copyWith({
    String? id,
    String? content,
    bool? isSeen,
    Attachment? attachment,
    int? seq,
    bool? isDeleted,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId,
      content: content ?? this.content,
      timestamp: timestamp,
      isSeen: isSeen ?? this.isSeen,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      attachment: attachment ?? this.attachment,
      seq: seq ?? this.seq,
      isMine: isMine,
      isDeleted: isDeleted ?? this.isDeleted,
      clientMsgId: clientMsgId,
      status: status ?? this.status,
    );
  }
}

class Chat {
  /// The conversation id. Direct threads have no other identity, so [id] and
  /// [conversationId] are the same thing — the second name exists because
  /// group threads are keyed differently (see [GroupChat]).
  final String id;

  /// The other participant. `get_chat_list()` returns their name, avatar and
  /// presence flattened into the row, so holding the whole [User] here costs
  /// no extra fetch.
  final User otherUser;
  final List<Message> messages;
  final int unreadCount;

  /// Chat-list preview kept on `conversations` by `send_message()`. Used until
  /// the thread itself is opened and [messages] is populated.
  final String previewText;
  final DateTime? lastActivity;

  final bool isPinned;
  final bool isMuted;

  /// The head of the thread as the server sees it. [messages] may be a page
  /// behind it while history is still loading.
  final int lastSeq;

  /// True once [messages] holds this thread's history rather than nothing.
  final bool isHydrated;

  String get conversationId => id;

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  /// What the list row renders, whether or not the thread has been opened.
  String get displayPreview => lastMessage?.preview ?? previewText;

  DateTime? get lastTimestamp => lastMessage?.timestamp ?? lastActivity;

  Chat({
    required this.id,
    required this.otherUser,
    required this.messages,
    this.unreadCount = 0,
    this.previewText = '',
    this.lastActivity,
    this.isPinned = false,
    this.isMuted = false,
    this.lastSeq = 0,
    this.isHydrated = false,
  });

  Chat copyWith({
    User? otherUser,
    List<Message>? messages,
    int? unreadCount,
    String? previewText,
    DateTime? lastActivity,
    bool? isPinned,
    bool? isMuted,
    int? lastSeq,
    bool? isHydrated,
  }) {
    return Chat(
      id: id,
      otherUser: otherUser ?? this.otherUser,
      messages: messages ?? this.messages,
      unreadCount: unreadCount ?? this.unreadCount,
      previewText: previewText ?? this.previewText,
      lastActivity: lastActivity ?? this.lastActivity,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      lastSeq: lastSeq ?? this.lastSeq,
      isHydrated: isHydrated ?? this.isHydrated,
    );
  }
}

enum GroupKind { community, club, studyGroup, project, event }

/// Mirrors `public.group_source`.
extension GroupKindWire on GroupKind {
  static const _names = {
    GroupKind.community: 'community',
    GroupKind.club: 'club',
    GroupKind.studyGroup: 'study_group',
    GroupKind.project: 'project',
    GroupKind.event: 'event',
  };

  String get wire => _names[this]!;

  static GroupKind parse(Object? value,
      {GroupKind fallback = GroupKind.community}) {
    if (value is GroupKind) return value;
    if (value is String) {
      for (final entry in _names.entries) {
        if (entry.value == value) return entry.key;
      }
    }
    return fallback;
  }
}

/// A group thread that appears in Chats once the student joins the
/// community, club or study group it belongs to. Its [id] is the id of
/// that community/club/group, so joining and leaving stay in sync.
///
/// [conversationId] is the thread itself — `conversations.source_id` is the
/// campus entity, `conversations.id` is where the messages live, and the two
/// are different rows. Every screen navigates by [id]; every RPC takes
/// [conversationId].
class GroupChat {
  final String id;
  final String conversationId;
  final String name;
  final GroupKind kind;
  final String description;
  final int memberCount;
  final List<User> members;
  final List<Message> messages;
  final int unreadCount;
  final String photoUrl;
  final String previewText;
  final DateTime? lastActivity;
  final bool isMuted;
  final int lastSeq;
  final bool isHydrated;

  GroupChat({
    required this.id,
    required this.name,
    required this.kind,
    required this.description,
    required this.memberCount,
    required this.members,
    required this.messages,
    String? conversationId,
    this.unreadCount = 0,
    this.photoUrl = '',
    this.previewText = '',
    this.lastActivity,
    this.isMuted = false,
    this.lastSeq = 0,
    this.isHydrated = false,
  }) : conversationId = conversationId ?? id;

  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  String get displayPreview => lastMessage?.preview ?? previewText;

  DateTime? get lastTimestamp => lastMessage?.timestamp ?? lastActivity;

  String get kindLabel {
    switch (kind) {
      case GroupKind.community:
        return 'Community';
      case GroupKind.club:
        return 'Club';
      case GroupKind.studyGroup:
        return 'Study Group';
      case GroupKind.project:
        return 'Project';
      case GroupKind.event:
        return 'Event';
    }
  }

  GroupChat copyWith({
    String? name,
    String? description,
    List<Message>? messages,
    List<User>? members,
    int? unreadCount,
    int? memberCount,
    String? previewText,
    DateTime? lastActivity,
    bool? isMuted,
    int? lastSeq,
    bool? isHydrated,
  }) {
    return GroupChat(
      id: id,
      conversationId: conversationId,
      name: name ?? this.name,
      kind: kind,
      description: description ?? this.description,
      memberCount: memberCount ?? this.memberCount,
      members: members ?? this.members,
      messages: messages ?? this.messages,
      unreadCount: unreadCount ?? this.unreadCount,
      photoUrl: photoUrl,
      previewText: previewText ?? this.previewText,
      lastActivity: lastActivity ?? this.lastActivity,
      isMuted: isMuted ?? this.isMuted,
      lastSeq: lastSeq ?? this.lastSeq,
      isHydrated: isHydrated ?? this.isHydrated,
    );
  }
}

class ConnectionRequest {
  final String id;
  final User sender;
  final String purpose;
  final DateTime timestamp;

  ConnectionRequest({
    required this.id,
    required this.sender,
    required this.purpose,
    required this.timestamp,
  });
}

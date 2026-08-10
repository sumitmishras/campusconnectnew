import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/chat_model.dart';
import '../../models/user_model.dart';
import '../../services/realtime_status.dart';
import '../chat_mapper.dart';
import '../profile_mapper.dart';
import 'storage_repository.dart';

/// Raised for anything the student should see a message about. Anything else
/// is a bug and propagates — same contract as `ConnectionFailure`.
class ChatFailure implements Exception {
  final String message;
  const ChatFailure(this.message);
  @override
  String toString() => message;
}

/// The Chats tab in one value: direct threads and group threads together,
/// which is how `get_chat_list()` returns them.
class ChatListSnapshot {
  final List<Chat> chats;
  final List<GroupChat> groups;

  const ChatListSnapshot({required this.chats, required this.groups});

  static const empty = ChatListSnapshot(chats: [], groups: []);
}

/// A message that arrived over Realtime rather than from a fetch.
class IncomingMessage {
  final String conversationId;
  final Message message;

  /// True when this is a change to a message the thread may already hold — a
  /// soft delete, most often. The provider replaces rather than appends, and
  /// does not count it as unread.
  final bool isUpdate;

  const IncomingMessage({
    required this.conversationId,
    required this.message,
    this.isUpdate = false,
  });
}

/// Someone started or stopped typing in a thread.
class TypingSignal {
  final String conversationId;
  final bool isTyping;

  const TypingSignal({required this.conversationId, required this.isTyping});
}

/// Another member has read up to [seq] in [conversationId].
///
/// Read pointers live in `conversation_members`, which is not replicated (a
/// student's read position in every thread is not something to broadcast to the
/// whole campus), so the reader announces it on the thread's own channel
/// instead. `seen_by_all` from `get_messages()` remains the source of truth on
/// the next load; this is what makes the tick turn over while both people are
/// looking at the thread.
class ReadReceipt {
  final String conversationId;
  final int seq;

  const ReadReceipt({required this.conversationId, required this.seq});
}

/// Everything the app does with chat.
///
/// Every write goes through an RPC rather than a table: allocating `seq`,
/// checking the block list, consuming the upload ticket and refreshing the
/// chat-list preview have to happen as one atomic unit, and `send_message()`
/// is the only place that can be guaranteed. See `0007_chat_functions.sql`.
abstract class ChatRepository {
  /// The signed-in student's id as messages carry it. Screens never need it:
  /// [Message.isMine] is resolved when the row is mapped.
  String get myId;

  Future<ChatListSnapshot> fetchChatList();

  /// One keyset page of history, oldest-first so it can be appended straight
  /// to the list the bubbles render from.
  Future<List<Message>> fetchMessages(
    String conversationId, {
    int? beforeSeq,
    int limit = kMessagePageSize,
  });

  /// [clientMsgId] must be generated once, before the first attempt, and
  /// reused on every retry — that is what makes a dropped response over campus
  /// wifi return the original message instead of posting a second bubble.
  Future<Message> sendMessage({
    required String conversationId,
    String body = '',
    Attachment? attachment,
    required String clientMsgId,
  });

  /// Soft delete. The row survives so replies do not dangle.
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  });

  /// Advances the read pointer and returns what is still unread.
  Future<int> markRead({required String conversationId, required int seq});

  Future<int> totalUnread();

  /// Opens (or reuses) the DM with [other] and returns its conversation id.
  /// Race-safe: `get_or_create_direct_conversation` infers the unique index on
  /// `direct_key`, so two devices cannot produce two threads.
  Future<String> openDirectConversation(User other);

  Future<void> setMuted({required String conversationId, required bool muted});

  /// Hides everything said so far from this student only.
  Future<void> clearHistory(String conversationId);

  /// Leaves a group, or removes a DM from this student's list.
  Future<void> leaveConversation(String conversationId);

  Future<void> joinGroup(String conversationId);

  Future<List<User>> fetchMembers(String conversationId, {int limit = 60});

  /// Every message arriving in any thread this student belongs to.
  Stream<IncomingMessage> messages();

  /// Typing indicators. Ephemeral by design — they are valid for about three
  /// seconds and writing them to Postgres would generate more traffic than the
  /// messages themselves, so they travel over a Realtime broadcast channel.
  Stream<TypingSignal> typing();

  /// Read receipts from the other members of a thread.
  Stream<ReadReceipt> readReceipts();

  /// Joins a thread's ephemeral channel so its typing indicators and read
  /// receipts start arriving. Called when a thread is opened — without it a
  /// student would only ever see the other side typing in a thread they had
  /// already typed in themselves. Idempotent.
  void watchThread(String conversationId);

  /// Fires when the inbox channel re-joins after the socket dropped.
  ///
  /// Realtime replays nothing, so every message that arrived while the phone
  /// was asleep is simply absent — the provider re-reads the chat list rather
  /// than waiting for the next one to arrive and paper over the hole.
  Stream<void> reconnections();

  Future<void> notifyTyping(String conversationId);

  /// Tells the other members this student has read up to [seq].
  Future<void> notifyRead({required String conversationId, required int seq});

  /// Drops per-thread subscriptions and re-joins the inbox, for when the signed
  /// in student changes on this device. The streams stay open.
  Future<void> resetSession();

  /// Called when the provider is disposed; tears down any subscriptions.
  Future<void> close();
}

/// 40 is what `get_messages()` defaults to: about three screens of bubbles.
const int kMessagePageSize = 40;

/// How long a typing indicator stays on screen without another keystroke.
const Duration kTypingTimeout = Duration(seconds: 4);

// =====================================================================
// Supabase
// =====================================================================

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client, this._storage);

  final SupabaseClient _client;
  final StorageRepository _storage;

  final _messages = StreamController<IncomingMessage>.broadcast();
  final _typing = StreamController<TypingSignal>.broadcast();
  final _receipts = StreamController<ReadReceipt>.broadcast();
  final _reconnects = StreamController<void>.broadcast();

  RealtimeChannel? _inbox;

  /// One ephemeral channel per open thread, carrying typing and read events.
  final Map<String, RealtimeChannel> _threadChannels = {};

  @override
  String get myId => _client.auth.currentUser?.id ?? '';

  // ------------------------------------------------------------- chat list

  @override
  Future<ChatListSnapshot> fetchChatList() async {
    final rows = await _rpcRows('get_chat_list', {'p_limit': 60});
    if (rows.isEmpty) return ChatListSnapshot.empty;

    final directRows = rows.where((r) => !ChatMapper.isGroupRow(r)).toList();
    final groupRows = rows.where(ChatMapper.isGroupRow).toList();

    // Two batched follow-ups rather than one per row: full profiles for the
    // DM avatars (so tapping through to a profile has something to show), and
    // the group descriptions, which get_chat_list does not carry.
    final results = await Future.wait([
      _profilesById(directRows
          .map((r) => r['other_user_id'] as String?)
          .nonNulls
          .toSet()
          .toList()),
      _conversationDetails(
          groupRows.map((r) => r['conversation_id'] as String).toList()),
    ]);

    final profiles = results[0] as Map<String, User>;
    final details = results[1] as Map<String, Map<String, dynamic>>;

    final chats = [
      for (final row in directRows)
        ChatMapper.chatFromListRow(
          row,
          profile: profiles[row['other_user_id']],
        ),
    ];

    final groups = [
      for (final row in groupRows)
        ChatMapper.groupFromListRow(row).copyWith(
          description:
              details[row['conversation_id']]?['description'] as String? ?? '',
        ),
    ];

    return ChatListSnapshot(chats: chats, groups: groups);
  }

  Future<Map<String, User>> _profilesById(List<String> ids) async {
    if (ids.isEmpty) return const {};

    final rows = await _client
        .from('profiles')
        .select('''
          ${ProfileMapper.columns},
          profile_badges!profile_badges_profile_id_fkey(badges(label)),
          user_presence(is_online, last_active)
        ''')
        .inFilter('id', ids);

    return {
      for (final row in rows) row['id'] as String: ProfileMapper.fromRow(row),
    };
  }

  Future<Map<String, Map<String, dynamic>>> _conversationDetails(
      List<String> ids) async {
    if (ids.isEmpty) return const {};

    final rows = await _client
        .from('conversations')
        .select('id, title, description, photo_url, member_count')
        .inFilter('id', ids);

    return {for (final row in rows) row['id'] as String: row};
  }

  // -------------------------------------------------------------- messages

  @override
  Future<List<Message>> fetchMessages(
    String conversationId, {
    int? beforeSeq,
    int limit = kMessagePageSize,
  }) async {
    final rows = await _rpcRows('get_messages', {
      'p_conversation_id': conversationId,
      'p_before_seq': beforeSeq,
      'p_limit': limit,
    });
    return _mapPage(rows);
  }

  /// `get_messages()` returns newest-first (the keyset scan runs backwards);
  /// the bubbles are built oldest-first, so the page is reversed here rather
  /// than in every caller.
  Future<List<Message>> _mapPage(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];

    // One signing request for the whole page. chat-media is private, so every
    // photo needs a signed URL and doing it per bubble would be one round trip
    // per image.
    final signed = await _storage.signedUrls(
      StorageBuckets.chatMedia,
      ChatMapper.attachmentPaths(rows),
    );

    final me = myId;
    final messages = [
      for (final row in rows)
        ChatMapper.messageFromRow(row, myId: me, signedUrls: signed),
    ];
    return messages.reversed.toList();
  }

  @override
  Future<Message> sendMessage({
    required String conversationId,
    String body = '',
    Attachment? attachment,
    required String clientMsgId,
  }) async {
    var stored = attachment;
    final payload = <Map<String, dynamic>>[];

    if (attachment != null) {
      final upload = await _storage.uploadChatAttachment(
        conversationId: conversationId,
        file: attachment,
      );
      payload.add(upload.toPayload());
      stored = attachment.copyWith(
        bucket: StorageBuckets.chatMedia,
        objectPath: upload.objectPath,
        // Signed now so the sender's own bubble still renders after the bytes
        // are dropped, and so re-opening the thread shows the same image
        // everyone else sees rather than a placeholder.
        previewUrl: attachment.isPhoto
            ? await _storage.signedUrl(
                StorageBuckets.chatMedia, upload.objectPath)
            : '',
        clearBytes: true,
      );
    }

    try {
      final row = Map<String, dynamic>.from(
        await _client.rpc('send_message', params: {
          'p_conversation_id': conversationId,
          'p_body': body.trim().isEmpty ? null : body.trim(),
          'p_kind': attachment == null
              ? 'text'
              : (attachment.isPhoto ? 'photo' : 'document'),
          'p_client_msg_id': clientMsgId,
          'p_attachments': payload,
        }) as Map,
      );

      // The photo the sender is looking at is the one they picked, so its
      // local preview is kept rather than signing the object they just sent.
      return ChatMapper.sentMessageFromRow(row, attachment: stored);
    } on PostgrestException catch (e) {
      throw ChatFailure(_readableSend(e));
    } on StorageFailure catch (e) {
      throw ChatFailure(e.message);
    }
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    try {
      await _client.rpc('delete_message', params: {
        'p_conversation_id': conversationId,
        'p_message_id': messageId,
      });
    } on PostgrestException catch (e) {
      throw ChatFailure(_readable(e));
    }
  }

  @override
  Future<int> markRead({
    required String conversationId,
    required int seq,
  }) async {
    if (seq <= 0) return 0;
    try {
      final remaining = await _client.rpc('mark_read', params: {
        'p_conversation_id': conversationId,
        'p_seq': seq,
      });
      return _asInt(remaining);
    } on PostgrestException {
      // A failed acknowledgement is not worth a message: the badge is
      // recomputed from the server on the next load either way.
      return 0;
    }
  }

  @override
  Future<int> totalUnread() async {
    try {
      return _asInt(await _client.rpc('total_unread'));
    } on PostgrestException {
      return 0;
    }
  }

  @override
  Future<String> openDirectConversation(User other) async {
    try {
      final id = await _client.rpc('get_or_create_direct_conversation',
          params: {'p_other_user': other.id});
      return id as String;
    } on PostgrestException catch (e) {
      throw ChatFailure(_readableSend(e));
    }
  }

  @override
  Future<void> setMuted({
    required String conversationId,
    required bool muted,
  }) async {
    final me = myId;
    if (me.isEmpty) return;

    try {
      await _client
          .from('conversation_members')
          .update({
            // Far enough out to mean "muted"; unmuting clears it. `muted_until`
            // is one of the few columns the grants in 0008 leave writable.
            'muted_until': muted
                ? DateTime.now()
                    .toUtc()
                    .add(const Duration(days: 3650))
                    .toIso8601String()
                : null,
          })
          .eq('conversation_id', conversationId)
          .eq('user_id', me);
    } on PostgrestException catch (e) {
      throw ChatFailure(_readable(e));
    }
  }

  @override
  Future<void> clearHistory(String conversationId) async {
    try {
      // `visible_from_seq` is deliberately not in the column grants, so this
      // has to be a function (0012).
      await _client.rpc('clear_my_history',
          params: {'p_conversation_id': conversationId});
    } on PostgrestException catch (e) {
      throw ChatFailure(_readable(e));
    }
  }

  @override
  Future<void> leaveConversation(String conversationId) async {
    try {
      await _client
          .rpc('leave_group', params: {'p_conversation_id': conversationId});
    } on PostgrestException catch (e) {
      throw ChatFailure(_readable(e));
    }
  }

  @override
  Future<void> joinGroup(String conversationId) async {
    try {
      await _client
          .rpc('join_group', params: {'p_conversation_id': conversationId});
    } on PostgrestException catch (e) {
      throw ChatFailure(_readableJoin(e));
    }
  }

  @override
  Future<List<User>> fetchMembers(String conversationId,
      {int limit = 60}) async {
    final rows = await _client
        .from('conversation_members')
        .select('''
          user_id,
          profiles!inner(
            ${ProfileMapper.columns},
            profile_badges!profile_badges_profile_id_fkey(badges(label)),
            user_presence(is_online, last_active)
          )
        ''')
        .eq('conversation_id', conversationId)
        .isFilter('left_at', null)
        .limit(limit);

    final members = <User>[];
    for (final row in rows) {
      final profile = row['profiles'];
      if (profile is Map<String, dynamic>) {
        members.add(ProfileMapper.fromRow(profile));
      }
    }
    return members;
  }

  // -------------------------------------------------------------- realtime

  @override
  Stream<IncomingMessage> messages() {
    _subscribeInbox();
    return _messages.stream;
  }

  @override
  Stream<TypingSignal> typing() => _typing.stream;

  @override
  Stream<ReadReceipt> readReceipts() => _receipts.stream;

  @override
  Stream<void> reconnections() => _reconnects.stream;

  /// One channel for every thread. Realtime honours RLS, so `messages_read`
  /// already limits this to conversations the student belongs to — no filter
  /// is needed and none would be correct, since the set of threads changes as
  /// they join things.
  void _subscribeInbox() {
    if (_inbox != null) return;

    _inbox = _client.channel('cc-inbox')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) => _onMessageChanged(payload, isUpdate: false),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        callback: (payload) => _onMessageChanged(payload, isUpdate: true),
      )
      ..subscribe(realtimeStatus('cc-inbox', onRejoin: () {
        if (!_reconnects.isClosed) _reconnects.add(null);
      }));
  }

  /// The replicated row carries neither the sender's name nor its attachment
  /// rows, and a group bubble needs both — so the one message is re-read
  /// through `get_messages()`, which returns it fully joined.
  void _onMessageChanged(
    PostgresChangePayload payload, {
    required bool isUpdate,
  }) {
    final row = payload.newRecord;
    final conversationId = row['conversation_id'] as String?;
    final seq = _asInt(row['seq']);
    if (conversationId == null || seq <= 0) return;

    // A message this student just sent is already on screen, optimistically.
    // Updates are not skipped: a message deleted from this student's other
    // device has to disappear here too.
    if (!isUpdate && row['sender_id'] == myId) return;

    unawaited(_emitEnriched(conversationId, seq, isUpdate: isUpdate));
  }

  Future<void> _emitEnriched(
    String conversationId,
    int seq, {
    required bool isUpdate,
  }) async {
    try {
      final page = await fetchMessages(
        conversationId,
        beforeSeq: seq + 1,
        limit: 1,
      );
      if (page.isEmpty || _messages.isClosed) return;
      _messages.add(IncomingMessage(
        conversationId: conversationId,
        message: page.first,
        isUpdate: isUpdate,
      ));
    } catch (_) {
      // A message that cannot be re-read is one this student is not entitled
      // to; the next full load will agree.
    }
  }

  @override
  void watchThread(String conversationId) {
    if (conversationId.isEmpty) return;
    _threadChannel(conversationId);
  }

  @override
  Future<void> notifyTyping(String conversationId) async {
    await _threadChannel(conversationId).sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': myId},
    );
  }

  @override
  Future<void> notifyRead({
    required String conversationId,
    required int seq,
  }) async {
    if (seq <= 0) return;
    try {
      await _threadChannel(conversationId).sendBroadcastMessage(
        event: 'read',
        payload: {'user_id': myId, 'seq': seq},
      );
    } catch (_) {
      // The tick is a courtesy; `mark_read` has already recorded the truth.
    }
  }

  /// Typing and read events live on a broadcast channel, so nothing is written
  /// to Postgres. Created when a thread is opened and torn down in [close].
  RealtimeChannel _threadChannel(String conversationId) {
    final existing = _threadChannels[conversationId];
    if (existing != null) return existing;

    final channel = _client.channel(
      'cc-thread-$conversationId',
      // `self: false` — the sender does not need their own keystrokes back.
      opts: const RealtimeChannelConfig(self: false),
    )
      ..onBroadcast(
        event: 'typing',
        callback: (payload) {
          if (payload['user_id'] == myId || _typing.isClosed) return;
          _typing.add(
            TypingSignal(conversationId: conversationId, isTyping: true),
          );
        },
      )
      ..onBroadcast(
        event: 'read',
        callback: (payload) {
          if (payload['user_id'] == myId || _receipts.isClosed) return;
          final seq = _asInt(payload['seq']);
          if (seq <= 0) return;
          _receipts
              .add(ReadReceipt(conversationId: conversationId, seq: seq));
        },
      );

    _threadChannels[conversationId] = channel;
    channel.subscribe(realtimeStatus('cc-thread-$conversationId'));
    return channel;
  }

  @override
  Future<void> resetSession() async {
    await _removeChannels();
    // The inbox is filtered by RLS rather than by a subscription argument, so
    // it has to be re-joined under the new session's token.
    _subscribeInbox();
  }

  @override
  Future<void> close() async {
    await _removeChannels();
    await _messages.close();
    await _typing.close();
    await _receipts.close();
    await _reconnects.close();
  }

  Future<void> _removeChannels() async {
    final channels = [..._threadChannels.values, ?_inbox];
    _threadChannels.clear();
    _inbox = null;
    for (final channel in channels) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {
        // Tearing down a socket that is already gone is not a failure.
      }
    }
  }

  // ---------------------------------------------------------------- errors

  Future<List<Map<String, dynamic>>> _rpcRows(
    String name,
    Map<String, dynamic> params,
  ) async {
    try {
      final result = await _client.rpc(name, params: params);
      if (result is! List) return const [];
      return result
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } on PostgrestException catch (e) {
      throw ChatFailure(_readable(e));
    }
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// `send_message` raises with student-facing text already — the block gate,
  /// the rate limiter and the read-only check all say what happened.
  static String _readableSend(PostgrestException e) {
    if (e.code == '53400') {
      return 'You are sending messages too quickly. Wait a moment.';
    }
    if (e.code == '42501') {
      return e.message.isEmpty ? 'This chat is not available.' : e.message;
    }
    return _readable(e);
  }

  static String _readableJoin(PostgrestException e) {
    if (e.code == '23514') return 'This group is full.';
    return _readable(e);
  }

  static String _readable(PostgrestException e) =>
      e.message.isEmpty ? 'Something went wrong. Please try again.' : e.message;
}


// =====================================================================
// Unavailable
// =====================================================================

/// What [ChatRepository] resolves to when Supabase was never initialised.
///
/// Chat is a server feature: there is no offline story for it and no fixture
/// worth pretending with, so this reads as empty and refuses every write with
/// something the student can act on. It replaced an in-memory demo that
/// answered with generated threads and simulated replies — which made a
/// misconfigured build look like a working one.
class UnavailableChatRepository implements ChatRepository {
  const UnavailableChatRepository();

  static const _reason =
      'Chat is unavailable — the app is not connected to Campus Connect.';

  @override
  String get myId => '';

  @override
  Future<ChatListSnapshot> fetchChatList() async => ChatListSnapshot.empty;

  @override
  Future<List<Message>> fetchMessages(
    String conversationId, {
    int? beforeSeq,
    int limit = kMessagePageSize,
  }) async =>
      const [];

  @override
  Future<Message> sendMessage({
    required String conversationId,
    String body = '',
    Attachment? attachment,
    required String clientMsgId,
  }) =>
      throw const ChatFailure(_reason);

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) =>
      throw const ChatFailure(_reason);

  @override
  Future<int> markRead({
    required String conversationId,
    required int seq,
  }) async =>
      0;

  @override
  Future<int> totalUnread() async => 0;

  @override
  Future<String> openDirectConversation(User other) =>
      throw const ChatFailure(_reason);

  @override
  Future<void> setMuted({
    required String conversationId,
    required bool muted,
  }) async {}

  @override
  Future<void> clearHistory(String conversationId) async {}

  @override
  Future<void> leaveConversation(String conversationId) async {}

  @override
  Future<void> joinGroup(String conversationId) =>
      throw const ChatFailure(_reason);

  @override
  Future<List<User>> fetchMembers(String conversationId, {int limit = 60}) async =>
      const [];

  @override
  Stream<IncomingMessage> messages() => const Stream.empty();

  @override
  Stream<TypingSignal> typing() => const Stream.empty();

  @override
  Stream<ReadReceipt> readReceipts() => const Stream.empty();

  @override
  Stream<void> reconnections() => const Stream.empty();

  @override
  void watchThread(String conversationId) {}

  @override
  Future<void> notifyTyping(String conversationId) async {}

  @override
  Future<void> notifyRead({
    required String conversationId,
    required int seq,
  }) async {}

  @override
  Future<void> resetSession() async {}

  @override
  Future<void> close() async {}
}

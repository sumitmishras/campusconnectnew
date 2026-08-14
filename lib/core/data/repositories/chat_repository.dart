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
///
/// [userId] is who it was about. A group thread can have two people typing at
/// once, and without the id one of them stopping would clear the indicator for
/// both — which is one of the ways a "typing…" ends up describing nobody.
class TypingSignal {
  final String conversationId;
  final bool isTyping;
  final String userId;

  const TypingSignal({
    required this.conversationId,
    required this.isTyping,
    this.userId = '',
  });
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

  /// Asks for anything in [conversationId] this client has not seen yet.
  ///
  /// The repository knows how far it has read each thread, so this is a delta
  /// — not a reload. [headSeq] is the thread's head as some authority just
  /// reported it (a Realtime event, or `get_chat_list()` on the way back from
  /// a dropped socket); when it is at or below what this client already holds
  /// the call does nothing at all.
  ///
  /// Idempotent and safe to call from several places at once: concurrent
  /// requests for the same thread are coalesced into one fetch.
  void syncConversation(String conversationId, {int? headSeq});

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

  /// Tells the other members a message is being composed. Call it while the
  /// student types; the provider decides how often it is worth saying.
  Future<void> notifyTyping(String conversationId);

  /// The other half of [notifyTyping] — sent when the student stops, sends, or
  /// leaves. A receiver that misses it falls back to [kTypingTimeout].
  Future<void> notifyStoppedTyping(String conversationId);

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

/// How long a typing indicator survives on the receiver without being renewed.
///
/// Comfortably longer than [kTypingHeartbeat] so a healthy typist never
/// flickers, and short enough that a lost "stopped" broadcast clears by itself
/// rather than leaving a "typing…" that describes nobody.
const Duration kTypingTimeout = Duration(seconds: 6);

/// How often a keystroke is worth putting on the wire while someone is still
/// typing. Every keystroke would be thirty broadcasts for one sentence.
const Duration kTypingHeartbeat = Duration(seconds: 2);

/// Silence after the last keystroke before "stopped typing" is sent.
const Duration kTypingIdle = Duration(milliseconds: 2500);

// =====================================================================
// Supabase
// =====================================================================

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client, this._storage) {
    // The inbox cannot be joined until there is a session — see
    // [_subscribeInbox] for why joining early is the same as not joining at
    // all. This is what wakes it up when one appears.
    _authSub = _client.auth.onAuthStateChange.listen(_onAuthStateChange);
    unawaited(_joinInbox());
  }

  final SupabaseClient _client;
  final StorageRepository _storage;

  final _messages = StreamController<IncomingMessage>.broadcast();
  final _typing = StreamController<TypingSignal>.broadcast();
  final _receipts = StreamController<ReadReceipt>.broadcast();
  final _reconnects = StreamController<void>.broadcast();

  StreamSubscription<AuthState>? _authSub;

  RealtimeChannel? _inbox;

  /// Which student the inbox channel joined as. Realtime evaluates a
  /// `postgres_changes` subscription against the token the channel joined
  /// with, so a channel that outlives its session is a channel that silently
  /// stops matching rows.
  String? _inboxUserId;

  /// One ephemeral channel per open thread, carrying typing and read events.
  /// Insertion-ordered, and trimmed from the front — see [_threadChannel].
  final Map<String, RealtimeChannel> _threadChannels = {};

  /// The highest `seq` this client has actually seen in each thread. Every
  /// Realtime signal is turned into "fetch what is above this", which is what
  /// makes a burst of ten messages one round trip instead of ten, and what
  /// makes a duplicate signal cost nothing.
  final Map<String, int> _knownSeq = {};

  /// Threads with a fetch in flight, and the head that arrived while it was.
  final Set<String> _syncing = {};
  final Map<String, int> _pendingHead = {};

  /// Sends waiting on `send_message()`, per thread. The conversation row is
  /// updated inside that call, so this client hears about its own message
  /// before the RPC has answered — and would render it twice, next to the
  /// optimistic bubble that is already on screen.
  final Map<String, int> _inFlightSends = {};

  /// How far back a delta sync will page before giving up and letting the next
  /// full load reconcile. Four pages is 160 messages — more than a phone can
  /// miss between two heartbeats on any plausible network.
  static const int _maxSyncPages = 4;

  /// Thread channels are kept after the screen closes, so typing still shows
  /// in the chat list. Not forever, though: this bounds them to the threads
  /// actually being used.
  static const int _maxThreadChannels = 12;

  @override
  String get myId => _client.auth.currentUser?.id ?? '';

  // ------------------------------------------------------------- chat list

  @override
  Future<ChatListSnapshot> fetchChatList() async {
    final rows = await _rpcRows('get_chat_list', {'p_limit': 60});
    if (rows.isEmpty) return ChatListSnapshot.empty;

    // The first sighting of a thread establishes where "new" starts. Without
    // this the first Realtime signal in a thread nobody has opened would be
    // answered with its whole last page, every one of them counted as an
    // arrival. `putIfAbsent`, not assignment: a thread already on screen knows
    // better than the list does, and overwriting it here would swallow the
    // messages this load is meant to reveal.
    for (final row in rows) {
      final id = row['conversation_id'] as String?;
      if (id == null) continue;
      _knownSeq.putIfAbsent(id, () => _asInt(row['last_seq']));
    }

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
    final page = await _mapPage(rows);
    // Whatever a caller reads, this client has now seen — including the head
    // page an opening thread loads, which is what every later delta measures
    // itself against.
    for (final message in page) {
      _noteSeq(conversationId, message.seq);
    }
    return page;
  }

  /// Records that [seq] in [conversationId] is accounted for. Monotonic: an
  /// older page must not drag the watermark backwards.
  void _noteSeq(String conversationId, int seq) {
    if (seq <= 0) return;
    final known = _knownSeq[conversationId] ?? 0;
    if (seq > known) _knownSeq[conversationId] = seq;
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

    // The message row is only written once the bytes are safely in Storage —
    // a message pointing at an object that never arrived would render as a
    // permanent broken bubble on every other device.
    try {
      if (attachment != null) {
        realtimeLog('upload started: ${attachment.name} → $conversationId');
        final upload = await _storage.uploadChatAttachment(
          conversationId: conversationId,
          file: attachment,
        );
        realtimeLog('upload finished: ${upload.objectPath}');
        payload.add(upload.toPayload());
        stored = attachment.copyWith(
          bucket: StorageBuckets.chatMedia,
          objectPath: upload.objectPath,
          // Signed now so the sender's own bubble still renders after the
          // bytes are dropped, and so re-opening the thread shows the same
          // image everyone else sees rather than a placeholder.
          previewUrl: attachment.isPhoto
              ? await _storage.signedUrl(
                  StorageBuckets.chatMedia, upload.objectPath)
              : '',
          clearBytes: true,
        );
      }
    } on StorageFailure catch (e) {
      // Surfaced as a chat failure so the screen shows the reason the upload
      // was refused — too large, wrong type, no longer a member — rather than
      // a generic "could not be sent".
      throw ChatFailure(e.message);
    }

    _inFlightSends[conversationId] = (_inFlightSends[conversationId] ?? 0) + 1;
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
      final saved = ChatMapper.sentMessageFromRow(row, attachment: stored);
      // This client has seen its own message, so the Realtime signal that
      // `send_message()` set off on the way is already accounted for.
      _noteSeq(conversationId, saved.seq);
      realtimeLog('sent ${saved.id} seq=${saved.seq} in $conversationId');
      return saved;
    } on PostgrestException catch (e) {
      throw ChatFailure(_readableSend(e));
    } finally {
      final left = (_inFlightSends[conversationId] ?? 1) - 1;
      if (left <= 0) {
        _inFlightSends.remove(conversationId);
      } else {
        _inFlightSends[conversationId] = left;
      }
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

    // A soft delete moves no `seq` and touches no conversation row, so there
    // is nothing for the head-watcher to notice. Announcing it on the thread's
    // own channel is what makes the bubble turn into "this message was
    // deleted" for everyone looking at the thread right now; anyone who is not
    // sees it on the next load, from `deleted_at`.
    try {
      await _threadChannel(conversationId).sendBroadcastMessage(
        event: 'deleted',
        payload: {'user_id': myId, 'message_id': messageId},
      );
    } catch (_) {
      // Best effort — the database already holds the truth.
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
    unawaited(_joinInbox());
    return _messages.stream;
  }

  @override
  Stream<TypingSignal> typing() => _typing.stream;

  @override
  Stream<ReadReceipt> readReceipts() => _receipts.stream;

  @override
  Stream<void> reconnections() => _reconnects.stream;

  /// Re-joins the inbox whenever the session behind it changes.
  ///
  /// `Supabase.initialize()` does **not** wait for the stored session to be
  /// restored — it starts `recoverSession()` and returns — so at the moment
  /// the provider tree is built the socket is still holding the anon key.
  /// A `postgres_changes` subscription is authorised against the token the
  /// channel joined with, and every chat policy in `0008` is `to
  /// authenticated`; a channel joined as `anon` therefore matches no row,
  /// ever, while still reporting `subscribed`. That is a channel that looks
  /// healthy and delivers nothing.
  void _onAuthStateChange(AuthState state) {
    final id = state.session?.user.id;
    if (state.event == AuthChangeEvent.signedOut || id == null) {
      if (_inboxUserId != null) {
        realtimeLog('session ended — leaving cc-inbox');
        unawaited(_removeChannels());
      }
      return;
    }
    if (id == _inboxUserId) return;
    unawaited(_joinInbox());
  }

  /// One channel for every thread this student is in. Realtime honours RLS, so
  /// `conversations_read` already limits it to their own threads — no filter
  /// is needed and none would be correct, since the set of threads changes as
  /// they join things.
  ///
  /// **Why the live signal is `conversations` and not `messages`.**
  /// `public.messages` is HASH partitioned (0004). Supabase Realtime decodes
  /// the WAL with `wal2json` and matches each change against
  /// `realtime.subscription.entity` by exact regclass — and a row inserted
  /// into `messages` is physically written to `messages_p7`, so it is
  /// `messages_p7` that comes out of logical decoding. It never equals the
  /// `public.messages` the client subscribed to, and the event is dropped
  /// inside Realtime before it reaches any socket. `publish_via_partition_root
  /// = true` does not rescue this: it is a `pgoutput` feature, and all it does
  /// here is hide the partitions from `pg_publication_tables`, which is where
  /// Realtime builds its `add-tables` filter from.
  ///
  /// `public.conversations` is not partitioned, is already published, already
  /// carries `REPLICA IDENTITY FULL`, and `send_message()` updates it twice in
  /// the same transaction as the INSERT — once to allocate `seq`, once for the
  /// preview. So its UPDATE is an exact, RLS-scoped, once-per-message signal
  /// carrying the new head. The message itself is then read back through
  /// `get_messages()`, which is where the sender's name, the attachment rows
  /// and the signed URLs come from — none of which are in the WAL row anyway.
  ///
  /// The `messages` bindings are kept below as a fast path. They cost nothing
  /// when they never fire, they route into the same idempotent delta sync, and
  /// they start working by themselves if the table is ever de-partitioned.
  Future<void> _joinInbox() async {
    final me = myId;
    if (me.isEmpty) return;
    if (_inbox != null && _inboxUserId == me) return;

    await _removeInbox();
    _inboxUserId = me;
    realtimeLog('joining cc-inbox as $me');

    _inbox = _client.channel('cc-inbox')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'conversations',
        callback: _onConversationChanged,
      )
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
        // Realtime re-joins on its own after the socket drops, but replays
        // nothing. Everything said in between exists only in Postgres.
        if (!_reconnects.isClosed) _reconnects.add(null);
      }));
  }

  /// The head of a thread moved. That is one message — or several, if two
  /// landed between decoding runs — so it is answered with a delta rather than
  /// with an assumption about how many.
  void _onConversationChanged(PostgresChangePayload payload) {
    final row = payload.newRecord;
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) return;

    final head = _asInt(row['last_seq']);
    realtimeLog('conversation $id head=$head (known ${_knownSeq[id]})');
    syncConversation(id, headSeq: head > 0 ? head : null);
  }

  /// The `messages` binding, when a deployment delivers it. An insert is just
  /// another way of learning the head moved; an update — a soft delete from
  /// this student's other device, most often — has to replace a bubble that is
  /// already on screen, which no head watcher can express.
  void _onMessageChanged(
    PostgresChangePayload payload, {
    required bool isUpdate,
  }) {
    final row = payload.newRecord;
    final conversationId = row['conversation_id'] as String?;
    final seq = _asInt(row['seq']);
    if (conversationId == null || seq <= 0) return;

    realtimeLog(
      'message ${isUpdate ? 'UPDATE' : 'INSERT'} seq=$seq in $conversationId',
    );

    if (isUpdate) {
      unawaited(_emitEnriched(conversationId, seq, isUpdate: true));
      return;
    }
    syncConversation(conversationId, headSeq: seq);
  }

  @override
  void syncConversation(String conversationId, {int? headSeq}) {
    if (conversationId.isEmpty || _messages.isClosed) return;

    final known = _knownSeq[conversationId];
    if (headSeq != null && known != null && headSeq <= known) return;

    // 0 means "head unknown, go and look". Coalescing on the maximum keeps a
    // burst of ten inserts to one fetch rather than ten.
    final head = headSeq ?? 0;
    final pending = _pendingHead[conversationId];
    _pendingHead[conversationId] =
        pending == null || head > pending ? head : pending;

    if (_syncing.contains(conversationId)) return;
    unawaited(_drainSync(conversationId));
  }

  Future<void> _drainSync(String conversationId) async {
    _syncing.add(conversationId);
    try {
      while (_pendingHead.containsKey(conversationId)) {
        final head = _pendingHead.remove(conversationId)!;
        await _emitNewMessages(conversationId, head > 0 ? head : null);
      }
    } finally {
      _syncing.remove(conversationId);
    }
  }

  /// Reads everything above this client's watermark and emits it oldest-first.
  Future<void> _emitNewMessages(String conversationId, int? headSeq) async {
    final known = _knownSeq[conversationId];

    try {
      // A thread this client has never read anything from — one it was added
      // to a moment ago, say. There is no watermark to measure against, so the
      // arrival itself is all it can honestly report; the provider re-reads the
      // chat list when it does not recognise the thread.
      if (known == null) {
        final page = await _readPage(conversationId, null, 1);
        _emit(conversationId, page);
        return;
      }

      if (headSeq != null && headSeq <= known) return;

      final fresh = <Message>[];
      int? before;
      for (var page = 0; page < _maxSyncPages; page++) {
        final rows = await _readPage(conversationId, before, kMessagePageSize);
        if (rows.isEmpty) break;

        // `_readPage` answers oldest-first.
        final newer = [
          for (final m in rows)
            if (m.seq > known) m,
        ];
        fresh.insertAll(0, newer);

        // The page reached down into what is already held, so the gap is
        // closed.
        if (newer.length < rows.length) break;
        before = rows.first.seq;
        if (before <= known + 1) break;
      }

      _emit(conversationId, fresh);
    } catch (_) {
      // A thread that cannot be re-read is one this student is not entitled to
      // any more; the next full load will agree.
    }
  }

  /// A page, without touching the watermark — [_emit] owns that, so a fetch
  /// made to *compute* the delta cannot erase it first.
  Future<List<Message>> _readPage(
    String conversationId,
    int? beforeSeq,
    int limit,
  ) async {
    final rows = await _rpcRows('get_messages', {
      'p_conversation_id': conversationId,
      'p_before_seq': beforeSeq,
      'p_limit': limit,
    });
    return _mapPage(rows);
  }

  void _emit(String conversationId, List<Message> messages) {
    if (messages.isEmpty) return;
    final sending = (_inFlightSends[conversationId] ?? 0) > 0;

    for (final message in messages) {
      if (_messages.isClosed) return;
      _noteSeq(conversationId, message.seq);

      // This client's own message, read back while its `send_message()` call
      // is still in flight: it is already on screen as the optimistic bubble
      // and the RPC's answer is what will replace it. Emitting it here would
      // put a second copy next to the first. A message from this student's
      // *other* device arrives with no send in flight and is delivered
      // normally.
      if (message.isMine && sending) continue;

      realtimeLog('deliver ${message.id} seq=${message.seq} '
          'in $conversationId${message.hasAttachment ? ' +attachment' : ''}');
      _messages.add(IncomingMessage(
        conversationId: conversationId,
        message: message,
      ));
    }
  }

  /// One message, re-read fully joined, replacing whatever copy is on screen.
  Future<void> _emitEnriched(
    String conversationId,
    int seq, {
    required bool isUpdate,
  }) async {
    try {
      final page = await _readPage(conversationId, seq + 1, 1);
      if (page.isEmpty || page.first.seq != seq || _messages.isClosed) return;
      _noteSeq(conversationId, seq);
      _messages.add(IncomingMessage(
        conversationId: conversationId,
        message: page.first,
        isUpdate: isUpdate,
      ));
    } catch (_) {
      // As above — not entitled to it, or it is gone.
    }
  }

  @override
  void watchThread(String conversationId) {
    if (conversationId.isEmpty) return;
    _threadChannel(conversationId);
  }

  @override
  Future<void> notifyTyping(String conversationId) async {
    await _sendTyping(conversationId, true);
  }

  @override
  Future<void> notifyStoppedTyping(String conversationId) async {
    await _sendTyping(conversationId, false);
  }

  Future<void> _sendTyping(String conversationId, bool isTyping) async {
    if (conversationId.isEmpty) return;
    try {
      await _threadChannel(conversationId).sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': myId, 'typing': isTyping},
      );
    } catch (_) {
      // A lost keystroke notice is not worth an error. The receiver's timeout
      // covers a lost "stopped" the same way.
    }
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

  /// Typing, read receipts and delete notices live on a broadcast channel, so
  /// nothing ephemeral is written to Postgres. Memoised per thread, so
  /// navigating between two chats and back cannot stack up subscriptions.
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
          final from = payload['user_id'];
          if (from == myId || _typing.isClosed) return;
          // Older clients sent no flag at all; the presence of the event was
          // the signal.
          final isTyping = payload['typing'] as bool? ?? true;
          realtimeLog('typing=$isTyping from $from in $conversationId');
          _typing.add(TypingSignal(
            conversationId: conversationId,
            isTyping: isTyping,
            userId: from is String ? from : '',
          ));
        },
      )
      ..onBroadcast(
        event: 'read',
        callback: (payload) {
          if (payload['user_id'] == myId || _receipts.isClosed) return;
          final seq = _asInt(payload['seq']);
          if (seq <= 0) return;
          _receipts.add(ReadReceipt(conversationId: conversationId, seq: seq));
        },
      )
      ..onBroadcast(
        event: 'deleted',
        callback: (payload) {
          if (payload['user_id'] == myId || _messages.isClosed) return;
          final id = payload['message_id'];
          if (id is! String || id.isEmpty) return;
          unawaited(_emitDeleted(conversationId, id));
        },
      );

    _threadChannels[conversationId] = channel;
    channel.subscribe(realtimeStatus('cc-thread-$conversationId'));
    _trimThreadChannels(conversationId);
    return channel;
  }

  /// Re-reads a soft-deleted message so the bubble on screen becomes "this
  /// message was deleted" rather than staying as it was until the next load.
  Future<void> _emitDeleted(String conversationId, String messageId) async {
    try {
      final page = await _readPage(conversationId, null, kMessagePageSize);
      for (final message in page) {
        if (message.id != messageId) continue;
        if (_messages.isClosed) return;
        _messages.add(IncomingMessage(
          conversationId: conversationId,
          message: message,
          isUpdate: true,
        ));
        return;
      }
    } catch (_) {
      // Out of the loaded window, or no longer readable. The next load agrees.
    }
  }

  /// Keeps the number of live thread channels bounded. The one just used is
  /// never a candidate — it is the thread on screen.
  void _trimThreadChannels(String keep) {
    while (_threadChannels.length > _maxThreadChannels) {
      final oldest =
          _threadChannels.keys.firstWhere((k) => k != keep, orElse: () => '');
      if (oldest.isEmpty) return;
      final channel = _threadChannels.remove(oldest);
      if (channel == null) return;
      realtimeLog('dropping idle thread channel $oldest');
      unawaited(_drop(channel));
    }
  }

  Future<void> _drop(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (_) {
      // Tearing down a socket that is already gone is not a failure.
    }
  }

  @override
  Future<void> resetSession() async {
    await _removeChannels();
    // Watermarks belong to the session that read them: the next student's
    // threads have their own sequence numbers, and carrying these over would
    // hide their first messages.
    _knownSeq.clear();
    _pendingHead.clear();
    _inFlightSends.clear();
    // The inbox is scoped by RLS rather than by a subscription argument, so it
    // has to be re-joined under the new session's token.
    await _joinInbox();
  }

  @override
  Future<void> close() async {
    await _authSub?.cancel();
    _authSub = null;
    await _removeChannels();
    await _messages.close();
    await _typing.close();
    await _receipts.close();
    await _reconnects.close();
  }

  Future<void> _removeInbox() async {
    final channel = _inbox;
    _inbox = null;
    _inboxUserId = null;
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } catch (_) {
      // Tearing down a socket that is already gone is not a failure.
    }
  }

  Future<void> _removeChannels() async {
    final threads = [..._threadChannels.values];
    _threadChannels.clear();
    await _removeInbox();
    for (final channel in threads) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {
        // As above.
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
  void syncConversation(String conversationId, {int? headSeq}) {}

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
  Future<void> notifyStoppedTyping(String conversationId) async {}

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

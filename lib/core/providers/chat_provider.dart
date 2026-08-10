import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/repositories/chat_repository.dart';
import '../data/repositories/repositories.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';
import '../services/presence_service.dart';

/// Chats: direct threads and group threads.
///
/// Nothing in here knows whether it is talking to Postgres or to fixtures —
/// [ChatRepository] answers that, and [Repositories] chose which one at
/// startup. Reads come from `get_chat_list()` / `get_messages()`, writes go
/// through `send_message()` / `mark_read()`, and everything that arrives while
/// the app is open arrives over Realtime.
///
/// The provider holds the *rendered* state: which threads exist, which page of
/// each thread has been loaded, who is typing. It does not hold business rules
/// — the block gate, the rate limiter and the read pointer all live in SQL.
class ChatProvider with ChangeNotifier {
  ChatProvider({ChatRepository? repository})
      : _repo = repository ?? Repositories.chat {
    _load();
    _listen();
  }

  static const _uuid = Uuid();

  final ChatRepository _repo;

  final List<Chat> _chats = [];
  final List<GroupChat> _groupChats = [];

  /// Source id (club / community / study group) to conversation id. Screens
  /// navigate by the campus entity; every RPC takes the thread.
  final Map<String, String> _conversationBySource = {};

  bool _isLoading = false;
  String _query = '';

  /// Keyed by conversation id, with a timer that clears it — a typing
  /// indicator is only valid for a few seconds and the "stopped" broadcast can
  /// be lost.
  final Map<String, Timer> _typingTimers = {};
  final Set<String> _typingConversationIds = {};

  /// The thread currently on screen, so a message arriving in it is marked read
  /// rather than counted as unread.
  String? _openConversationId;

  StreamSubscription<IncomingMessage>? _messageSub;
  StreamSubscription<TypingSignal>? _typingSub;
  StreamSubscription<ReadReceipt>? _receiptSub;
  StreamSubscription<Set<String>>? _presenceSub;
  StreamSubscription<void>? _reconnectSub;

  /// Who the loaded threads belong to. The provider outlives a sign-out — it is
  /// above the auth gate in the tree — so this is what stops one student's
  /// threads from being shown to the next one on the same device.
  String? _sessionUserId;
  bool _sessionKnown = false;

  bool get isLoading => _isLoading;
  String get query => _query;

  List<Chat> get chats {
    final list = _query.isEmpty
        ? List<Chat>.from(_chats)
        : _chats
            .where((c) =>
                c.otherUser.name.toLowerCase().contains(_query.toLowerCase()) ||
                c.displayPreview
                    .toLowerCase()
                    .contains(_query.toLowerCase()) ||
                c.messages.any((m) =>
                    m.content.toLowerCase().contains(_query.toLowerCase())))
            .toList();
    _sortByActivity(list, (c) => c.lastTimestamp, (c) => c.isPinned);
    return list;
  }

  /// Group threads for every community, club and study group the student
  /// has joined, newest activity first.
  List<GroupChat> get groupChats {
    final list = _query.isEmpty
        ? List<GroupChat>.from(_groupChats)
        : _groupChats
            .where((g) =>
                g.name.toLowerCase().contains(_query.toLowerCase()) ||
                g.displayPreview
                    .toLowerCase()
                    .contains(_query.toLowerCase()) ||
                g.messages.any((m) =>
                    m.content.toLowerCase().contains(_query.toLowerCase())))
            .toList();
    _sortByActivity(list, (g) => g.lastTimestamp, (_) => false);
    return list;
  }

  int get totalUnread =>
      _chats.fold(0, (sum, c) => sum + (c.isMuted ? 0 : c.unreadCount)) +
      _groupChats.fold(0, (sum, g) => sum + (g.isMuted ? 0 : g.unreadCount));

  bool isTyping(String chatId) =>
      _typingConversationIds.contains(_conversationId(chatId));

  bool isMuted(String chatId) {
    final id = _conversationId(chatId);
    for (final c in _chats) {
      if (c.id == id) return c.isMuted;
    }
    for (final g in _groupChats) {
      if (g.conversationId == id) return g.isMuted;
    }
    return false;
  }

  // ------------------------------------------------------------- lifecycle

  Future<void> _load() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _repo.fetchChatList();
      _replace(snapshot);
    } catch (_) {
      // An unreachable chat list is an empty one; the tab renders its empty
      // state and pull-to-refresh is the way back.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pull to refresh, and after joining or leaving a group.
  Future<void> refresh() async {
    try {
      final snapshot = await _repo.fetchChatList();
      _replace(snapshot);
      notifyListeners();
    } catch (_) {
      // Keep what is on screen.
    }
  }

  void _replace(ChatListSnapshot snapshot) {
    // Anything already loaded is kept: a refresh should not throw away the
    // history of a thread the student has open.
    final loadedChats = {
      for (final c in _chats)
        if (c.isHydrated) c.id: c.messages,
    };
    final loadedGroups = {
      for (final g in _groupChats)
        if (g.isHydrated) g.conversationId: g,
    };

    _chats
      ..clear()
      ..addAll(snapshot.chats.map((c) {
        final messages = loadedChats[c.id];
        return messages == null
            ? c
            : c.copyWith(messages: messages, isHydrated: true);
      }));

    _groupChats
      ..clear()
      ..addAll(snapshot.groups.map((g) {
        final previous = loadedGroups[g.conversationId];
        return previous == null
            ? g
            : g.copyWith(
                messages: previous.messages,
                members: previous.members,
                isHydrated: true,
              );
      }));

    _conversationBySource
      ..clear()
      ..addEntries(_groupChats.map((g) => MapEntry(g.id, g.conversationId)));

    // The rows carry `user_presence`, which only catches up when
    // `expire_stale_presence()` next runs. The channel already knows who is
    // connected, and it reports *changes* — so a student who was online
    // before this list loaded would otherwise keep their stale "active 23
    // minutes ago" until they happened to disconnect.
    _applyPresence(PresenceService.instance.onlineIds);
  }

  void _listen() {
    _messageSub = _repo.messages().listen(_onIncoming);
    _typingSub = _repo.typing().listen(_onTyping);
    _receiptSub = _repo.readReceipts().listen(_onReadReceipt);
    _presenceSub = PresenceService.instance.changes.listen(_onPresence);
    // Everything said while the socket was down is missing rather than
    // pending: Realtime re-joins, it never replays.
    _reconnectSub = _repo.reconnections().listen((_) => unawaited(refresh()));
  }

  /// Called by the provider tree whenever the signed-in student changes.
  ///
  /// The first call is the session the constructor already loaded for. Any
  /// change after that — a sign-out, or a second account on the same phone —
  /// throws away every thread, message and unread count in memory before
  /// loading the new student's list.
  void syncCurrentUser(User? me) {
    final id = me?.id;
    if (!_sessionKnown) {
      _sessionKnown = true;
      _sessionUserId = id;
      return;
    }
    if (id == _sessionUserId) return;

    _sessionUserId = id;

    // Cleared without notifying — this runs inside the provider subtree's
    // build. The first frame after it reads as loading, which is correct, and
    // the microtask below does the notifying.
    _chats.clear();
    _groupChats.clear();
    _conversationBySource.clear();
    _typingConversationIds.clear();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _openConversationId = null;
    _query = '';
    _lastError = null;
    _isLoading = id != null;

    scheduleMicrotask(() async {
      // Per-thread channels belong to the session that opened them, and the
      // inbox has to be re-joined so Realtime filters it against the new token.
      await _repo.resetSession();
      if (id == null) {
        notifyListeners();
        return;
      }
      await _load();
    });
  }

  /// The online dot follows the presence channel, not `user_presence`: a phone
  /// that loses signal never writes a disconnect, and the table only catches up
  /// when `expire_stale_presence()` next runs.
  void _onPresence(Set<String> onlineIds) {
    if (_applyPresence(onlineIds)) notifyListeners();
  }

  /// Patches the loaded threads with what the channel currently says, and
  /// reports whether anything moved. Also called straight after a load — see
  /// [_replace].
  bool _applyPresence(Set<String> onlineIds) {
    var changed = false;
    for (var i = 0; i < _chats.length; i++) {
      final other = _chats[i].otherUser;
      // The privacy switch wins: a student who hid their active status stays
      // dark whatever the socket says.
      if (other.hideActiveStatus) continue;
      final online = onlineIds.contains(other.id);
      if (online == other.isOnline) continue;
      _chats[i] = _chats[i].copyWith(
        otherUser: other.copyWith(
          isOnline: online,
          lastActive: online ? DateTime.now() : other.lastActive,
        ),
      );
      changed = true;
    }
    return changed;
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _typingSub?.cancel();
    _receiptSub?.cancel();
    _presenceSub?.cancel();
    _reconnectSub?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _repo.close();
    super.dispose();
  }

  // ------------------------------------------------------------------ realtime

  void _onIncoming(IncomingMessage incoming) {
    final id = incoming.conversationId;
    final message = incoming.message;
    final isOpen = _openConversationId == id;

    // A change to a message — a soft delete, most often. It replaces the copy
    // on screen; if this thread has never loaded it there is nothing to update
    // and nothing to count, since an edit is not an arrival.
    if (incoming.isUpdate) {
      if (_replaceMessage(id, message)) notifyListeners();
      return;
    }

    final chatIndex = _chats.indexWhere((c) => c.id == id);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      if (_alreadyHave(chat.messages, message)) return;

      _chats[chatIndex] = chat.copyWith(
        // Only append to a thread that has its history: appending to an
        // unopened one would render a single bubble with a hole above it.
        messages: chat.isHydrated ? [...chat.messages, message] : null,
        unreadCount: isOpen ? 0 : chat.unreadCount + 1,
        previewText: message.preview,
        lastActivity: message.timestamp,
        lastSeq: message.seq > chat.lastSeq ? message.seq : chat.lastSeq,
      );
      _stopTyping(id);
      if (isOpen) _acknowledge(id, message.seq);
      notifyListeners();
      return;
    }

    final groupIndex = _groupChats.indexWhere((g) => g.conversationId == id);
    if (groupIndex != -1) {
      final group = _groupChats[groupIndex];
      if (_alreadyHave(group.messages, message)) return;

      _groupChats[groupIndex] = group.copyWith(
        messages: group.isHydrated ? [...group.messages, message] : null,
        unreadCount: isOpen ? 0 : group.unreadCount + 1,
        previewText: message.preview,
        lastActivity: message.timestamp,
        lastSeq: message.seq > group.lastSeq ? message.seq : group.lastSeq,
      );
      _stopTyping(id);
      if (isOpen) _acknowledge(id, message.seq);
      notifyListeners();
      return;
    }

    // A message in a thread this student was just added to — a club they
    // joined on another device, say. The list has to be re-read to learn what
    // the thread even is.
    unawaited(refresh());
  }

  /// Realtime can deliver the same insert twice after a reconnect, and a
  /// message this student sent is already on screen optimistically.
  static bool _alreadyHave(List<Message> messages, Message candidate) {
    for (final m in messages) {
      if (m.id == candidate.id) return true;
      if (candidate.seq > 0 && m.seq == candidate.seq) return true;
    }
    return false;
  }

  /// Swaps a message the thread already holds for a newer copy of itself.
  /// False when the thread is not loaded or has never seen it, in which case the
  /// caller treats it as an arrival.
  bool _replaceMessage(String conversationId, Message message) {
    List<Message> swap(List<Message> messages) => [
          for (final m in messages)
            m.id == message.id || (message.seq > 0 && m.seq == message.seq)
                ? message
                : m,
        ];

    final chatIndex = _chats.indexWhere((c) => c.id == conversationId);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      if (!_alreadyHave(chat.messages, message)) return false;
      final messages = swap(chat.messages);
      _chats[chatIndex] = chat.copyWith(
        messages: messages,
        previewText: messages.last.preview,
      );
      return true;
    }

    final groupIndex =
        _groupChats.indexWhere((g) => g.conversationId == conversationId);
    if (groupIndex != -1) {
      final group = _groupChats[groupIndex];
      if (!_alreadyHave(group.messages, message)) return false;
      final messages = swap(group.messages);
      _groupChats[groupIndex] = group.copyWith(
        messages: messages,
        previewText: messages.last.preview,
      );
      return true;
    }

    return false;
  }

  /// The other side read up to [receipt]`.seq`, so every message of this
  /// student's at or below it has been seen.
  ///
  /// Direct threads only. In a group the double tick means *every* member has
  /// read it, which one member's receipt cannot establish — that stays with
  /// `seen_by_all` from `get_messages()`. The unread count is not touched
  /// either: the thing being described is the reader's, not this device's.
  void _onReadReceipt(ReadReceipt receipt) {
    final index = _chats.indexWhere((c) => c.id == receipt.conversationId);
    if (index == -1) return;

    final chat = _chats[index];
    var changed = false;
    final messages = [
      for (final m in chat.messages)
        if (m.isMine && !m.isSeen && m.seq > 0 && m.seq <= receipt.seq)
          _seen(m, () => changed = true)
        else
          m,
    ];

    if (!changed) return;
    _chats[index] = chat.copyWith(messages: messages);
    notifyListeners();
  }

  static Message _seen(Message message, void Function() mark) {
    mark();
    return message.copyWith(isSeen: true);
  }

  void _onTyping(TypingSignal signal) {
    if (!signal.isTyping) {
      _stopTyping(signal.conversationId);
      notifyListeners();
      return;
    }

    _typingConversationIds.add(signal.conversationId);
    _typingTimers[signal.conversationId]?.cancel();
    _typingTimers[signal.conversationId] = Timer(kTypingTimeout, () {
      _stopTyping(signal.conversationId);
      notifyListeners();
    });
    notifyListeners();
  }

  void _stopTyping(String conversationId) {
    _typingConversationIds.remove(conversationId);
    _typingTimers.remove(conversationId)?.cancel();
  }

  // --------------------------------------------------------------- searching

  void search(String query) {
    _query = query.trim();
    notifyListeners();
  }

  Chat? chatById(String chatId) {
    for (final c in _chats) {
      if (c.id == chatId) return c;
    }
    return null;
  }

  String _conversationId(String id) => _conversationBySource[id] ?? id;

  static void _sortByActivity<T>(
    List<T> list,
    DateTime? Function(T) stamp,
    bool Function(T) pinned,
  ) {
    list.sort((a, b) {
      if (pinned(a) != pinned(b)) return pinned(a) ? -1 : 1;
      final sa = stamp(a);
      final sb = stamp(b);
      if (sa == null && sb == null) return 0;
      if (sa == null) return 1;
      if (sb == null) return -1;
      return sb.compareTo(sa);
    });
  }

  // ------------------------------------------------------------ direct chats

  /// Opens the thread with [user], creating it if this is the first message.
  ///
  /// Race-safe against a double tap on "Message":
  /// `get_or_create_direct_conversation` infers the unique index on
  /// `direct_key`, so two requests cannot produce two threads.
  Future<Chat?> openChatWith(User user) async {
    for (final c in _chats) {
      if (c.otherUser.id == user.id) return c;
    }

    try {
      final conversationId = await _repo.openDirectConversation(user);
      final existing = chatById(conversationId);
      if (existing != null) return existing;

      // The thread may already exist with history on it — the other student
      // wrote first, or this device has never loaded it — so it is fetched
      // rather than assumed empty.
      final messages = await _repo.fetchMessages(conversationId);
      final chat = Chat(
        id: conversationId,
        otherUser: user,
        messages: messages,
        isHydrated: true,
        lastSeq: messages.isEmpty ? 0 : messages.last.seq,
        previewText: messages.isEmpty ? '' : messages.last.preview,
        lastActivity: messages.isEmpty ? null : messages.last.timestamp,
      );
      _chats.insert(0, chat);
      notifyListeners();
      return chat;
    } on ChatFailure catch (e) {
      _lastError = e.message;
      notifyListeners();
      return null;
    }
  }

  String? _lastError;

  /// Set when the last action failed. Screens read it once to show a message.
  String? get lastError => _lastError;

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// Loads the thread's history the first time it is opened and moves the read
  /// pointer to its head.
  Future<void> openThread(String chatId) async {
    final id = _conversationId(chatId);
    _openConversationId = id;
    // Joining here rather than on the first keystroke is what makes the other
    // side's "typing…" and read receipts arrive at all.
    _repo.watchThread(id);

    final index = _chats.indexWhere((c) => c.id == id);
    if (index == -1) return;

    if (!_chats[index].isHydrated) {
      try {
        final messages = await _repo.fetchMessages(id);
        final current = _chats.indexWhere((c) => c.id == id);
        if (current == -1) return;
        _chats[current] =
            _chats[current].copyWith(messages: messages, isHydrated: true);
      } catch (_) {
        // An empty thread is what an unreachable one looks like; the empty
        // state already covers it.
      }
    }

    markAsRead(id);
    notifyListeners();
  }

  void closeThread(String chatId) {
    if (_openConversationId == _conversationId(chatId)) {
      _openConversationId = null;
    }
  }

  /// Loads the page before the oldest message on screen.
  Future<void> loadOlderMessages(String chatId) async {
    final id = _conversationId(chatId);
    final index = _chats.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final chat = _chats[index];
    if (chat.messages.isEmpty) return;

    try {
      final older =
          await _repo.fetchMessages(id, beforeSeq: chat.messages.first.seq);
      if (older.isEmpty) return;
      final current = _chats.indexWhere((c) => c.id == id);
      if (current == -1) return;
      _chats[current] = _chats[current]
          .copyWith(messages: [...older, ..._chats[current].messages]);
      notifyListeners();
    } catch (_) {
      // Keep the page that is already there.
    }
  }

  Future<void> sendMessage(String chatId, String content,
      {Attachment? attachment}) async {
    final id = _conversationId(chatId);
    final index = _chats.indexWhere((c) => c.id == id);
    if (index == -1) return;

    // Generated here, before the first attempt, and reused if the send is
    // retried — that is what makes a dropped response idempotent rather than
    // a duplicate bubble.
    final clientMsgId = _uuid.v4();
    final pending = Message(
      id: clientMsgId,
      senderId: _repo.myId,
      senderName: 'You',
      content: content,
      timestamp: DateTime.now(),
      attachment: attachment,
      isMine: true,
      clientMsgId: clientMsgId,
      status: MessageStatus.sending,
    );

    _chats[index] = _chats[index].copyWith(
      messages: [..._chats[index].messages, pending],
      previewText: pending.preview,
      lastActivity: pending.timestamp,
      isHydrated: true,
    );
    notifyListeners();

    try {
      final saved = await _repo.sendMessage(
        conversationId: id,
        body: content,
        attachment: attachment,
        clientMsgId: clientMsgId,
      );
      _replacePending(id, clientMsgId, saved);
    } on ChatFailure catch (e) {
      _markFailed(id, clientMsgId);
      _lastError = e.message;
    } catch (_) {
      _markFailed(id, clientMsgId);
      _lastError = 'That message could not be sent.';
    }
    notifyListeners();
  }

  void _replacePending(String conversationId, String clientMsgId, Message saved) {
    final chatIndex = _chats.indexWhere((c) => c.id == conversationId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        messages: [
          for (final m in _chats[chatIndex].messages)
            m.clientMsgId == clientMsgId ? saved : m,
        ],
        lastSeq: saved.seq,
        previewText: saved.preview,
        lastActivity: saved.timestamp,
      );
      return;
    }

    final groupIndex =
        _groupChats.indexWhere((g) => g.conversationId == conversationId);
    if (groupIndex == -1) return;
    _groupChats[groupIndex] = _groupChats[groupIndex].copyWith(
      messages: [
        for (final m in _groupChats[groupIndex].messages)
          m.clientMsgId == clientMsgId ? saved : m,
      ],
      lastSeq: saved.seq,
      previewText: saved.preview,
      lastActivity: saved.timestamp,
    );
  }

  void _markFailed(String conversationId, String clientMsgId) {
    final chatIndex = _chats.indexWhere((c) => c.id == conversationId);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        messages: [
          for (final m in _chats[chatIndex].messages)
            m.clientMsgId == clientMsgId
                ? m.copyWith(status: MessageStatus.failed)
                : m,
        ],
      );
      return;
    }

    final groupIndex =
        _groupChats.indexWhere((g) => g.conversationId == conversationId);
    if (groupIndex == -1) return;
    _groupChats[groupIndex] = _groupChats[groupIndex].copyWith(
      messages: [
        for (final m in _groupChats[groupIndex].messages)
          m.clientMsgId == clientMsgId
              ? m.copyWith(status: MessageStatus.failed)
              : m,
      ],
    );
  }

  /// Shares a photo or document in a direct chat. Files over the size limit
  /// are rejected before they reach here (see `AttachmentService`).
  Future<void> sendAttachment(String chatId, Attachment file) =>
      sendMessage(chatId, '', attachment: file);

  /// Sends a failed message again, reusing its original `client_msg_id`.
  ///
  /// That id is what makes this safe: if the first attempt actually reached
  /// Postgres and only the response was lost, `send_message()` returns the
  /// message it already stored instead of posting a second bubble.
  Future<void> retrySend(String chatId, Message message) async {
    if (message.status != MessageStatus.failed) return;
    final id = _conversationId(chatId);
    final clientMsgId =
        message.clientMsgId.isEmpty ? message.id : message.clientMsgId;

    _updateMessage(id, clientMsgId,
        (m) => m.copyWith(status: MessageStatus.sending));
    _lastError = null;
    notifyListeners();

    try {
      final saved = await _repo.sendMessage(
        conversationId: id,
        body: message.content,
        attachment: message.attachment,
        clientMsgId: clientMsgId,
      );
      _replacePending(id, clientMsgId, saved);
    } on ChatFailure catch (e) {
      _markFailed(id, clientMsgId);
      _lastError = e.message;
    } catch (_) {
      _markFailed(id, clientMsgId);
      _lastError = 'That message could not be sent.';
    }
    notifyListeners();
  }

  /// Applies [change] to whichever thread holds the message with this
  /// `client_msg_id`.
  void _updateMessage(
    String conversationId,
    String clientMsgId,
    Message Function(Message) change,
  ) {
    List<Message> apply(List<Message> messages) => [
          for (final m in messages)
            m.clientMsgId == clientMsgId ? change(m) : m,
        ];

    final chatIndex = _chats.indexWhere((c) => c.id == conversationId);
    if (chatIndex != -1) {
      _chats[chatIndex] =
          _chats[chatIndex].copyWith(messages: apply(_chats[chatIndex].messages));
      return;
    }

    final groupIndex =
        _groupChats.indexWhere((g) => g.conversationId == conversationId);
    if (groupIndex == -1) return;
    _groupChats[groupIndex] = _groupChats[groupIndex]
        .copyWith(messages: apply(_groupChats[groupIndex].messages));
  }

  /// Tells the other side a message is being typed. Ephemeral — it travels
  /// over a Realtime broadcast channel and is never written to Postgres.
  void notifyTyping(String chatId) {
    unawaited(_repo.notifyTyping(_conversationId(chatId)));
  }

  void markAsRead(String chatId) {
    final id = _conversationId(chatId);
    final index = _chats.indexWhere((c) => c.id == id);
    if (index == -1) return;

    final chat = _chats[index];
    final head = chat.lastMessage?.seq ?? chat.lastSeq;
    if (chat.unreadCount == 0 && head == 0) return;

    _chats[index] = chat.copyWith(unreadCount: 0);
    _acknowledge(id, head);
    notifyListeners();
  }

  void _acknowledge(String conversationId, int seq) {
    if (seq <= 0) return;
    unawaited(_repo
        .markRead(conversationId: conversationId, seq: seq)
        .catchError((_) => 0));
    // Turns the sender's tick over while they are still looking at the thread;
    // `mark_read` above is what the next load reads back.
    unawaited(_repo.notifyRead(conversationId: conversationId, seq: seq));
  }

  Future<void> toggleMute(String chatId) async {
    final id = _conversationId(chatId);
    final next = !isMuted(chatId);

    final chatIndex = _chats.indexWhere((c) => c.id == id);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(isMuted: next);
    } else {
      final groupIndex = _groupChats.indexWhere((g) => g.conversationId == id);
      if (groupIndex == -1) return;
      _groupChats[groupIndex] =
          _groupChats[groupIndex].copyWith(isMuted: next);
    }
    notifyListeners();

    try {
      await _repo.setMuted(conversationId: id, muted: next);
    } catch (_) {
      // The switch stays where the student put it; the next load reconciles.
    }
  }

  Future<void> clearMessages(String chatId) async {
    final id = _conversationId(chatId);
    final index = _chats.indexWhere((c) => c.id == id);
    if (index == -1) return;

    _chats[index] = _chats[index]
        .copyWith(messages: const [], unreadCount: 0, previewText: '');
    notifyListeners();

    try {
      await _repo.clearHistory(id);
    } on ChatFailure catch (e) {
      _lastError = e.message;
      notifyListeners();
    }
  }

  /// Removes the thread from this student's list. The other side keeps theirs —
  /// `leave_group` sets `left_at`, it does not delete the conversation.
  Future<void> deleteChat(String chatId) async {
    final id = _conversationId(chatId);
    _chats.removeWhere((c) => c.id == id);
    _stopTyping(id);
    notifyListeners();

    try {
      await _repo.leaveConversation(id);
    } catch (_) {
      // Already gone, or gone on the next load.
    }
  }

  /// Soft-deletes one message. Only its sender, or a group admin, may.
  Future<void> deleteMessage(String chatId, Message message) async {
    final id = _conversationId(chatId);
    try {
      await _repo.deleteMessage(conversationId: id, messageId: message.id);
    } on ChatFailure catch (e) {
      _lastError = e.message;
      notifyListeners();
      return;
    }

    final chatIndex = _chats.indexWhere((c) => c.id == id);
    if (chatIndex != -1) {
      _chats[chatIndex] = _chats[chatIndex].copyWith(
        messages: [
          for (final m in _chats[chatIndex].messages)
            m.id == message.id ? m.copyWith(isDeleted: true, content: '') : m,
        ],
      );
      notifyListeners();
      return;
    }

    final groupIndex = _groupChats.indexWhere((g) => g.conversationId == id);
    if (groupIndex == -1) return;
    _groupChats[groupIndex] = _groupChats[groupIndex].copyWith(
      messages: [
        for (final m in _groupChats[groupIndex].messages)
          m.id == message.id ? m.copyWith(isDeleted: true, content: '') : m,
      ],
    );
    notifyListeners();
  }

  // ------------------------------------------------------------ group chats

  GroupChat? groupChatById(String id) {
    final conversationId = _conversationId(id);
    for (final g in _groupChats) {
      if (g.conversationId == conversationId || g.id == id) return g;
    }
    return null;
  }

  bool hasGroupChat(String id) => groupChatById(id) != null;

  /// Called when the student joins a community, club or study group.
  ///
  /// The membership write itself belongs to `CampusProvider` — against
  /// Supabase, joining a club and appearing in its chat are the *same* INSERT
  /// into `conversation_members`, so doing it twice would be wrong. This adds
  /// the thread to the list and then reconciles with the server.
  GroupChat joinGroupChat({
    required String id,
    required String name,
    required GroupKind kind,
    required String description,
    required int memberCount,
    String? conversationId,
  }) {
    final existing = groupChatById(id);
    if (existing != null) return existing;

    final threadId = conversationId ?? id;
    final group = GroupChat(
      id: id,
      conversationId: threadId,
      name: name,
      kind: kind,
      description: description,
      memberCount: memberCount,
      members: const [],
      messages: const [],
    );

    _groupChats.insert(0, group);
    _conversationBySource[id] = threadId;
    notifyListeners();

    // Pull the real thread: its history, its member list and the counts the
    // triggers just updated.
    unawaited(_hydrateGroup(threadId));
    return group;
  }

  Future<void> _hydrateGroup(String conversationId) async {
    try {
      final results = await Future.wait([
        _repo.fetchMessages(conversationId),
        _repo.fetchMembers(conversationId),
      ]);

      final index =
          _groupChats.indexWhere((g) => g.conversationId == conversationId);
      if (index == -1) return;

      _groupChats[index] = _groupChats[index].copyWith(
        messages: results[0] as List<Message>,
        members: results[1] as List<User>,
        isHydrated: true,
      );
      notifyListeners();
    } catch (_) {
      // The thread stays in the list with what it was created with.
    }
  }

  /// Called when the student leaves — the thread disappears from Chats.
  ///
  /// Like [joinGroupChat], the membership write belongs to `CampusProvider`.
  void leaveGroupChat(String id) {
    final conversationId = _conversationId(id);
    _groupChats.removeWhere(
        (g) => g.conversationId == conversationId || g.id == id);
    _conversationBySource.remove(id);
    _stopTyping(conversationId);
    notifyListeners();
  }

  /// Loads a group thread's history and members the first time it is opened.
  Future<void> openGroupThread(String groupId) async {
    final group = groupChatById(groupId);
    if (group == null) return;

    _openConversationId = group.conversationId;
    _repo.watchThread(group.conversationId);

    if (!group.isHydrated) {
      await _hydrateGroup(group.conversationId);
    } else if (group.members.isEmpty) {
      unawaited(_hydrateGroup(group.conversationId));
    }

    markGroupAsRead(groupId);
  }

  Future<void> sendGroupMessage(String groupId, String content,
      {Attachment? attachment}) async {
    final group = groupChatById(groupId);
    if (group == null) return;
    final id = group.conversationId;

    final clientMsgId = _uuid.v4();
    final pending = Message(
      id: clientMsgId,
      senderId: _repo.myId,
      senderName: 'You',
      content: content,
      timestamp: DateTime.now(),
      attachment: attachment,
      isMine: true,
      clientMsgId: clientMsgId,
      status: MessageStatus.sending,
    );

    final index = _groupChats.indexWhere((g) => g.conversationId == id);
    if (index == -1) return;
    _groupChats[index] = _groupChats[index].copyWith(
      messages: [..._groupChats[index].messages, pending],
      previewText: pending.preview,
      lastActivity: pending.timestamp,
      isHydrated: true,
    );
    notifyListeners();

    try {
      final saved = await _repo.sendMessage(
        conversationId: id,
        body: content,
        attachment: attachment,
        clientMsgId: clientMsgId,
      );
      _replacePending(id, clientMsgId, saved);
    } on ChatFailure catch (e) {
      _markFailed(id, clientMsgId);
      _lastError = e.message;
    } catch (_) {
      _markFailed(id, clientMsgId);
      _lastError = 'That message could not be sent.';
    }
    notifyListeners();
  }

  /// Shares a photo or document in a group thread.
  Future<void> sendGroupAttachment(String groupId, Attachment file) =>
      sendGroupMessage(groupId, '', attachment: file);

  void markGroupAsRead(String groupId) {
    final conversationId = _conversationId(groupId);
    final index =
        _groupChats.indexWhere((g) => g.conversationId == conversationId);
    if (index == -1) return;

    final group = _groupChats[index];
    final head = group.lastMessage?.seq ?? group.lastSeq;
    if (group.unreadCount == 0 && head == 0) return;

    _groupChats[index] = group.copyWith(unreadCount: 0);
    _acknowledge(conversationId, head);
    notifyListeners();
  }

  Future<void> clearGroupMessages(String groupId) async {
    final conversationId = _conversationId(groupId);
    final index =
        _groupChats.indexWhere((g) => g.conversationId == conversationId);
    if (index == -1) return;

    _groupChats[index] = _groupChats[index]
        .copyWith(messages: const [], unreadCount: 0, previewText: '');
    notifyListeners();

    try {
      await _repo.clearHistory(conversationId);
    } on ChatFailure catch (e) {
      _lastError = e.message;
      notifyListeners();
    }
  }
}

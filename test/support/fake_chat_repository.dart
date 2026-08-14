import 'dart:async';

import 'package:campus_connect/core/data/repositories/chat_repository.dart';
import 'package:campus_connect/core/mock_data/mock_data_generator.dart';
import 'package:campus_connect/core/models/chat_model.dart';
import 'package:campus_connect/core/models/user_model.dart';

/// In-memory [ChatRepository] for widget tests.
///
/// Chat has no offline implementation in the app any more — threads, sequence
/// numbers and read pointers all live in Postgres — so a test that drives the
/// Chats tab supplies this instead. Deliberately dumb: no simulated replies, no
/// timers, no randomness, so a test that fails did so because of the code under
/// test.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({ChatListSnapshot? seed, List<User>? members})
      : _members = members ?? const [] {
    final snapshot = seed ?? ChatListSnapshot.empty;
    for (final chat in snapshot.chats) {
      _chats[chat.id] = chat;
    }
    for (final group in snapshot.groups) {
      _groups[group.conversationId] = group;
    }
  }

  final Map<String, Chat> _chats = {};
  final Map<String, GroupChat> _groups = {};
  final List<User> _members;

  final _messages = StreamController<IncomingMessage>.broadcast();
  final _typing = StreamController<TypingSignal>.broadcast();
  final _receipts = StreamController<ReadReceipt>.broadcast();
  final _reconnects = StreamController<void>.broadcast();

  final List<String> calls = [];
  int _seq = 1000;

  @override
  String get myId => 'me';

  @override
  Future<ChatListSnapshot> fetchChatList() async => ChatListSnapshot(
        chats: _chats.values.toList(),
        groups: _groups.values.toList(),
      );

  @override
  Future<List<Message>> fetchMessages(
    String conversationId, {
    int? beforeSeq,
    int limit = kMessagePageSize,
  }) async {
    final all = _chats[conversationId]?.messages ??
        _groups[conversationId]?.messages ??
        const <Message>[];
    if (beforeSeq == null) return List.of(all);
    return all.where((m) => m.seq < beforeSeq).toList();
  }

  @override
  Future<Message> sendMessage({
    required String conversationId,
    String body = '',
    Attachment? attachment,
    required String clientMsgId,
  }) async {
    calls.add('send:$conversationId');

    final message = Message(
      id: 'server-$clientMsgId',
      senderId: myId,
      senderName: 'You',
      content: body,
      timestamp: DateTime.now(),
      // Stored attachments come back without their bytes, exactly as
      // `send_message()` plus a signed URL would leave them.
      attachment: attachment?.copyWith(
        bucket: 'chat-media',
        objectPath: 'test/${attachment.name}',
        clearBytes: true,
      ),
      seq: _seq++,
      isMine: true,
      clientMsgId: clientMsgId,
    );

    final chat = _chats[conversationId];
    if (chat != null) {
      _chats[conversationId] =
          chat.copyWith(messages: [...chat.messages, message]);
    }
    final group = _groups[conversationId];
    if (group != null) {
      _groups[conversationId] =
          group.copyWith(messages: [...group.messages, message]);
    }
    return message;
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    calls.add('delete:$conversationId:$messageId');
  }

  @override
  Future<int> markRead({
    required String conversationId,
    required int seq,
  }) async =>
      0;

  @override
  Future<int> totalUnread() async => 0;

  @override
  Future<String> openDirectConversation(User other) async {
    calls.add('openDirect:${other.id}');
    final existing = _chats.values.firstWhere(
      (c) => c.otherUser.id == other.id,
      orElse: () => Chat(id: '', otherUser: other, messages: const []),
    );
    if (existing.id.isNotEmpty) return existing.id;

    final id = 'conv-${other.id}';
    _chats[id] = Chat(id: id, otherUser: other, messages: const []);
    return id;
  }

  @override
  Future<void> setMuted({
    required String conversationId,
    required bool muted,
  }) async {
    calls.add('mute:$conversationId:$muted');
  }

  @override
  Future<void> clearHistory(String conversationId) async {
    calls.add('clearHistory:$conversationId');
    final chat = _chats[conversationId];
    if (chat != null) {
      _chats[conversationId] = chat.copyWith(messages: const []);
    }
    final group = _groups[conversationId];
    if (group != null) {
      _groups[conversationId] = group.copyWith(messages: const []);
    }
  }

  @override
  Future<void> leaveConversation(String conversationId) async {
    calls.add('leave:$conversationId');
    _chats.remove(conversationId);
    _groups.remove(conversationId);
  }

  @override
  Future<void> joinGroup(String conversationId) async {
    calls.add('join:$conversationId');
  }

  @override
  Future<List<User>> fetchMembers(String conversationId,
          {int limit = 60}) async =>
      _members.take(limit).toList();

  @override
  Stream<IncomingMessage> messages() => _messages.stream;

  @override
  void syncConversation(String conversationId, {int? headSeq}) {
    calls.add('sync:$conversationId:$headSeq');
  }

  @override
  Stream<TypingSignal> typing() => _typing.stream;

  @override
  Stream<ReadReceipt> readReceipts() => _receipts.stream;

  @override
  Stream<void> reconnections() => _reconnects.stream;

  @override
  void watchThread(String conversationId) {
    calls.add('watch:$conversationId');
  }

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
  Future<void> resetSession() async {
    calls.add('resetSession');
  }

  @override
  Future<void> close() async {
    await _messages.close();
    await _typing.close();
    await _receipts.close();
    await _reconnects.close();
  }

  /// Pushes a message the way Realtime would.
  void deliver(String conversationId, Message message,
          {bool isUpdate = false}) =>
      _messages.add(IncomingMessage(
        conversationId: conversationId,
        message: message,
        isUpdate: isUpdate,
      ));
}

/// A Chats tab consistent with the campus fixtures the other mock repositories
/// serve: one thread per group the demo student already belongs to, plus a
/// couple of direct threads.
///
/// The group ids are the campus entity ids, which is how `CampusProvider` and
/// `ChatProvider` agree on what a student has joined.
ChatListSnapshot fakeChatSeed() {
  MockDataGenerator.initialize();

  final groups = <GroupChat>[
    for (final c in MockDataGenerator.communities
        .where((c) => MockDataGenerator.preJoinedCommunityIds.contains(c.id)))
      GroupChat(
        id: c.id,
        conversationId: c.id,
        name: c.name,
        kind: GroupKind.community,
        description: c.description,
        memberCount: c.memberCount,
        members: const [],
        messages: const [],
      ),
    for (final club in MockDataGenerator.clubs
        .where((c) => MockDataGenerator.preJoinedClubIds.contains(c.id)))
      GroupChat(
        id: club.id,
        conversationId: club.id,
        name: club.name,
        kind: GroupKind.club,
        description: club.description,
        memberCount: club.memberCount,
        members: const [],
        messages: const [],
      ),
    for (final group in MockDataGenerator.studyGroups
        .where((g) => MockDataGenerator.preJoinedStudyGroupIds.contains(g.id)))
      GroupChat(
        id: group.id,
        conversationId: group.id,
        name: group.title,
        kind: GroupKind.studyGroup,
        description: group.description,
        memberCount: group.memberCount,
        members: const [],
        messages: const [],
      ),
  ];

  final chats = <Chat>[
    for (var i = 0; i < 2; i++)
      Chat(
        id: 'conv-direct-$i',
        otherUser: MockDataGenerator.students[i],
        messages: [
          Message(
            id: 'seed-$i',
            senderId: MockDataGenerator.students[i].id,
            senderName: MockDataGenerator.students[i].name,
            content: 'Are you coming to the lab session?',
            timestamp: DateTime.now().subtract(const Duration(hours: 2)),
            seq: 1,
            isSeen: true,
          ),
        ],
        isHydrated: true,
        lastSeq: 1,
      ),
  ];

  return ChatListSnapshot(chats: chats, groups: groups);
}

/// Members for a group info sheet.
List<User> fakeMembers() {
  MockDataGenerator.initialize();
  return MockDataGenerator.students.take(5).toList();
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/core/data/repositories/chat_repository.dart';
import 'package:campus_connect/core/models/chat_model.dart';
import 'package:campus_connect/core/models/user_model.dart';
import 'package:campus_connect/core/providers/chat_provider.dart';

/// Records what the provider asked the backend to do, and lets a test push
/// Realtime events at it. Deliberately not the mock repository: this is about
/// the provider's side of the contract, and the mock has behaviour of its own
/// (simulated replies) that would blur it.
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository({required this.snapshot});

  ChatListSnapshot snapshot;

  final _messages = StreamController<IncomingMessage>.broadcast();
  final _typing = StreamController<TypingSignal>.broadcast();
  final _receipts = StreamController<ReadReceipt>.broadcast();
  final _reconnects = StreamController<void>.broadcast();

  final List<String> calls = [];
  final Map<String, List<Message>> history = {};
  final List<String> watchedThreads = [];
  int resetCount = 0;

  /// Set to make the next send fail, the way a block or the rate limiter would.
  String? sendFailure;

  int fetchListCount = 0;
  int nextSeq = 1;
  bool closed = false;

  @override
  String get myId => 'me';

  @override
  Future<ChatListSnapshot> fetchChatList() async {
    fetchListCount++;
    return snapshot;
  }

  @override
  Future<List<Message>> fetchMessages(
    String conversationId, {
    int? beforeSeq,
    int limit = kMessagePageSize,
  }) async {
    calls.add('fetchMessages:$conversationId:$beforeSeq');
    final all = history[conversationId] ?? const <Message>[];
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
    calls.add('send:$conversationId:$body');
    final failure = sendFailure;
    if (failure != null) throw ChatFailure(failure);

    return Message(
      id: 'server-$clientMsgId',
      senderId: 'me',
      senderName: 'You',
      content: body,
      timestamp: DateTime.now(),
      seq: nextSeq++,
      isMine: true,
      clientMsgId: clientMsgId,
      attachment: attachment,
    );
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
  }) async {
    calls.add('markRead:$conversationId:$seq');
    return 0;
  }

  @override
  Future<int> totalUnread() async => 0;

  @override
  Future<String> openDirectConversation(User other) async {
    calls.add('openDirect:${other.id}');
    return 'conv-${other.id}';
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
  }

  @override
  Future<void> leaveConversation(String conversationId) async {
    calls.add('leave:$conversationId');
  }

  @override
  Future<void> joinGroup(String conversationId) async {
    calls.add('join:$conversationId');
  }

  @override
  Future<List<User>> fetchMembers(String conversationId,
      {int limit = 60}) async {
    calls.add('members:$conversationId');
    return const [];
  }

  @override
  Stream<IncomingMessage> messages() => _messages.stream;

  /// Stands in for the repository's delta sync. Records the head the provider
  /// believed the thread was at, and — when [syncDelivers] holds messages for
  /// it — pushes exactly what a real sync would have fetched.
  final Map<String, List<Message>> syncDelivers = {};

  @override
  void syncConversation(String conversationId, {int? headSeq}) {
    calls.add('sync:$conversationId:$headSeq');
    final pending = syncDelivers.remove(conversationId);
    if (pending == null) return;
    for (final message in pending) {
      _messages.add(IncomingMessage(
        conversationId: conversationId,
        message: message,
      ));
    }
  }

  @override
  Stream<TypingSignal> typing() => _typing.stream;

  @override
  Stream<ReadReceipt> readReceipts() => _receipts.stream;

  @override
  Stream<void> reconnections() => _reconnects.stream;

  /// Stands in for the inbox channel re-joining after the socket dropped.
  void reconnect() => _reconnects.add(null);

  @override
  void watchThread(String conversationId) {
    watchedThreads.add(conversationId);
  }

  @override
  Future<void> notifyTyping(String conversationId) async {
    calls.add('typing:$conversationId');
  }

  @override
  Future<void> notifyStoppedTyping(String conversationId) async {
    calls.add('stoppedTyping:$conversationId');
  }

  @override
  Future<void> notifyRead({
    required String conversationId,
    required int seq,
  }) async {
    calls.add('notifyRead:$conversationId:$seq');
  }

  @override
  Future<void> resetSession() async {
    resetCount++;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _messages.close();
    await _typing.close();
    await _receipts.close();
    await _reconnects.close();
  }

  void push(IncomingMessage message) => _messages.add(message);
  void pushTyping(TypingSignal signal) => _typing.add(signal);
  void pushReceipt(ReadReceipt receipt) => _receipts.add(receipt);
}

User _student(String id, String name) => User(
      id: id,
      name: name,
      username: name.toLowerCase(),
      phoneNumber: '',
      department: 'Computer Science',
      course: 'B.E. CSE',
      year: '3rd Year',
      bio: '',
      interests: const [],
      languages: const [],
      lookingFor: const [],
      profilePhotoUrl: '',
      lastActive: DateTime.now(),
    );

Message _incoming(String content, int seq) => Message(
      id: 'm$seq',
      senderId: 'other',
      senderName: 'Riya Sharma',
      content: content,
      timestamp: DateTime.now(),
      seq: seq,
    );

void main() {
  late _FakeChatRepository repo;
  late ChatProvider provider;

  final riya = _student('riya', 'Riya Sharma');

  setUp(() {
    repo = _FakeChatRepository(
      snapshot: ChatListSnapshot(
        chats: [
          Chat(
            id: 'conv-1',
            otherUser: riya,
            messages: const [],
            unreadCount: 2,
            previewText: 'See you there!',
            lastActivity: DateTime.now(),
            lastSeq: 7,
          ),
        ],
        groups: [
          GroupChat(
            id: 'club-1',
            conversationId: 'conv-club-1',
            name: 'CodeChef CU Chapter',
            kind: GroupKind.club,
            description: 'Weekly contests',
            memberCount: 40,
            members: const [],
            messages: const [],
            lastSeq: 3,
          ),
        ],
      ),
    );
    repo.history['conv-1'] = [
      _incoming('Hey!', 6),
      _incoming('See you there!', 7),
    ];
    provider = ChatProvider(repository: repo);
  });

  tearDown(() => provider.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('loading', () {
    test('the chat list arrives from the repository, not from memory',
        () async {
      await settle();

      expect(repo.fetchListCount, 1);
      expect(provider.isLoading, isFalse);
      expect(provider.chats.single.otherUser.name, 'Riya Sharma');
      expect(provider.groupChats.single.name, 'CodeChef CU Chapter');
      // 2 unread in the DM, none in the group.
      expect(provider.totalUnread, 2);
    });

    test('a dropped socket re-reads the list on the way back', () async {
      await settle();
      final loadsBefore = repo.fetchListCount;

      // Realtime re-joins after the phone comes out of a pocket, but it
      // replays nothing — whatever arrived in between is only in Postgres.
      repo.reconnect();
      await settle();

      expect(repo.fetchListCount, loadsBefore + 1);
    });

    test('the list preview renders before any history is loaded', () async {
      await settle();
      final chat = provider.chats.single;

      expect(chat.messages, isEmpty);
      expect(chat.displayPreview, 'See you there!');
    });

    test('opening a thread loads its page and acknowledges the head',
        () async {
      await settle();
      await provider.openThread('conv-1');

      expect(repo.calls, contains('fetchMessages:conv-1:null'));
      expect(repo.calls, contains('markRead:conv-1:7'));
      expect(provider.chats.single.messages.length, 2);
      expect(provider.chats.single.unreadCount, 0);
      expect(provider.totalUnread, 0);
    });

    test('a group thread pulls its history and its member list', () async {
      await settle();
      await provider.openGroupThread('club-1');

      // Navigated by the club id, fetched by the conversation id.
      expect(repo.calls, contains('fetchMessages:conv-club-1:null'));
      expect(repo.calls, contains('members:conv-club-1'));
    });

    test('older pages are keyset-paginated on seq', () async {
      await settle();
      await provider.openThread('conv-1');
      await provider.loadOlderMessages('conv-1');

      expect(repo.calls, contains('fetchMessages:conv-1:6'));
    });
  });

  group('sending', () {
    test('the bubble appears before the server answers, then is replaced',
        () async {
      await settle();
      await provider.openThread('conv-1');

      final send = provider.sendMessage('conv-1', 'On my way');
      // Optimistic: on screen already, marked as still in flight.
      final pending = provider.chats.single.messages.last;
      expect(pending.content, 'On my way');
      expect(pending.status, MessageStatus.sending);
      expect(pending.isMine, isTrue);

      await send;

      final saved = provider.chats.single.messages.last;
      expect(saved.status, MessageStatus.sent);
      expect(saved.id, startsWith('server-'));
      // The client id survives, which is what makes a retry idempotent.
      expect(saved.clientMsgId, pending.clientMsgId);
      expect(provider.chats.single.displayPreview, 'On my way');
    });

    test('a rejected send is marked failed and explains why', () async {
      await settle();
      await provider.openThread('conv-1');
      repo.sendFailure = 'This chat is not available';

      await provider.sendMessage('conv-1', 'Hello?');

      expect(provider.chats.single.messages.last.status, MessageStatus.failed);
      expect(provider.lastError, 'This chat is not available');
    });

    test('a group message is sent against the conversation, not the club',
        () async {
      await settle();
      await provider.sendGroupMessage('club-1', 'Practice at 6');

      expect(repo.calls, contains('send:conv-club-1:Practice at 6'));
      expect(provider.groupChatById('club-1')!.messages.last.content,
          'Practice at 6');
    });
  });

  group('realtime', () {
    test('a message in a closed thread counts as unread', () async {
      await settle();

      repo.push(IncomingMessage(
        conversationId: 'conv-1',
        message: _incoming('Are you coming?', 8),
      ));
      await settle();

      final chat = provider.chats.single;
      expect(chat.unreadCount, 3);
      expect(chat.displayPreview, 'Are you coming?');
      expect(chat.lastSeq, 8);
    });

    test('a message in the open thread is read immediately', () async {
      await settle();
      await provider.openThread('conv-1');
      repo.calls.clear();

      repo.push(IncomingMessage(
        conversationId: 'conv-1',
        message: _incoming('Are you coming?', 8),
      ));
      await settle();

      expect(provider.chats.single.unreadCount, 0);
      expect(provider.chats.single.messages.last.content, 'Are you coming?');
      expect(repo.calls, contains('markRead:conv-1:8'));
    });

    test('a redelivered message after a reconnect is not duplicated', () async {
      await settle();
      await provider.openThread('conv-1');
      final message = _incoming('Twice?', 8);

      repo.push(IncomingMessage(conversationId: 'conv-1', message: message));
      await settle();
      repo.push(IncomingMessage(conversationId: 'conv-1', message: message));
      await settle();

      final count = provider.chats.single.messages
          .where((m) => m.content == 'Twice?')
          .length;
      expect(count, 1);
    });

    test('typing shows against the club id as well as the conversation id',
        () async {
      await settle();
      expect(provider.isTyping('club-1'), isFalse);

      repo.pushTyping(
          const TypingSignal(conversationId: 'conv-club-1', isTyping: true));
      await settle();
      expect(provider.isTyping('club-1'), isTrue);

      repo.pushTyping(
          const TypingSignal(conversationId: 'conv-club-1', isTyping: false));
      await settle();
      expect(provider.isTyping('club-1'), isFalse);
    });
  });

  group('thread actions', () {
    test('muting writes through and stops counting toward the badge', () async {
      await settle();
      expect(provider.totalUnread, 2);

      await provider.toggleMute('conv-1');

      expect(provider.isMuted('conv-1'), isTrue);
      expect(repo.calls, contains('mute:conv-1:true'));
      expect(provider.totalUnread, 0);
    });

    test('clearing messages calls clear_my_history, not a delete', () async {
      await settle();
      await provider.openThread('conv-1');

      await provider.clearMessages('conv-1');

      expect(repo.calls, contains('clearHistory:conv-1'));
      expect(provider.chats.single.messages, isEmpty);
    });

    test('deleting a chat leaves the conversation', () async {
      await settle();
      await provider.deleteChat('conv-1');

      expect(repo.calls, contains('leave:conv-1'));
      expect(provider.chats, isEmpty);
    });

    test('deleting a message soft-deletes it in place', () async {
      await settle();
      await provider.openThread('conv-1');
      final target = provider.chats.single.messages.first;

      await provider.deleteMessage('conv-1', target);

      final after = provider.chats.single.messages.first;
      expect(repo.calls, contains('delete:conv-1:${target.id}'));
      expect(after.isDeleted, isTrue);
      expect(after.preview, 'This message was deleted');
    });

    test('opening a DM with a connection asks the backend for the thread',
        () async {
      await settle();
      final other = _student('kabir', 'Kabir Singh');

      final chat = await provider.openChatWith(other);

      expect(repo.calls, contains('openDirect:kabir'));
      expect(chat!.id, 'conv-kabir');
      expect(provider.chats.any((c) => c.id == 'conv-kabir'), isTrue);
    });

    test('an existing DM is reused rather than reopened', () async {
      await settle();
      final chat = await provider.openChatWith(riya);

      expect(chat!.id, 'conv-1');
      expect(repo.calls, isNot(contains('openDirect:riya')));
    });
  });

  group('groups', () {
    test('joining adds the thread and hydrates it from the conversation',
        () async {
      await settle();

      provider.joinGroupChat(
        id: 'community-9',
        conversationId: 'conv-community-9',
        name: 'Placement 2026',
        kind: GroupKind.community,
        description: 'Drive updates',
        memberCount: 120,
      );
      await settle();

      expect(provider.hasGroupChat('community-9'), isTrue);
      expect(repo.calls, contains('fetchMessages:conv-community-9:null'));
      expect(repo.calls, contains('members:conv-community-9'));
      // The membership write belongs to CampusProvider — doing it here too
      // would be a second INSERT into the same table.
      expect(repo.calls, isNot(contains('join:conv-community-9')));
    });

    test('leaving removes the thread and forgets its id mapping', () async {
      await settle();
      provider.leaveGroupChat('club-1');

      expect(provider.hasGroupChat('club-1'), isFalse);
      expect(provider.groupChats, isEmpty);
    });
  });

  group('search', () {
    test('matches the other student, the preview and loaded messages',
        () async {
      await settle();
      await provider.openThread('conv-1');

      provider.search('riya');
      expect(provider.chats, hasLength(1));

      provider.search('CodeChef');
      expect(provider.groupChats, hasLength(1));
      expect(provider.chats, isEmpty);

      provider.search('zzzzz');
      expect(provider.chats, isEmpty);
      expect(provider.groupChats, isEmpty);
    });
  });

  group('retrying', () {
    test('a failed message is sent again under its original client id',
        () async {
      await settle();
      await provider.openThread('conv-1');

      repo.sendFailure = 'You are sending messages too quickly.';
      await provider.sendMessage('conv-1', 'Are you there?');
      await settle();

      final failed = provider.chatById('conv-1')!.messages.last;
      expect(failed.status, MessageStatus.failed);

      repo.sendFailure = null;
      await provider.retrySend('conv-1', failed);
      await settle();

      final resent = provider.chatById('conv-1')!.messages.last;
      expect(resent.status, MessageStatus.sent);
      expect(resent.clientMsgId, failed.clientMsgId,
          reason: 'the same id is what makes a retry idempotent');
      expect(provider.chatById('conv-1')!.messages.where((m) => m.isMine),
          hasLength(1), reason: 'retried, not duplicated');
    });

    test('a message that did not fail is left alone', () async {
      await settle();
      await provider.openThread('conv-1');
      await provider.sendMessage('conv-1', 'Sent fine');
      await settle();

      final sent = provider.chatById('conv-1')!.messages.last;
      final before = repo.calls.where((c) => c.startsWith('send:')).length;
      await provider.retrySend('conv-1', sent);

      expect(repo.calls.where((c) => c.startsWith('send:')), hasLength(before));
    });
  });

  group('read receipts', () {
    test('opening a thread joins its channel', () async {
      await settle();
      await provider.openThread('conv-1');

      // Without this the other side's "typing…" and read events never arrive,
      // because nothing is subscribed to the thread's channel.
      expect(repo.watchedThreads, contains('conv-1'));
    });

    test('opening a group thread joins the conversation, not the club',
        () async {
      await settle();
      await provider.openGroupThread('club-1');

      expect(repo.watchedThreads, contains('conv-club-1'));
    });

    test('reading a thread tells the other side how far', () async {
      await settle();
      await provider.openThread('conv-1');

      expect(repo.calls, contains('markRead:conv-1:7'));
      expect(repo.calls, contains('notifyRead:conv-1:7'));
    });

    test('a receipt turns the tick over on messages already sent', () async {
      await settle();
      await provider.openThread('conv-1');
      await provider.sendMessage('conv-1', 'On my way');
      await settle();

      final sent = provider.chatById('conv-1')!.messages.last;
      expect(sent.isMine, isTrue);
      expect(sent.isSeen, isFalse);

      repo.pushReceipt(ReadReceipt(conversationId: 'conv-1', seq: sent.seq));
      await settle();

      expect(provider.chatById('conv-1')!.messages.last.isSeen, isTrue);
    });

    test('a receipt does not disturb the unread count', () async {
      await settle();
      repo.pushReceipt(const ReadReceipt(conversationId: 'conv-1', seq: 7));
      await settle();

      // The thread being described was read by the *other* student.
      expect(provider.chats.first.unreadCount, 2);
    });
  });

  group('message updates', () {
    test('a changed message replaces the one on screen', () async {
      await settle();
      await provider.openThread('conv-1');
      final before = provider.chatById('conv-1')!.messages.length;

      repo.push(IncomingMessage(
        conversationId: 'conv-1',
        isUpdate: true,
        message: Message(
          id: 'm7',
          senderId: 'other',
          senderName: 'Riya Sharma',
          content: '',
          timestamp: DateTime.now(),
          seq: 7,
          isDeleted: true,
        ),
      ));
      await settle();

      final messages = provider.chatById('conv-1')!.messages;
      expect(messages, hasLength(before), reason: 'replaced, not appended');
      expect(messages.last.isDeleted, isTrue);
      expect(provider.chats.first.unreadCount, 0,
          reason: 'an edit is not a new message');
    });
  });

  group('sessions', () {
    test('signing in as a different student drops the previous threads',
        () async {
      await settle();
      expect(provider.chats, isNotEmpty);

      provider.syncCurrentUser(_student('me', 'First Student'));
      repo.snapshot = ChatListSnapshot.empty;
      provider.syncCurrentUser(_student('someone-else', 'Second Student'));
      await settle();

      expect(provider.chats, isEmpty);
      expect(provider.groupChats, isEmpty);
      expect(repo.resetCount, 1, reason: 'realtime re-joined for the new token');
    });

    test('signing out clears the list without reloading it', () async {
      await settle();
      provider.syncCurrentUser(_student('me', 'First Student'));
      final loadsBefore = repo.fetchListCount;

      provider.syncCurrentUser(null);
      await settle();

      expect(provider.chats, isEmpty);
      expect(repo.fetchListCount, loadsBefore);
    });
  });

  test('disposing tears the repository down', () async {
    await settle();
    provider.dispose();
    await settle();
    expect(repo.closed, isTrue);

    // tearDown disposes whatever `provider` points at, so hand it a fresh one.
    provider = ChatProvider(
      repository: _FakeChatRepository(snapshot: ChatListSnapshot.empty),
    );
  });
}

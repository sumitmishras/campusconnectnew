import 'user_model.dart';

class Message {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final bool isSeen;

  Message({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.isSeen = false,
  });
}

class Chat {
  final String id;
  final User otherUser; // In a real app, this would be just IDs, but for mock UI it's easier to hold the user.
  final List<Message> messages;
  final int unreadCount;
  
  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;

  Chat({
    required this.id,
    required this.otherUser,
    required this.messages,
    this.unreadCount = 0,
  });

  Chat copyWith({
    List<Message>? messages,
    int? unreadCount,
  }) {
    return Chat(
      id: id,
      otherUser: otherUser,
      messages: messages ?? this.messages,
      unreadCount: unreadCount ?? this.unreadCount,
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

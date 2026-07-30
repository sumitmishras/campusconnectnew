import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_model.dart';
import '../mock_data/mock_data_generator.dart';

class ChatProvider with ChangeNotifier {
  List<Chat> _chats = [];
  bool _isLoading = false;

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;

  ChatProvider() {
    _loadChats();
  }

  Future<void> _loadChats() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800));

    if (MockDataGenerator.chats.isEmpty) {
      MockDataGenerator.initialize();
    }
    
    _chats = List.from(MockDataGenerator.chats);
    // Sort chats by most recent message
    _sortChats();
    
    _isLoading = false;
    notifyListeners();
  }

  void _sortChats() {
    _chats.sort((a, b) {
      if (a.lastMessage == null && b.lastMessage == null) return 0;
      if (a.lastMessage == null) return 1;
      if (b.lastMessage == null) return -1;
      return b.lastMessage!.timestamp.compareTo(a.lastMessage!.timestamp);
    });
  }

  void sendMessage(String chatId, String content) {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      final newMessage = Message(
        id: const Uuid().v4(),
        senderId: 'me', // Assuming 'me' is the current logged-in user for mock purposes
        content: content,
        timestamp: DateTime.now(),
        isSeen: false,
      );

      final updatedMessages = List<Message>.from(chat.messages)..add(newMessage);
      _chats[chatIndex] = chat.copyWith(messages: updatedMessages);
      
      _sortChats();
      notifyListeners();

      // Simulate reply from the other person
      _simulateReply(chatId);
    }
  }

  void _simulateReply(String chatId) {
    Future.delayed(const Duration(seconds: 2), () {
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        final chat = _chats[chatIndex];
        final replyMessage = Message(
          id: const Uuid().v4(),
          senderId: chat.otherUser.id,
          content: 'That sounds great! I agree.',
          timestamp: DateTime.now(),
          isSeen: false,
        );

        final updatedMessages = List<Message>.from(chat.messages)..add(replyMessage);
        _chats[chatIndex] = chat.copyWith(
          messages: updatedMessages,
          unreadCount: chat.unreadCount + 1,
        );
        
        _sortChats();
        notifyListeners();
      }
    });
  }

  void markAsRead(String chatId) {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex != -1) {
      final chat = _chats[chatIndex];
      if (chat.unreadCount > 0) {
        _chats[chatIndex] = chat.copyWith(unreadCount: 0);
        notifyListeners();
      }
    }
  }
}

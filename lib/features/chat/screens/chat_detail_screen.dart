import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/models/chat_model.dart';
import 'package:intl/intl.dart';

class ChatDetailScreen extends StatefulWidget {
  final Chat chat;
  const ChatDetailScreen({super.key, required this.chat});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    
    final provider = context.read<ChatProvider>();
    provider.sendMessage(widget.chat.id, _controller.text.trim());
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();
    
    // Find the latest chat data
    final currentChat = chatProvider.chats.firstWhere((c) => c.id == widget.chat.id, orElse: () => widget.chat);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(currentChat.otherUser.profilePhotoUrl),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(currentChat.otherUser.name, style: theme.textTheme.titleMedium),
                if (currentChat.otherUser.isOnline)
                  Text('Online', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(LucideIcons.phone), onPressed: () {}),
          IconButton(icon: const Icon(LucideIcons.moreVertical), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true, // Show latest messages at the bottom
              padding: const EdgeInsets.all(16),
              itemCount: currentChat.messages.length,
              itemBuilder: (context, index) {
                // Messages are naturally sorted oldest to newest. Since we reverse the list,
                // we need to access them in reverse order.
                final msg = currentChat.messages[currentChat.messages.length - 1 - index];
                final isMe = msg.senderId == 'current_user'; // Assumption

                return _buildMessageBubble(msg, isMe, theme);
              },
            ),
          ),
          _buildMessageInput(theme),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, bool isMe, ThemeData theme) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? theme.primaryColor : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(20),
            bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(0),
          ),
          border: isMe ? null : Border.all(color: theme.dividerColor.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.content,
              style: TextStyle(
                color: isMe ? Colors.white : theme.textTheme.bodyLarge?.color,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('hh:mm a').format(msg.timestamp),
              style: TextStyle(
                color: isMe ? Colors.white70 : theme.textTheme.bodySmall?.color,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(LucideIcons.paperclip, color: theme.textTheme.bodySmall?.color),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: theme.primaryColor,
              child: IconButton(
                icon: const Icon(LucideIcons.send, color: Colors.white, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/chat_provider.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Chats', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: chatProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : chatProvider.chats.isEmpty
              ? Center(child: Text('No active chats.', style: theme.textTheme.bodyLarge))
              : ListView.builder(
                  itemCount: chatProvider.chats.length,
                  itemBuilder: (context, index) {
                    final chat = chatProvider.chats[index];
                    final isUnread = chat.unreadCount > 0;
                    
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundImage: NetworkImage(chat.otherUser.profilePhotoUrl),
                          ),
                          if (chat.otherUser.isOnline)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        chat.otherUser.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        chat.lastMessage?.content ?? 'No messages yet',
                        style: TextStyle(
                          fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                          color: isUnread ? theme.textTheme.bodyLarge?.color : theme.textTheme.bodySmall?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (chat.lastMessage != null)
                            Text(
                              _formatTime(chat.lastMessage!.timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: isUnread ? theme.primaryColor : theme.textTheme.bodySmall?.color,
                                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          if (isUnread) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                chat.unreadCount.toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () {
                        chatProvider.markAsRead(chat.id);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatDetailScreen(chat: chat),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day}/${time.month}';
  }
}

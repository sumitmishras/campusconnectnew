import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import 'chat_detail_screen.dart';
import 'group_chat_screen.dart';

enum _ChatFilter { all, direct, groups }

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  _ChatFilter _filter = _ChatFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        context.read<ChatProvider>().search('');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();

    final groups = chatProvider.groupChats;
    final direct = chatProvider.chats;
    final showGroups = _filter != _ChatFilter.direct;
    final showDirect = _filter != _ChatFilter.groups;
    final isEmpty =
        (!showGroups || groups.isEmpty) && (!showDirect || direct.isEmpty);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        centerTitle: false,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: chatProvider.search,
                decoration: const InputDecoration(
                  hintText: 'Search chats, groups and messages...',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              )
            : Text('Chats', style: theme.textTheme.displaySmall),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? LucideIcons.x : LucideIcons.search),
            tooltip: _isSearching ? 'Close search' : 'Search chats',
            onPressed: _toggleSearch,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewChatSheet,
        backgroundColor: theme.primaryColor,
        child: const Icon(LucideIcons.messageSquarePlus, color: Colors.white),
      ),
      body: chatProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _filterChip(theme, _ChatFilter.all,
                          'All (${groups.length + direct.length})'),
                      _filterChip(theme, _ChatFilter.groups,
                          'Groups (${groups.length})'),
                      _filterChip(theme, _ChatFilter.direct,
                          'Direct (${direct.length})'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: chatProvider.refresh,
                    child: isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.6,
                                child: _buildEmpty(chatProvider),
                              ),
                            ],
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 88),
                            children: [
                              if (showGroups && groups.isNotEmpty) ...[
                                _sectionHeader(theme, 'Groups'),
                                ...groups.map(
                                    (g) => _groupTile(theme, chatProvider, g)),
                              ],
                              if (showDirect && direct.isNotEmpty) ...[
                                _sectionHeader(theme, 'Direct messages'),
                                ...direct.map(
                                    (c) => _chatTile(theme, chatProvider, c)),
                              ],
                            ],
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(ChatProvider provider) {
    if (provider.query.isNotEmpty) {
      return EmptyState(
        icon: LucideIcons.search,
        title: 'No results',
        message: 'Nothing matches "${provider.query}".',
      );
    }
    if (_filter == _ChatFilter.groups) {
      return const EmptyState(
        icon: LucideIcons.users2,
        title: 'No groups yet',
        message:
            'Join a community, club or study group from the Campus Hub and its chat will show up here.',
      );
    }
    return EmptyState(
      icon: LucideIcons.messageCircle,
      title: 'No chats yet',
      message:
          'Connect with someone from Discover and start a conversation.',
      actionLabel: 'Start a chat',
      onAction: _showNewChatSheet,
    );
  }

  Widget _filterChip(ThemeData theme, _ChatFilter value, String label) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
        labelStyle: TextStyle(
          color:
              selected ? theme.primaryColor : theme.textTheme.bodyMedium?.color,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: selected ? theme.primaryColor : theme.dividerColor,
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.bodySmall
            ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1),
      ),
    );
  }

  // ----------------------------------------------------------------- groups

  Widget _groupTile(ThemeData theme, ChatProvider provider, GroupChat group) {
    final isUnread = group.unreadCount > 0;
    final last = group.lastMessage;
    final preview = provider.isTyping(group.id)
        ? 'someone is typing…'
        : last != null
            ? '${last.isMine ? 'You' : last.senderName.split(' ').first}: ${last.preview}'
            // Before the thread is opened all that is known is the preview
            // `send_message()` left on the conversation.
            : group.displayPreview.isEmpty
                ? 'No messages yet'
                : group.displayPreview;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(_groupIcon(group.kind), color: theme.primaryColor),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          if (provider.isMuted(group.id))
            Icon(LucideIcons.bellOff,
                size: 14, color: theme.textTheme.bodySmall?.color),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                group.kindLabel,
                style: TextStyle(fontSize: 9, color: theme.primaryColor),
              ),
            ),
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                  color: provider.isTyping(group.id)
                      ? theme.primaryColor
                      : isUnread
                          ? theme.textTheme.bodyLarge?.color
                          : theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: _trailing(theme, group.lastTimestamp, group.unreadCount),
      onTap: () {
        provider.markGroupAsRead(group.id);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(groupId: group.id),
          ),
        );
      },
    );
  }

  IconData _groupIcon(GroupKind kind) {
    switch (kind) {
      case GroupKind.community:
        return LucideIcons.users2;
      case GroupKind.club:
        return LucideIcons.tent;
      case GroupKind.studyGroup:
        return LucideIcons.bookOpen;
      case GroupKind.project:
        return LucideIcons.code;
      case GroupKind.event:
        return LucideIcons.calendarDays;
    }
  }

  // ----------------------------------------------------------------- direct

  Widget _chatTile(ThemeData theme, ChatProvider provider, Chat chat) {
    final isUnread = chat.unreadCount > 0;

    return Dismissible(
      key: ValueKey(chat.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.withValues(alpha: 0.85),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      confirmDismiss: (_) => showConfirmDialog(
        context,
        title: 'Delete chat?',
        message: 'This removes the conversation with ${chat.otherUser.name}.',
        confirmLabel: 'Delete',
        isDestructive: true,
      ),
      onDismissed: (_) {
        provider.deleteChat(chat.id);
        showAppSnackBar(context, 'Chat deleted', icon: LucideIcons.trash2);
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: UserAvatar(
          imageUrl: chat.otherUser.profilePhotoUrl,
          name: chat.otherUser.name,
          radius: 26,
          showOnlineDot: true,
          isOnline: chat.otherUser.isOnline,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                chat.otherUser.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            if (provider.isMuted(chat.id))
              Icon(LucideIcons.bellOff,
                  size: 14, color: theme.textTheme.bodySmall?.color),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            provider.isTyping(chat.id)
                ? 'typing…'
                : chat.displayPreview.isEmpty
                    ? 'Say hello 👋'
                    : chat.displayPreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
              color: provider.isTyping(chat.id)
                  ? theme.primaryColor
                  : isUnread
                      ? theme.textTheme.bodyLarge?.color
                      : theme.textTheme.bodySmall?.color,
            ),
          ),
        ),
        trailing: _trailing(theme, chat.lastTimestamp, chat.unreadCount),
        onTap: () {
          provider.markAsRead(chat.id);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatDetailScreen(chat: chat)),
          );
        },
        onLongPress: () => _showChatOptions(chat, provider),
      ),
    );
  }

  Widget _trailing(ThemeData theme, DateTime? timestamp, int unread) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (timestamp != null)
          Text(
            _formatTime(timestamp),
            style: TextStyle(
              fontSize: 11,
              color: unread > 0
                  ? theme.primaryColor
                  : theme.textTheme.bodySmall?.color,
              fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        const SizedBox(height: 6),
        if (unread > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            constraints: const BoxConstraints(minWidth: 20),
            decoration: BoxDecoration(
              color: theme.primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$unread',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  void _showChatOptions(Chat chat, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const SheetHandle(),
            ListTile(
              leading: Icon(provider.isMuted(chat.id)
                  ? LucideIcons.bell
                  : LucideIcons.bellOff),
              title: Text(provider.isMuted(chat.id)
                  ? 'Unmute notifications'
                  : 'Mute notifications'),
              onTap: () {
                provider.toggleMute(chat.id);
                Navigator.pop(sheetContext);
                showAppSnackBar(
                  context,
                  provider.isMuted(chat.id) ? 'Chat muted' : 'Chat unmuted',
                );
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.checkCircle2),
              title: const Text('Mark as read'),
              onTap: () {
                provider.markAsRead(chat.id);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title:
                  const Text('Delete chat', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await showConfirmDialog(
                  context,
                  title: 'Delete chat?',
                  message:
                      'This removes the conversation with ${chat.otherUser.name}.',
                  confirmLabel: 'Delete',
                  isDestructive: true,
                );
                if (!ok || !mounted) return;
                provider.deleteChat(chat.id);
                showAppSnackBar(context, 'Chat deleted');
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Lets the student start a chat with any of their connections.
  void _showNewChatSheet() {
    final connections = context.read<UserProvider>().connections;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
            child: Column(
              children: [
                const SheetHandle(),
                Text('New message', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Pick one of your connections',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Expanded(
                  child: connections.isEmpty
                      ? const EmptyState(
                          icon: LucideIcons.users,
                          title: 'No connections yet',
                          message:
                              'Accept or send a connection request first, then you can chat.',
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: connections.length,
                          itemBuilder: (context, index) {
                            final User user = connections[index];
                            return ListTile(
                              leading: UserAvatar(
                                imageUrl: user.profilePhotoUrl,
                                name: user.name,
                              ),
                              title: Text(user.name),
                              subtitle: Text(user.department),
                              onTap: () async {
                                final chats = this.context.read<ChatProvider>();
                                Navigator.pop(sheetContext);
                                // `get_or_create_direct_conversation` is a
                                // round trip, and it can refuse — a student
                                // who blocked you, or a connection that was
                                // cancelled since this list was built.
                                final chat = await chats.openChatWith(user);
                                if (!mounted) return;
                                if (chat == null) {
                                  showAppSnackBar(
                                    this.context,
                                    chats.lastError ??
                                        'That chat could not be opened.',
                                    icon: LucideIcons.circleAlert,
                                  );
                                  return;
                                }
                                Navigator.push(
                                  this.context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatDetailScreen(chat: chat),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        time.year == now.year && time.month == now.month && time.day == now.day;
    if (isToday) {
      final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final period = time.hour < 12 ? 'AM' : 'PM';
      return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (time.year == yesterday.year &&
        time.month == yesterday.month &&
        time.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${time.day}/${time.month}';
  }
}

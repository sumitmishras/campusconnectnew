import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_model.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../profile/screens/student_profile_screen.dart';
import '../widgets/attachment_bubble.dart';
import '../widgets/attachment_picker.dart';

class ChatDetailScreen extends StatefulWidget {
  final Chat chat;

  const ChatDetailScreen({super.key, required this.chat});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Loads the first page of history if this is the first open, and moves
      // the read pointer to the head of the thread.
      context.read<ChatProvider>().openThread(widget.chat.id);
    });
    // Reverse list: offset 0 is the newest message, so the top of the list is
    // the far end of the scroll extent.
    _scrollController.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    // Captured before the frame is torn down: a message arriving after this
    // screen is gone should count as unread again.
    _chats?.closeThread(widget.chat.id);
    _scrollController.removeListener(_maybeLoadOlder);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ChatProvider? _chats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chats = context.read<ChatProvider>();
  }

  bool _loadingOlder = false;

  Future<void> _maybeLoadOlder() async {
    if (_loadingOlder || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 200) return;

    _loadingOlder = true;
    await context.read<ChatProvider>().loadOlderMessages(widget.chat.id);
    _loadingOlder = false;
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    context.read<ChatProvider>().sendMessage(widget.chat.id, text);
    _controller.clear();
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();
    final chat = chatProvider.chatById(widget.chat.id) ?? widget.chat;
    final other = chat.otherUser;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentProfileScreen(user: other),
            ),
          ),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: other.profilePhotoUrl,
                name: other.name,
                radius: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      other.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      chatProvider.isTyping(chat.id)
                          ? 'typing…'
                          : other.isOnline
                              ? 'Online'
                              : other.lastActiveLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: chatProvider.isTyping(chat.id) || other.isOnline
                            ? Colors.green
                            : theme.textTheme.bodySmall?.color,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: () => _showChatMenu(chat, chatProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chat.messages.isEmpty
                ? EmptyState(
                    icon: LucideIcons.messageSquare,
                    title: 'No messages yet',
                    message: 'Say hi to ${other.name.split(' ').first} 👋',
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, index) {
                      final msg =
                          chat.messages[chat.messages.length - 1 - index];
                      final isMe = msg.isMine;
                      final previous = index < chat.messages.length - 1
                          ? chat.messages[chat.messages.length - 2 - index]
                          : null;
                      final showDate = previous == null ||
                          !_sameDay(previous.timestamp, msg.timestamp);

                      return Column(
                        children: [
                          if (showDate) _buildDateChip(theme, msg.timestamp),
                          _buildMessageBubble(theme, msg, isMe),
                        ],
                      );
                    },
                  ),
          ),
          if (chatProvider.isTyping(chat.id))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 8),
                child: Text('${other.name.split(' ').first} is typing…',
                    style: theme.textTheme.bodySmall),
              ),
            ),
          _buildMessageInput(theme),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateChip(ThemeData theme, DateTime date) {
    final now = DateTime.now();
    String label;
    if (_sameDay(date, now)) {
      label = 'Today';
    } else if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('dd MMM yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: theme.textTheme.bodySmall),
      ),
    );
  }

  Widget _buildMessageBubble(ThemeData theme, Message msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // Only the sender may delete, which delete_message() enforces anyway —
        // offering it to everyone would just produce a refusal.
        onLongPress: isMe && !msg.isDeleted ? () => _confirmDelete(msg) : null,
        // A message that failed to send is tappable: the retry reuses its
        // client id, so a lost response cannot turn into two bubbles.
        onTap: msg.status == MessageStatus.failed ? () => _retry(msg) : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.symmetric(
            horizontal: msg.hasAttachment ? 8 : 14,
            vertical: msg.hasAttachment ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: isMe ? theme.primaryColor : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: isMe ? Radius.zero : const Radius.circular(18),
              bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
            ),
            border: isMe
                ? null
                : Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (msg.hasAttachment)
                AttachmentBubble(attachment: msg.attachment!, isMe: isMe),
              if (msg.isDeleted)
                Text(
                  'This message was deleted',
                  style: TextStyle(
                    color: isMe ? Colors.white70 : theme.textTheme.bodySmall?.color,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (msg.content.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                      top: msg.hasAttachment ? 8 : 0,
                      left: msg.hasAttachment ? 4 : 0,
                      right: msg.hasAttachment ? 4 : 0),
                  child: Text(
                    msg.content,
                    style: TextStyle(
                      color:
                          isMe ? Colors.white : theme.textTheme.bodyLarge?.color,
                      fontSize: 15,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('hh:mm a').format(msg.timestamp),
                    style: TextStyle(
                      color: isMe
                          ? Colors.white70
                          : theme.textTheme.bodySmall?.color,
                      fontSize: 10,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(_receiptIcon(msg), size: 12, color: Colors.white70),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One tick sent, two ticks read — read being "the other member's
  /// `last_read_seq` is at or past this message", which is what `seen_by_all`
  /// resolves to in a two-person thread.
  static IconData _receiptIcon(Message msg) {
    switch (msg.status) {
      case MessageStatus.sending:
        return LucideIcons.clock;
      case MessageStatus.failed:
        return LucideIcons.circleAlert;
      case MessageStatus.sent:
        return msg.isSeen ? LucideIcons.checkCheck : LucideIcons.check;
    }
  }

  Future<void> _retry(Message msg) async {
    final chats = context.read<ChatProvider>();
    await chats.retrySend(widget.chat.id, msg);
    if (!mounted) return;
    final error = chats.lastError;
    if (error == null) return;
    showAppSnackBar(context, error, icon: LucideIcons.circleAlert);
    chats.clearError();
  }

  Future<void> _confirmDelete(Message msg) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete message?',
      message: 'This removes it for everyone in the chat.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<ChatProvider>().deleteMessage(widget.chat.id, msg);
  }

  Widget _buildMessageInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(LucideIcons.paperclip,
                  color: theme.textTheme.bodySmall?.color),
              tooltip: 'Attach a photo or document',
              onPressed: _pickAttachment,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  setState(() {});
                  // Broadcast, not a write: a typing indicator is valid for a
                  // few seconds and never reaches Postgres.
                  context.read<ChatProvider>().notifyTyping(widget.chat.id);
                },
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: _controller.text.trim().isEmpty
                  ? theme.primaryColor.withValues(alpha: 0.4)
                  : theme.primaryColor,
              child: IconButton(
                icon: const Icon(LucideIcons.send, color: Colors.white, size: 18),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Photos and documents only, and nothing above the size limit —
  /// the picker enforces both before returning a file.
  Future<void> _pickAttachment() async {
    final file = await showAttachmentPicker(context);
    if (file == null || !mounted) return;

    final chats = context.read<ChatProvider>();
    _scrollToBottom();
    // The bubble appears at once; the upload (ticket → PUT → send_message)
    // happens behind it and reports only if it fails.
    await chats.sendAttachment(widget.chat.id, file);
    if (!mounted) return;

    final error = chats.lastError;
    showAppSnackBar(
      context,
      error ?? '${file.isPhoto ? 'Photo' : 'Document'} sent • ${file.readableSize}',
      icon: error == null ? LucideIcons.paperclip : LucideIcons.circleAlert,
    );
    if (error != null) chats.clearError();
  }

  void _showChatMenu(Chat chat, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const SheetHandle(),
            ListTile(
              leading: const Icon(LucideIcons.user),
              title: const Text('View profile'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentProfileScreen(user: chat.otherUser),
                  ),
                );
              },
            ),
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
              leading: const Icon(LucideIcons.eraser),
              title: const Text('Clear messages'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await showConfirmDialog(
                  context,
                  title: 'Clear messages?',
                  message: 'All messages in this chat will be removed.',
                  confirmLabel: 'Clear',
                  isDestructive: true,
                );
                if (!ok || !mounted) return;
                provider.clearMessages(chat.id);
                showAppSnackBar(context, 'Messages cleared');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.ban, color: Colors.red),
              title: const Text('Block user',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await showConfirmDialog(
                  context,
                  title: 'Block ${chat.otherUser.name}?',
                  message:
                      'They will no longer be able to message you or see your profile.',
                  confirmLabel: 'Block',
                  isDestructive: true,
                );
                if (!ok || !mounted) return;
                // Captured before popping — this screen is about to go away,
                // and on failure the snack bar is the only thing left to
                // explain why nothing happened.
                final messenger = ScaffoldMessenger.of(context);
                final users = context.read<UserProvider>();
                final blocked = await users.blockUser(chat.otherUser);
                if (!mounted) return;
                if (blocked) provider.deleteChat(chat.id);
                Navigator.pop(context);
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    content: Text(blocked
                        ? '${chat.otherUser.name} blocked'
                        : users.lastActionError ??
                            'That student could not be blocked.'),
                  ));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

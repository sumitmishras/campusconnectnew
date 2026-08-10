import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_model.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../profile/screens/student_profile_screen.dart';
import '../widgets/attachment_bubble.dart';
import '../widgets/attachment_picker.dart';

/// Chat thread for a community, club or study group the student has joined.
class GroupChatScreen extends StatefulWidget {
  final String groupId;

  const GroupChatScreen({super.key, required this.groupId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  ChatProvider? _chats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Loads history and the member list the first time, then advances the
      // read pointer.
      context.read<ChatProvider>().openGroupThread(widget.groupId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chats = context.read<ChatProvider>();
  }

  @override
  void dispose() {
    _chats?.closeThread(widget.groupId);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<ChatProvider>().sendGroupMessage(widget.groupId, text);
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

  /// Photos and documents only, capped at the shared size limit.
  Future<void> _pickAttachment() async {
    final file = await showAttachmentPicker(context);
    if (file == null || !mounted) return;

    final chats = context.read<ChatProvider>();
    _scrollToBottom();
    await chats.sendGroupAttachment(widget.groupId, file);
    if (!mounted) return;

    final error = chats.lastError;
    showAppSnackBar(
      context,
      error ?? '${file.isPhoto ? 'Photo' : 'Document'} shared with the group',
      icon: error == null ? LucideIcons.paperclip : LucideIcons.circleAlert,
    );
    if (error != null) chats.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatProvider = context.watch<ChatProvider>();
    final group = chatProvider.groupChatById(widget.groupId);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const EmptyState(
          icon: LucideIcons.users2,
          title: 'You left this group',
          message: 'Join it again from the Campus Hub to see the chat.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: InkWell(
          onTap: () => _showGroupInfo(group),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                child: Icon(
                  _iconFor(group.kind),
                  size: 18,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      chatProvider.isTyping(group.id)
                          ? 'someone is typing…'
                          : '${group.memberCount} members',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: chatProvider.isTyping(group.id)
                            ? Colors.green
                            : theme.textTheme.bodySmall?.color,
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
            icon: const Icon(LucideIcons.info),
            tooltip: 'Group info',
            onPressed: () => _showGroupInfo(group),
          ),
          IconButton(
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: () => _showMenu(group, chatProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: group.messages.isEmpty
                ? EmptyState(
                    icon: LucideIcons.messageSquare,
                    title: 'No messages yet',
                    message: 'Be the first to say something in ${group.name}.',
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: group.messages.length,
                    itemBuilder: (context, index) {
                      final list = group.messages;
                      final msg = list[list.length - 1 - index];
                      final isMe = msg.isMine;
                      final previous = index < list.length - 1
                          ? list[list.length - 2 - index]
                          : null;
                      final showDate =
                          previous == null ||
                          !_sameDay(previous.timestamp, msg.timestamp);
                      final showSender =
                          !isMe &&
                          (previous == null ||
                              previous.senderId != msg.senderId ||
                              showDate);

                      return Column(
                        children: [
                          if (showDate) _dateChip(theme, msg.timestamp),
                          _bubble(theme, msg, isMe, showSender),
                        ],
                      );
                    },
                  ),
          ),
          if (chatProvider.isTyping(group.id))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 8),
                child: Text(
                  'someone is typing…',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          _input(theme),
        ],
      ),
    );
  }

  IconData _iconFor(GroupKind kind) {
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

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dateChip(ThemeData theme, DateTime date) {
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

  Widget _bubble(ThemeData theme, Message msg, bool isMe, bool showSender) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 10),
              child: Opacity(
                opacity: showSender ? 1 : 0,
                child: UserAvatar(
                  imageUrl: msg.senderPhotoUrl,
                  name: msg.senderName,
                  radius: 14,
                ),
              ),
            ),
          // Flexible so the bubble shrinks to the space left beside the
          // avatar — a plain Container gets unbounded width inside a Row
          // and would overflow on narrow screens.
          Flexible(
            child: GestureDetector(
              // Group admins may also delete other people's messages, but the
              // client does not know its own role here — delete_message()
              // decides, and offering it only to the sender avoids a refusal.
              onLongPress:
                  isMe && !msg.isDeleted ? () => _confirmDelete(msg) : null,
              // A failed send retries on tap, reusing its client id.
              onTap:
                  msg.status == MessageStatus.failed ? () => _retry(msg) : null,
              child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
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
                    : Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.15),
                      ),
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (showSender) ...[
                    Padding(
                      padding: EdgeInsets.only(
                        left: msg.hasAttachment ? 4 : 0,
                        bottom: 4,
                      ),
                      child: Text(
                        msg.senderName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (msg.hasAttachment)
                    AttachmentBubble(attachment: msg.attachment!, isMe: isMe),
                  if (msg.isDeleted)
                    Text(
                      'This message was deleted',
                      style: TextStyle(
                        color: isMe
                            ? Colors.white70
                            : theme.textTheme.bodySmall?.color,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (msg.content.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        top: msg.hasAttachment ? 8 : 0,
                        left: msg.hasAttachment ? 4 : 0,
                        right: msg.hasAttachment ? 4 : 0,
                      ),
                      child: Text(
                        msg.content,
                        style: TextStyle(
                          color: isMe
                              ? Colors.white
                              : theme.textTheme.bodyLarge?.color,
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
                        // Two ticks in a group thread means every other member's
                        // read pointer has passed this message — MIN(last_read_seq).
                        Icon(_receiptIcon(msg), size: 12, color: Colors.white70),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

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
    await chats.retrySend(widget.groupId, msg);
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
      message: 'This removes it for everyone in the group.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<ChatProvider>().deleteMessage(widget.groupId, msg);
  }

  Widget _input(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                LucideIcons.paperclip,
                color: theme.textTheme.bodySmall?.color,
              ),
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
                  context.read<ChatProvider>().notifyTyping(widget.groupId);
                },
                decoration: InputDecoration(
                  hintText: 'Message the group...',
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: _controller.text.trim().isEmpty
                  ? theme.primaryColor.withValues(alpha: 0.4)
                  : theme.primaryColor,
              child: IconButton(
                icon: const Icon(
                  LucideIcons.send,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupInfo(GroupChat group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, controller) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                Center(
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                    child: Icon(
                      _iconFor(group.kind),
                      size: 30,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  group.name,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.kindLabel} • ${group.memberCount} members',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(group.description, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 20),
                Text('Members', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: controller,
                    children: group.members
                        .map(
                          (m) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: UserAvatar(
                              imageUrl: m.profilePhotoUrl,
                              name: m.name,
                              radius: 20,
                            ),
                            title: Text(m.name),
                            subtitle: Text('${m.department} • ${m.year}'),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StudentProfileScreen(user: m),
                                ),
                              );
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMenu(GroupChat group, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            const SheetHandle(),
            ListTile(
              leading: const Icon(LucideIcons.info),
              title: const Text('Group info'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showGroupInfo(group);
              },
            ),
            ListTile(
              leading: Icon(
                provider.isMuted(group.id)
                    ? LucideIcons.bell
                    : LucideIcons.bellOff,
              ),
              title: Text(
                provider.isMuted(group.id) ? 'Unmute group' : 'Mute group',
              ),
              onTap: () {
                provider.toggleMute(group.id);
                Navigator.pop(sheetContext);
                showAppSnackBar(
                  context,
                  provider.isMuted(group.id) ? 'Group muted' : 'Group unmuted',
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
                  message: 'All messages in ${group.name} will be removed.',
                  confirmLabel: 'Clear',
                  isDestructive: true,
                );
                if (!ok || !mounted) return;
                provider.clearGroupMessages(group.id);
                showAppSnackBar(context, 'Messages cleared');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.logOut, color: Colors.red),
              title: const Text(
                'Leave group',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await showConfirmDialog(
                  context,
                  title: 'Leave ${group.name}?',
                  message:
                      'The chat will be removed from your list. You can join again anytime.',
                  confirmLabel: 'Leave',
                  isDestructive: true,
                );
                if (!ok || !mounted) return;

                final messenger = ScaffoldMessenger.of(context);
                final campus = context.read<CampusProvider>();
                switch (group.kind) {
                  case GroupKind.community:
                    if (campus.isCommunityJoined(group.id)) {
                      campus.toggleCommunityJoin(group.id);
                    }
                    break;
                  case GroupKind.club:
                    if (campus.isClubJoined(group.id)) {
                      campus.toggleClubJoin(group.id);
                    }
                    break;
                  case GroupKind.studyGroup:
                    if (campus.isStudyGroupJoined(group.id)) {
                      campus.toggleStudyGroupJoin(group.id);
                    }
                    break;
                  case GroupKind.project:
                  case GroupKind.event:
                    // These threads have no join button of their own yet, so
                    // leaving is handled by the chat provider alone.
                    break;
                }
                provider.leaveGroupChat(group.id);
                Navigator.pop(context);
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      content: Text('You left ${group.name}'),
                    ),
                  );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

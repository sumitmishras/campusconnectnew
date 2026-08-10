import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user_model.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../chat/screens/chat_detail_screen.dart';
import '../../profile/screens/student_profile_screen.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<UserProvider>();

    final received = provider.receivedRequests;
    final sent = provider.sentRequests;
    final connections = provider.connections;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          centerTitle: false,
          title: Text('Connections', style: theme.textTheme.displaySmall),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Received (${received.length})'),
              Tab(text: 'Sent (${sent.length})'),
              Tab(text: 'Connections (${connections.length})'),
            ],
          ),
        ),
        body: _buildBody(context, theme, provider, received, sent, connections),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    UserProvider provider,
    List<User> received,
    List<User> sent,
    List<User> connections,
  ) {
    // Only the first load gets a spinner. A refresh keeps whatever is already
    // on screen, so pulling to refresh does not blank the tab you are reading.
    if (provider.isLoadingConnections &&
        received.isEmpty &&
        sent.isEmpty &&
        connections.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // A cold failure. Anything already loaded stays on screen instead, because
    // a stale list is more useful than an error page.
    if (provider.connectionsError != null &&
        received.isEmpty &&
        sent.isEmpty &&
        connections.isEmpty) {
      return EmptyState(
        icon: LucideIcons.wifiOff,
        title: 'Could not load connections',
        message: provider.connectionsError!,
        actionLabel: 'Try again',
        onAction: provider.refresh,
      );
    }

    return TabBarView(
      children: [
        _buildReceived(context, theme, provider, received),
        _buildSent(context, theme, provider, sent),
        _buildConnections(context, theme, provider, connections),
      ],
    );
  }

  // --------------------------------------------------------------- received

  Widget _buildReceived(BuildContext context, ThemeData theme,
      UserProvider provider, List<User> requests) {
    if (requests.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.userPlus,
        title: 'No pending requests',
        message:
            'When someone wants to connect with you, their request shows up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final user = requests[index];
          // Long press for the quieter options — ignoring a request is
          // deliberately not a button, so declining stays the obvious answer.
          return GestureDetector(
            onLongPress: () => _showRequestMenu(context, provider, user),
            child: AppCard(
              onTap: () => _openProfile(context, user),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _userRow(context, theme, user,
                      trailing: user.lastActiveLabel),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.handshake,
                            size: 16, color: theme.primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Wants to connect as a ${provider.requestPurpose(user.id)}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _decline(context, provider, user),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _accept(context, provider, user),
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------- sent

  Widget _buildSent(BuildContext context, ThemeData theme,
      UserProvider provider, List<User> requests) {
    if (requests.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.send,
        title: 'No requests sent',
        message:
            'Head to Discover, open a profile and send your first connection request.',
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final user = requests[index];
          return AppCard(
            onTap: () => _openProfile(context, user),
            child: Row(
              children: [
                UserAvatar(imageUrl: user.profilePhotoUrl, name: user.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Sent as ${provider.requestPurpose(user.id)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _withdraw(context, provider, user),
                  child: const Text('Withdraw'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ connections

  Widget _buildConnections(BuildContext context, ThemeData theme,
      UserProvider provider, List<User> connections) {
    if (connections.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.users,
        title: 'No connections yet',
        message: 'Accept a request or send one to start building your circle.',
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: connections.length,
        itemBuilder: (context, index) {
          final user = connections[index];
          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => _openProfile(context, user),
            child: Row(
              children: [
                UserAvatar(
                  imageUrl: user.profilePhotoUrl,
                  name: user.name,
                  showOnlineDot: true,
                  isOnline: user.isOnline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('${user.department} • ${user.year}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.messageCircle),
                  color: theme.primaryColor,
                  tooltip: 'Message',
                  onPressed: () async {
                    final chats = context.read<ChatProvider>();
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);

                    final chat = await chats.openChatWith(user);
                    if (chat == null) {
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(16),
                          content: Text(chats.lastError ??
                              'That chat could not be opened.'),
                        ));
                      chats.clearError();
                      return;
                    }
                    navigator.push(
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(chat: chat),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(LucideIcons.moreVertical),
                  onPressed: () => _showConnectionMenu(context, provider, user),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _userRow(BuildContext context, ThemeData theme, User user,
      {String? trailing}) {
    return Row(
      children: [
        UserAvatar(imageUrl: user.profilePhotoUrl, name: user.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text('${user.year} • ${user.course}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (trailing != null && trailing.isNotEmpty)
          Text(trailing, style: theme.textTheme.bodySmall),
      ],
    );
  }

  void _openProfile(BuildContext context, User user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentProfileScreen(user: user)),
    );
  }

  // --------------------------------------------------------------- actions

  Future<void> _accept(
      BuildContext context, UserProvider provider, User user) async {
    final ok = await provider.acceptRequest(user);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      ok
          ? 'Connected with ${user.name}!'
          : provider.lastActionError ?? 'That request could not be accepted.',
      icon: ok ? LucideIcons.checkCircle2 : LucideIcons.circleAlert,
    );
  }

  Future<void> _decline(
      BuildContext context, UserProvider provider, User user) async {
    final ok = await provider.declineRequest(user);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      ok
          ? 'Request declined'
          : provider.lastActionError ?? 'That request could not be declined.',
      icon: ok ? LucideIcons.userX : LucideIcons.circleAlert,
    );
  }

  Future<void> _withdraw(
      BuildContext context, UserProvider provider, User user) async {
    final ok = await provider.cancelRequest(user);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      ok
          ? 'Request withdrawn'
          : provider.lastActionError ?? 'That request could not be withdrawn.',
      icon: ok ? LucideIcons.userX : LucideIcons.circleAlert,
    );
  }

  /// Quiet options on an incoming request. Ignoring hides it without telling
  /// the sender anything, which is why it is not next to Accept and Decline.
  void _showRequestMenu(
      BuildContext context, UserProvider provider, User user) {
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
                _openProfile(context, user);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.eyeOff),
              title: const Text('Ignore request'),
              subtitle: const Text('Hides it without telling them'),
              onTap: () {
                Navigator.pop(sheetContext);
                provider.ignoreRequest(user);
                showAppSnackBar(context, 'Request ignored',
                    icon: LucideIcons.eyeOff);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showConnectionMenu(
      BuildContext context, UserProvider provider, User user) {
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
                _openProfile(context, user);
              },
            ),
            ListTile(
              leading: Icon(provider.isBookmarked(user.id)
                  ? LucideIcons.bookMarked
                  : LucideIcons.bookmark),
              title: Text(provider.isBookmarked(user.id)
                  ? 'Remove bookmark'
                  : 'Bookmark'),
              onTap: () {
                final added = provider.toggleBookmark(user.id);
                Navigator.pop(sheetContext);
                showAppSnackBar(context,
                    added ? 'Added to bookmarks' : 'Removed from bookmarks');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.userMinus, color: Colors.red),
              title: const Text('Remove connection',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await showConfirmDialog(
                  context,
                  title: 'Remove ${user.name}?',
                  message:
                      'You will no longer be connected. You can send a new request later.',
                  confirmLabel: 'Remove',
                  isDestructive: true,
                );
                if (!ok || !context.mounted) return;

                final removed = await provider.removeConnection(user);
                if (!context.mounted) return;
                showAppSnackBar(
                  context,
                  removed
                      ? 'Connection removed'
                      : provider.lastActionError ??
                          'That connection could not be removed.',
                  icon: removed
                      ? LucideIcons.userMinus
                      : LucideIcons.circleAlert,
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

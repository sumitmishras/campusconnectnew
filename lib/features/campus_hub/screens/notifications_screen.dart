import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/campus_models.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/widgets/app_widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();
    final items = campus.notifications;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications'),
        actions: [
          if (items.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (value) {
                if (value == 'read') {
                  campus.markAllNotificationsRead();
                  showAppSnackBar(context, 'All notifications marked as read');
                } else {
                  campus.clearNotifications();
                  showAppSnackBar(context, 'Notifications cleared');
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'read', child: Text('Mark all as read')),
                PopupMenuItem(value: 'clear', child: Text('Clear all')),
              ],
            ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: LucideIcons.bell,
              title: 'You are all caught up',
              message: 'New requests, messages and event reminders show up here.',
            )
          : RefreshIndicator(
              onRefresh: campus.refresh,
              child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = items[index];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  tileColor: n.isRead
                      ? null
                      : theme.primaryColor.withValues(alpha: 0.04),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_iconFor(n.type),
                        size: 18, color: theme.primaryColor),
                  ),
                  title: Text(
                    n.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: n.isRead ? FontWeight.w500 : FontWeight.bold,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(n.body, style: theme.textTheme.bodySmall),
                  ),
                  trailing: Text(_timeAgo(n.timestamp),
                      style: theme.textTheme.bodySmall),
                  onTap: () => campus.markNotificationRead(n.id),
                );
              },
              ),
            ),
    );
  }

  IconData _iconFor(CampusNotificationType type) {
    switch (type) {
      case CampusNotificationType.connection:
        return LucideIcons.userPlus;
      case CampusNotificationType.message:
        return LucideIcons.messageCircle;
      case CampusNotificationType.event:
        return LucideIcons.calendarDays;
      case CampusNotificationType.poll:
        return LucideIcons.barChart3;
      case CampusNotificationType.club:
        return LucideIcons.tent;
      case CampusNotificationType.project:
        return LucideIcons.code;
      case CampusNotificationType.system:
        return LucideIcons.shieldCheck;
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/campus_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../campus_hub/screens/event_detail_screen.dart';
import 'student_profile_screen.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.watch<UserProvider>();
    final campusProvider = context.watch<CampusProvider>();

    final students = userProvider.bookmarkedStudents;
    final events = campusProvider.savedEvents;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Bookmarks'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Students (${students.length})'),
              Tab(text: 'Events (${events.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            students.isEmpty
                ? const EmptyState(
                    icon: LucideIcons.bookmark,
                    title: 'No saved students',
                    message:
                        'Tap the bookmark icon on any student card to save them for later.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final user = students[index];
                      return AppCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudentProfileScreen(user: user),
                          ),
                        ),
                        child: Row(
                          children: [
                            UserAvatar(
                                imageUrl: user.profilePhotoUrl,
                                name: user.name),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.name,
                                      style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 2),
                                  Text('${user.department} • ${user.year}',
                                      style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.bookMarked),
                              color: theme.primaryColor,
                              tooltip: 'Remove bookmark',
                              onPressed: () {
                                userProvider.toggleBookmark(user.id);
                                showAppSnackBar(
                                    context, 'Removed from bookmarks');
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            events.isEmpty
                ? const EmptyState(
                    icon: LucideIcons.calendarDays,
                    title: 'No saved events',
                    message:
                        'Save an event from the Events screen and it will appear here.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return AppCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EventDetailScreen(event: event),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    theme.primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(LucideIcons.calendarDays,
                                  color: theme.primaryColor),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(event.title,
                                      style: theme.textTheme.titleMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${DateFormat('MMM dd').format(event.date)} • ${event.venue}',
                                    style: theme.textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.bookmarkCheck),
                              color: theme.primaryColor,
                              onPressed: () {
                                campusProvider.toggleEventSaved(event.id);
                                showAppSnackBar(context, 'Removed from saved');
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

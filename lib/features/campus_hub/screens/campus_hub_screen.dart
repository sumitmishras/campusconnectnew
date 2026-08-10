import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/campus_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import 'clubs_screen.dart';
import 'communities_screen.dart';
import 'event_detail_screen.dart';
import 'events_screen.dart';
import 'notifications_screen.dart';
import 'polls_screen.dart';
import 'projects_screen.dart';
import 'study_groups_screen.dart';

class CampusHubScreen extends StatelessWidget {
  const CampusHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();
    final featured =
        campus.upcomingEvents.isEmpty ? null : campus.upcomingEvents.first;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        centerTitle: false,
        title: Text('Campus Hub', style: theme.textTheme.displaySmall),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.bell),
                tooltip: 'Notifications',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                ),
              ),
              if (campus.unreadNotificationCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.scaffoldBackgroundColor, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: campus.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFeatured(context, theme, campus, featured),
              const SizedBox(height: 28),
              Text('Explore', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.05,
                children: [
                  _hubCard(context, 'Events', '${campus.upcomingEvents.length} upcoming',
                      LucideIcons.calendarDays, const EventsScreen()),
                  _hubCard(context, 'Communities', '${campus.communities.length} groups',
                      LucideIcons.users2, const CommunitiesScreen()),
                  _hubCard(context, 'Clubs', '${campus.clubs.length} societies',
                      LucideIcons.tent, const ClubsScreen()),
                  _hubCard(context, 'Study Groups', '${campus.studyGroups.length} active',
                      LucideIcons.bookOpen, const StudyGroupsScreen()),
                  _hubCard(context, 'Projects', '${campus.projects.length} hiring',
                      LucideIcons.code, const ProjectsScreen()),
                  _hubCard(context, 'Polls', '${campus.polls.length} live',
                      LucideIcons.barChart3, const PollsScreen()),
                ],
              ),
              const SizedBox(height: 28),
              if (campus.upcomingEvents.length > 1) ...[
                Row(
                  children: [
                    Text('Happening soon', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EventsScreen()),
                      ),
                      child: const Text('See all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: campus.upcomingEvents.take(6).length,
                    itemBuilder: (context, index) {
                      final event = campus.upcomingEvents[index];
                      return _buildMiniEventCard(context, theme, event);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatured(
      BuildContext context, ThemeData theme, CampusProvider campus, featured) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        if (featured == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EventDetailScreen(event: featured)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.primaryColor, theme.colorScheme.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Featured',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                const Spacer(),
                const Icon(LucideIcons.megaphone, color: Colors.white, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              featured?.title ?? 'Annual Tech Fest 2026 Registration Open!',
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              featured == null
                  ? 'Join the biggest coding event on campus.'
                  : '${DateFormat('EEE, MMM dd').format(featured.date)} • ${featured.venue}',
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (featured != null)
                  ElevatedButton(
                    onPressed: () {
                      final joined = campus.toggleEventJoin(featured.id);
                      showAppSnackBar(
                        context,
                        joined
                            ? 'You are going to ${featured.title}'
                            : 'Registration cancelled',
                        icon: LucideIcons.calendarDays,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: theme.primaryColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: Text(
                      campus.isEventJoined(featured.id)
                          ? 'Going ✓'
                          : 'Register now',
                    ),
                  ),
                const Spacer(),
                const Icon(LucideIcons.chevronRight, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniEventCard(BuildContext context, ThemeData theme, event) {
    return Container(
      width: 210,
      margin: const EdgeInsets.only(right: 12),
      child: AppCard(
        margin: EdgeInsets.zero,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TagChip(label: event.category, filled: true),
            const SizedBox(height: 10),
            Text(
              event.title,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Row(
              children: [
                Icon(LucideIcons.calendar,
                    size: 13, color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    DateFormat('MMM dd, h:mm a').format(event.date),
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hubCard(BuildContext context, String title, String subtitle,
      IconData icon, Widget destination) {
    final theme = Theme.of(context);
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      radius: 24,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: theme.primaryColor, size: 22),
          ),
          const Spacer(),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

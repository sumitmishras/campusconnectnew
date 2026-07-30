import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'events_screen.dart';
import 'communities_screen.dart';
import 'polls_screen.dart';
import 'clubs_screen.dart';
import 'study_groups_screen.dart';
import 'projects_screen.dart';

class CampusHubScreen extends StatelessWidget {
  const CampusHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Campus Hub', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Featured Announcement
            Container(
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('New', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      const Spacer(),
                      const Icon(LucideIcons.bell, color: Colors.white, size: 20),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Annual Tech Fest 2026 Registration Open!',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join the biggest coding event on campus.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('Explore', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildHubCard('Events', 'Workshops, Fests', LucideIcons.calendarDays, theme, context, const EventsScreen()),
                _buildHubCard('Communities', 'Department Groups', LucideIcons.users2, theme, context, const CommunitiesScreen()),
                _buildHubCard('Clubs', 'Coding, Dance, AI', LucideIcons.tent, theme, context, const ClubsScreen()),
                _buildHubCard('Study Groups', 'Find Partners', LucideIcons.bookOpen, theme, context, const StudyGroupsScreen()),
                _buildHubCard('Projects', 'Find Teammates', LucideIcons.code, theme, context, const ProjectsScreen()),
                _buildHubCard('Polls', 'Campus Opinions', LucideIcons.barChart3, theme, context, const PollsScreen()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubCard(String title, String subtitle, IconData icon, ThemeData theme, BuildContext context, [Widget? destination]) {
    return GestureDetector(
      onTap: () {
        if (destination != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title coming soon!')));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: theme.primaryColor, size: 24),
            ),
            const Spacer(),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

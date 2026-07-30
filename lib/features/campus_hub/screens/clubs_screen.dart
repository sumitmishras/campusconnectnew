import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/campus_provider.dart';

class ClubsScreen extends StatelessWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // We can reuse communities data for clubs for this demo, filtering by non-department
    final campusProvider = context.watch<CampusProvider>();
    final clubs = campusProvider.communities.where((c) => !c.isDepartment).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Campus Clubs', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
      ),
      body: campusProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: clubs.length,
              itemBuilder: (context, index) {
                final club = clubs[index];
                return _buildClubCard(club, theme, context, campusProvider);
              },
            ),
    );
  }

  Widget _buildClubCard(club, ThemeData theme, BuildContext context, CampusProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: theme.primaryColor.withOpacity(0.1),
            child: Icon(LucideIcons.tent, color: theme.primaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(club.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${club.memberCount} members',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.primaryColor),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              provider.joinCommunity(club.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Joined ${club.name}!')),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

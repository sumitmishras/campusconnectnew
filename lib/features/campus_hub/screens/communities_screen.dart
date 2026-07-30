import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/campus_provider.dart';

class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campusProvider = context.watch<CampusProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Communities', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
      ),
      body: campusProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: campusProvider.communities.length,
              itemBuilder: (context, index) {
                final community = campusProvider.communities[index];
                return _buildCommunityCard(community, theme, context, campusProvider);
              },
            ),
    );
  }

  Widget _buildCommunityCard(community, ThemeData theme, BuildContext context, CampusProvider provider) {
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
            child: Icon(community.isDepartment ? LucideIcons.building : LucideIcons.users, color: theme.primaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(community.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${community.memberCount} members',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.primaryColor),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              provider.joinCommunity(community.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Joined ${community.name}!')),
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

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: theme.primaryColor.withOpacity(0.1),
                  child: Icon(LucideIcons.user, size: 50, color: theme.primaryColor),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 3),
                    ),
                    child: const Icon(LucideIcons.edit2, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Sumit Mishra', style: theme.textTheme.titleLarge),
            Text('@sumit', style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color)),
            const SizedBox(height: 24),
            
            // Completion Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          value: 0.8,
                          backgroundColor: theme.dividerColor.withOpacity(0.2),
                          color: theme.primaryColor,
                          strokeWidth: 4,
                        ),
                      ),
                      Text('80%', style: theme.textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Profile Incomplete', style: theme.textTheme.titleMedium),
                        Text('Add your interests to reach 100%', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            _buildProfileOption('Edit Profile', LucideIcons.user, theme),
            _buildProfileOption('My Connections', LucideIcons.users, theme),
            _buildProfileOption('Privacy Settings', LucideIcons.shield, theme),
            _buildProfileOption('Bookmarks', LucideIcons.bookmark, theme),
            _buildProfileOption('Help & Support', LucideIcons.helpCircle, theme),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(LucideIcons.logOut, color: Colors.red),
              label: const Text('Log Out', style: TextStyle(color: Colors.red, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(String title, IconData icon, ThemeData theme) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.primaryColor, size: 20),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      trailing: const Icon(LucideIcons.chevronRight, size: 20),
      onTap: () {},
    );
  }
}

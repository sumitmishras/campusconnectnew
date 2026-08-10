import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/screens/welcome_screen.dart';
import 'bookmarks_screen.dart';
import 'edit_profile_screen.dart';
import 'help_support_screen.dart';
import 'privacy_settings_screen.dart';
import 'settings_screen.dart';

class MyProfileScreen extends StatelessWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final userProvider = context.watch<UserProvider>();
    final campusProvider = context.watch<CampusProvider>();
    final me = auth.currentUser;

    if (me == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final completion = me.completionPercentage;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        centerTitle: false,
        title: Text('Profile', style: theme.textTheme.displaySmall),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            tooltip: 'Settings',
            onPressed: () => _push(context, const SettingsScreen()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _push(context, const EditProfileScreen()),
              child: Stack(
                children: [
                  UserAvatar(
                    imageUrl: me.profilePhotoUrl,
                    name: me.name,
                    radius: 50,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: theme.scaffoldBackgroundColor, width: 3),
                      ),
                      child: const Icon(LucideIcons.edit2,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(me.name, style: theme.textTheme.titleLarge),
            Text('@${me.username}', style: theme.textTheme.bodySmall),
            if (me.uid.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.badgeCheck,
                        size: 14, color: theme.primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      '${me.uid} • CU Verified',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.primaryColor),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            _buildStatsRow(theme, userProvider, campusProvider),
            const SizedBox(height: 20),
            _buildCompletionCard(context, theme, completion, me.nextCompletionHint),
            const SizedBox(height: 24),
            if (me.bio.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('About', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(me.bio, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: 20),
            ],
            if (me.interests.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Interests', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      me.interests.map((i) => TagChip(label: i)).toList(),
                ),
              ),
              const SizedBox(height: 24),
            ],
            const Divider(),
            const SizedBox(height: 8),
            _option(context, 'Edit Profile', LucideIcons.user,
                () => _push(context, const EditProfileScreen())),
            _option(
              context,
              'My Connections',
              LucideIcons.users,
              () => showAppSnackBar(
                  context, 'Open the Connect tab to manage connections',
                  icon: LucideIcons.users),
              trailingText: '${userProvider.connections.length}',
            ),
            _option(context, 'Privacy Settings', LucideIcons.shield,
                () => _push(context, const PrivacySettingsScreen())),
            _option(
              context,
              'Bookmarks',
              LucideIcons.bookmark,
              () => _push(context, const BookmarksScreen()),
              trailingText:
                  '${userProvider.bookmarkedStudents.length + campusProvider.savedEvents.length}',
            ),
            _option(context, 'Help & Support', LucideIcons.helpCircle,
                () => _push(context, const HelpSupportScreen())),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(LucideIcons.logOut, color: Colors.red),
              label: const Text('Log Out',
                  style: TextStyle(color: Colors.red, fontSize: 16)),
            ),
            const SizedBox(height: 8),
            Text('Campus Connect v1.0.0', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme, UserProvider userProvider,
      CampusProvider campusProvider) {
    final stats = <List<Object>>[
      ['Connections', userProvider.connections.length],
      ['Events', campusProvider.joinedEvents.length],
      ['Communities', campusProvider.joinedCommunities.length],
    ];

    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Column(
            children: [
              Text('${s[1]}',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.primaryColor)),
              const SizedBox(height: 2),
              Text(s[0] as String, style: theme.textTheme.bodySmall),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCompletionCard(
      BuildContext context, ThemeData theme, int completion, String hint) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
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
                  value: completion / 100,
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.25),
                  color: theme.primaryColor,
                  strokeWidth: 4,
                ),
              ),
              Text('$completion%', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  completion >= 100 ? 'Profile Complete' : 'Profile Incomplete',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(hint, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (completion < 100)
            TextButton(
              onPressed: () => _push(context, const EditProfileScreen()),
              child: const Text('Fix'),
            ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    String? trailingText,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.primaryColor, size: 20),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(trailingText, style: theme.textTheme.bodySmall),
          const SizedBox(width: 6),
          const Icon(LucideIcons.chevronRight, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Log out?',
      message: 'You will need to verify your CU email again to sign back in.',
      confirmLabel: 'Log out',
      isDestructive: true,
    );
    if (!ok || !context.mounted) return;

    await context.read<AuthProvider>().logout();
    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }
}

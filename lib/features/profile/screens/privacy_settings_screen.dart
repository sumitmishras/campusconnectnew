import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/screens/welcome_screen.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final userProvider = context.watch<UserProvider>();
    final me = auth.currentUser!;
    final blocked = userProvider.blockedStudents;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Privacy Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text('What others can see', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: !me.hideDepartment,
            title: const Text('Show my department'),
            subtitle: const Text('Visible on your profile and cards'),
            onChanged: (v) => auth.updatePrivacy(hideDepartment: !v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: !me.hideYear,
            title: const Text('Show my year'),
            subtitle: const Text('Lets juniors and seniors find you'),
            onChanged: (v) => auth.updatePrivacy(hideYear: !v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: !me.hideLookingFor,
            title: const Text('Show what I am looking for'),
            subtitle: const Text('Study partner, project partner, and so on'),
            onChanged: (v) => auth.updatePrivacy(hideLookingFor: !v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: !me.hideActiveStatus,
            title: const Text('Show active status'),
            subtitle: const Text('Others can see when you were last online'),
            onChanged: (v) => auth.updatePrivacy(hideActiveStatus: !v),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Blocked students', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text('${blocked.length}', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          if (blocked.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'You have not blocked anyone. Blocked students cannot see your profile or message you.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            ...blocked.map(
              (user) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  imageUrl: user.profilePhotoUrl,
                  name: user.name,
                  radius: 20,
                ),
                title: Text(user.name),
                subtitle: Text(user.department),
                trailing: TextButton(
                  onPressed: () async {
                    final ok = await userProvider.unblockUser(user);
                    if (!context.mounted) return;
                    showAppSnackBar(
                      context,
                      ok
                          ? '${user.name} unblocked'
                          : userProvider.lastActionError ??
                              'That student could not be unblocked.',
                      icon: ok
                          ? LucideIcons.userCheck
                          : LucideIcons.circleAlert,
                    );
                  },
                  child: const Text('Unblock'),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text('Your data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.fileText),
            title: const Text('Download my data'),
            subtitle: const Text('Get a copy of your profile and activity'),
            onTap: () => showAppSnackBar(
                context, 'We will email your data export within 24 hours',
                icon: LucideIcons.mail),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.trash2, color: Colors.red),
            title: const Text('Delete my account',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text('Removes your profile from this device'),
            onTap: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Delete account?',
                message:
                    'Your profile, connections and chats will be removed. This cannot be undone.',
                confirmLabel: 'Delete',
                isDestructive: true,
              );
              if (!ok || !context.mounted) return;
              await auth.deleteAccount();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

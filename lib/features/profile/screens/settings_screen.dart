import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/screens/welcome_screen.dart';
import 'help_support_screen.dart';
import 'privacy_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _connectionAlerts = true;
  bool _eventReminders = true;
  bool _messagePreviews = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          if (me != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  UserAvatar(
                      imageUrl: me.profilePhotoUrl, name: me.name, radius: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me.name, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(me.email, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          _sectionTitle(theme, 'Notifications'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pushNotifications,
            title: const Text('Push notifications'),
            onChanged: (v) => setState(() => _pushNotifications = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _connectionAlerts && _pushNotifications,
            title: const Text('Connection requests'),
            onChanged: _pushNotifications
                ? (v) => setState(() => _connectionAlerts = v)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _eventReminders && _pushNotifications,
            title: const Text('Event reminders'),
            onChanged: _pushNotifications
                ? (v) => setState(() => _eventReminders = v)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _messagePreviews && _pushNotifications,
            title: const Text('Show message previews'),
            onChanged: _pushNotifications
                ? (v) => setState(() => _messagePreviews = v)
                : null,
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, 'Appearance'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.moon),
            title: const Text('Theme'),
            subtitle: const Text('Follows your device setting'),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => showAppSnackBar(
              context,
              'Campus Connect follows your system light/dark setting',
              icon: LucideIcons.sun,
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, 'Account'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.shield),
            title: const Text('Privacy settings'),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.helpCircle),
            title: const Text('Help & support'),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.fileText),
            title: const Text('Terms & community guidelines'),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => _showGuidelines(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.info),
            title: const Text('About'),
            subtitle: const Text('Version 1.0.0 (demo build)'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Campus Connect',
              applicationVersion: '1.0.0',
              applicationLegalese:
                  'A student community app for Chandigarh University.',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.logOut, color: Colors.red),
            title: const Text('Log out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Log out?',
                message:
                    'You will need to verify your CU email again to sign back in.',
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
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  void _showGuidelines(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              Text('Community Guidelines',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: const [
                    _Guideline(
                      title: 'Be a real student',
                      body:
                          'Every account is tied to a verified @cuchd.in email. Impersonating another student gets you removed.',
                    ),
                    _Guideline(
                      title: 'Respect a no',
                      body:
                          'If someone declines your connection request or stops replying, do not send repeat requests.',
                    ),
                    _Guideline(
                      title: 'Keep it campus-appropriate',
                      body:
                          'No harassment, hate speech, or explicit content. Reports are reviewed by student moderators.',
                    ),
                    _Guideline(
                      title: 'No spam or selling',
                      body:
                          'Use the Buy & Sell community for trades instead of messaging people directly.',
                    ),
                    _Guideline(
                      title: 'Protect your privacy',
                      body:
                          'Never share passwords, OTPs or bank details. Campus Connect will never ask for them.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Guideline extends StatelessWidget {
  final String title;
  final String body;

  const _Guideline({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.checkCircle2, size: 16, color: theme.primaryColor),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(body, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

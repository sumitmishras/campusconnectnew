import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/connection_model.dart';
import '../../../core/models/report_reason.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../chat/screens/chat_detail_screen.dart';

class StudentProfileScreen extends StatelessWidget {
  final User user;

  const StudentProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: _circleAction(
          context,
          LucideIcons.chevronLeft,
          () => Navigator.pop(context),
        ),
        actions: [
          Consumer<UserProvider>(
            builder: (context, provider, _) => _circleAction(
              context,
              provider.isBookmarked(user.id)
                  ? LucideIcons.bookMarked
                  : LucideIcons.bookmark,
              () {
                final added = provider.toggleBookmark(user.id);
                showAppSnackBar(
                  context,
                  added ? 'Saved to bookmarks' : 'Removed from bookmarks',
                  icon: LucideIcons.bookmark,
                );
              },
            ),
          ),
          _circleAction(
            context,
            LucideIcons.moreVertical,
            () => _showOptions(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCover(theme),
            Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(user.name,
                              style: theme.textTheme.displayMedium),
                        ),
                        if (user.isVerified)
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(LucideIcons.checkCircle2,
                                color: theme.primaryColor, size: 24),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('@${user.username}', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    _buildMetaRow(theme),
                    const SizedBox(height: 24),
                    _buildActionButtons(context, theme),
                    const SizedBox(height: 28),
                    if (user.campusStatus != null) ...[
                      _buildStatusCard(theme),
                      const SizedBox(height: 24),
                    ],
                    _section(theme, 'About'),
                    Text(user.bio, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    if (user.interests.isNotEmpty) ...[
                      _section(theme, 'Interests'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: user.interests
                            .map((i) => TagChip(label: i))
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (!user.hideLookingFor && user.lookingFor.isNotEmpty) ...[
                      _section(theme, 'Looking For'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: user.lookingFor
                            .map((l) => TagChip(
                                  label: l,
                                  icon: LucideIcons.checkCircle,
                                  filled: true,
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (user.languages.isNotEmpty) ...[
                      _section(theme, 'Languages'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: user.languages
                            .map((l) => TagChip(label: l))
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                    _section(theme, 'Trust & Safety'),
                    _buildTrustRow(theme, LucideIcons.badgeCheck,
                        user.verificationLabel),
                    _buildTrustRow(theme, LucideIcons.shieldCheck, user.trustLabel),
                    if (user.badges.isNotEmpty)
                      _buildTrustRow(
                          theme, LucideIcons.award, user.badges.join(', ')),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ parts

  Widget _buildCover(ThemeData theme) {
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: theme.primaryColor),
          if (user.profilePhotoUrl.isNotEmpty)
            Image.network(
              user.profilePhotoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(ThemeData theme) {
    final items = <List<Object>>[
      [LucideIcons.graduationCap, user.course],
      if (!user.hideYear) [LucideIcons.calendar, user.year],
      if (!user.hideDepartment) [LucideIcons.building, user.department],
      if (user.lastActiveLabel.isNotEmpty)
        [LucideIcons.clock, user.lastActiveLabel],
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item[0] as IconData,
                size: 15, color: theme.textTheme.bodySmall?.color),
            const SizedBox(width: 6),
            Text(item[1] as String, style: theme.textTheme.bodySmall),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.megaphone, size: 18, color: theme.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(user.campusStatus!, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  /// The primary action, driven entirely by the relationship. Every one of
  /// the six states the provider can report has a button here, so the screen
  /// can never show "Connect" to someone who already sent you a request.
  Widget _buildActionButtons(BuildContext context, ThemeData theme) {
    return Selector<UserProvider, ConnectionStatus>(
      selector: (_, provider) => provider.relationshipWith(user.id),
      builder: (context, status, _) {
        final userProvider = context.read<UserProvider>();

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _onPrimaryAction(context, userProvider, status),
                    icon: Icon(_primaryIcon(status)),
                    label: Text(
                      _primaryLabel(status),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor:
                          status == ConnectionStatus.outgoing ||
                                  status == ConnectionStatus.blocked
                              ? theme.textTheme.bodySmall?.color
                              : theme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    icon: const Icon(LucideIcons.share2),
                    tooltip: 'Share profile',
                    onPressed: () => _shareProfile(context),
                  ),
                ),
              ],
            ),
            if (status == ConnectionStatus.outgoing) ...[
              const SizedBox(height: 8),
              Text(
                'Requested as ${userProvider.requestPurpose(user.id)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (status == ConnectionStatus.incoming) ...[
              const SizedBox(height: 8),
              Text(
                'Wants to connect as a ${userProvider.requestPurpose(user.id)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }

  IconData _primaryIcon(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return LucideIcons.messageCircle;
      case ConnectionStatus.outgoing:
        return LucideIcons.clock;
      case ConnectionStatus.incoming:
        return LucideIcons.check;
      case ConnectionStatus.blocked:
        return LucideIcons.ban;
      case ConnectionStatus.none:
        return LucideIcons.userPlus;
    }
  }

  String _primaryLabel(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Message';
      case ConnectionStatus.outgoing:
        return 'Requested';
      case ConnectionStatus.incoming:
        return 'Accept Request';
      case ConnectionStatus.blocked:
        return 'Blocked';
      case ConnectionStatus.none:
        return 'Connect';
    }
  }

  Future<void> _onPrimaryAction(
    BuildContext context,
    UserProvider provider,
    ConnectionStatus status,
  ) async {
    switch (status) {
      case ConnectionStatus.connected:
        _openChat(context);

      case ConnectionStatus.none:
        _showConnectionSheet(context, provider);

      case ConnectionStatus.outgoing:
        final ok = await provider.cancelRequest(user);
        if (!context.mounted) return;
        _report(context, provider, ok, 'Connection request withdrawn',
            icon: LucideIcons.userX);

      case ConnectionStatus.incoming:
        final ok = await provider.acceptRequest(user);
        if (!context.mounted) return;
        _report(context, provider, ok, 'Connected with ${user.name}!');

      case ConnectionStatus.blocked:
        await _unblock(context, provider);
    }
  }

  Future<void> _unblock(BuildContext context, UserProvider provider) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Unblock ${user.name}?',
      message:
          'They will be able to find your profile and message you again. Your '
          'previous connection is not restored.',
      confirmLabel: 'Unblock',
    );
    if (!confirmed || !context.mounted) return;

    final ok = await provider.unblockUser(user);
    if (!context.mounted) return;
    _report(context, provider, ok, '${user.name} unblocked');
  }

  /// One place for "did it work" messaging, so a rolled-back action always
  /// says why instead of silently snapping back.
  void _report(BuildContext context, UserProvider provider, bool ok,
      String successMessage,
      {IconData? icon}) {
    showAppSnackBar(
      context,
      ok
          ? successMessage
          : provider.lastActionError ?? 'That did not work. Please try again.',
      icon: ok ? (icon ?? LucideIcons.checkCircle2) : LucideIcons.circleAlert,
    );
  }

  Widget _section(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: theme.textTheme.titleLarge),
    );
  }

  Widget _buildTrustRow(ThemeData theme, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.primaryColor),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _circleAction(
      BuildContext context, IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 20),
          onPressed: onPressed,
        ),
      ),
    );
  }

  // --------------------------------------------------------------- actions

  Future<void> _openChat(BuildContext context) async {
    final chats = context.read<ChatProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // `get_or_create_direct_conversation` re-checks the block list and the
    // "connect first" rule, so this can legitimately refuse.
    final chat = await chats.openChatWith(user);
    if (chat == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          content: Text(chats.lastError ?? 'That chat could not be opened.'),
        ));
      chats.clearError();
      return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => ChatDetailScreen(chat: chat)),
    );
  }

  void _shareProfile(BuildContext context) {
    showAppSnackBar(
      context,
      'Profile link copied: campusconnect.cu/@${user.username}',
      icon: LucideIcons.link,
    );
  }

  void _showOptions(BuildContext context) {
    final userProvider = context.read<UserProvider>();

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              ListTile(
                leading: const Icon(LucideIcons.share2),
                title: const Text('Share profile'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _shareProfile(context);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text('Copy username'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showAppSnackBar(context, 'Copied @${user.username}');
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.flag, color: Colors.orange),
                title: const Text('Report',
                    style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReportSheet(context, userProvider);
                },
              ),
              if (userProvider.isBlocked(user.id))
                ListTile(
                  leading: const Icon(LucideIcons.userCheck),
                  title: const Text('Unblock'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _unblock(context, userProvider);
                  },
                )
              else
                ListTile(
                  leading: const Icon(LucideIcons.ban, color: Colors.red),
                  title: const Text('Block',
                      style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Block ${user.name}?',
                      message:
                          'They will not be able to find your profile or message you. You can undo this from Privacy Settings.',
                      confirmLabel: 'Block',
                      isDestructive: true,
                    );
                    if (!confirmed || !context.mounted) return;

                    // Grabbed before popping — the snack bar outlives this
                    // screen, and on failure it is the only thing that will
                    // explain why the block did not stick.
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await userProvider.blockUser(user);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        content: Text(ok
                            ? '${user.name} has been blocked'
                            : userProvider.lastActionError ??
                                'That student could not be blocked.'),
                      ));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportSheet(BuildContext context, UserProvider userProvider) {
    // The labels are unchanged; what changed is that each one now carries a
    // value `reports.reason` will accept. The old sheet posted its label text,
    // which the CHECK constraint would have rejected outright.
    const reasons = kProfileReportReasons;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Text('Report ${user.name}',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Reports are reviewed by the campus moderation team.',
                  style: Theme.of(sheetContext).textTheme.bodySmall),
              const SizedBox(height: 16),
              ...reasons.map(
                (reason) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason.label),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await userProvider.reportUser(user, reason);
                    if (!context.mounted) return;
                    _report(
                      context,
                      userProvider,
                      ok,
                      'Report submitted. Thanks for keeping campus safe.',
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConnectionSheet(BuildContext context, UserProvider userProvider) {
    const purposes = <List<Object>>[
      ['Friendship', LucideIcons.users],
      ['Study Partner', LucideIcons.bookOpen],
      ['Networking', LucideIcons.briefcase],
      ['Coffee Chat', LucideIcons.coffee],
      ['Project Partner', LucideIcons.code],
      ['Gym Partner', LucideIcons.trendingUp],
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                Text('Send Connection Request',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Pick why you want to connect — ${user.name.split(' ').first} will see this.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: purposes.map((p) {
                    return SizedBox(
                      width: 100,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          final ok = await userProvider.sendConnectionRequest(
                              user, p[0] as String);
                          if (!context.mounted) return;
                          _report(
                            context,
                            userProvider,
                            ok,
                            'Request sent to ${user.name} for ${p[0]}',
                            icon: LucideIcons.userPlus,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(p[1] as IconData,
                                  size: 22, color: theme.primaryColor),
                              const SizedBox(height: 8),
                              Text(
                                p[0] as String,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

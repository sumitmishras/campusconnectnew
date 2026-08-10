import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/connection_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../profile/screens/student_profile_screen.dart';

/// What a card needs from [UserProvider], and nothing else.
///
/// A record so `Selector` can compare it structurally: accepting one request
/// used to rebuild every card on screen, because each one watched the whole
/// provider. Now only the card whose pair actually changed rebuilds.
typedef _CardState = ({ConnectionStatus status, bool bookmarked});

class StudentCard extends StatelessWidget {
  final User student;

  const StudentCard({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    return Selector<UserProvider, _CardState>(
      selector: (_, provider) => (
        status: provider.relationshipWith(student.id),
        bookmarked: provider.isBookmarked(student.id),
      ),
      builder: (context, state, _) => _buildCard(context, state),
    );
  }

  Widget _buildCard(BuildContext context, _CardState state) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openProfile(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, theme, state.bookmarked),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            student.name,
                            style: theme.textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (student.isVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  theme.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.checkCircle2,
                                    size: 14, color: theme.primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (!student.hideYear) student.year,
                        student.course,
                        if (!student.hideDepartment) student.department,
                      ].join(' • '),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.textTheme.bodySmall?.color),
                    ),
                    if (student.campusStatus != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Text('💬 ', style: TextStyle(fontSize: 12)),
                            Expanded(
                              child: Text(
                                student.campusStatus!,
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: student.interests
                          .map((i) => TagChip(label: i))
                          .toList(),
                    ),
                    if (!student.hideLookingFor &&
                        student.lookingFor.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Looking for: ${student.lookingFor.join(', ')}',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.primaryColor),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildConnectButton(
                              context, theme, state.status),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => _openProfile(context),
                          icon: const Icon(LucideIcons.user, size: 16),
                          label: const Text('Profile'),
                        ),
                      ],
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

  Widget _buildHeader(
      BuildContext context, ThemeData theme, bool isBookmarked) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.1),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (student.profilePhotoUrl.isNotEmpty)
            Image.network(
              student.profilePhotoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Icon(LucideIcons.user,
                    size: 56,
                    color: theme.primaryColor.withValues(alpha: 0.5)),
              ),
            )
          else
            Center(
              child: Icon(LucideIcons.user,
                  size: 56, color: theme.primaryColor.withValues(alpha: 0.5)),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: IconButton(
                iconSize: 18,
                icon: Icon(
                  isBookmarked ? LucideIcons.bookMarked : LucideIcons.bookmark,
                  color: Colors.white,
                ),
                tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
                onPressed: () {
                  final added = context
                      .read<UserProvider>()
                      .toggleBookmark(student.id);
                  showAppSnackBar(
                    context,
                    added
                        ? 'Saved ${student.name} to bookmarks'
                        : 'Removed from bookmarks',
                    icon: LucideIcons.bookmark,
                  );
                },
              ),
            ),
          ),
          if (student.isOnline && !student.hideActiveStatus)
            Positioned(
              bottom: 8,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 4, backgroundColor: Colors.green),
                    SizedBox(width: 6),
                    Text('Online',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectButton(
      BuildContext context, ThemeData theme, ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return ElevatedButton.icon(
          onPressed: () => _openProfile(context),
          icon: const Icon(LucideIcons.userCheck, size: 16),
          label: const Text('Connected'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
            foregroundColor: theme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        );

      case ConnectionStatus.outgoing:
        return OutlinedButton.icon(
          onPressed: () => _withdraw(context),
          icon: const Icon(LucideIcons.clock, size: 16),
          label: const Text('Requested'),
        );

      case ConnectionStatus.incoming:
        return ElevatedButton.icon(
          onPressed: () => _accept(context),
          icon: const Icon(LucideIcons.check, size: 16),
          label: const Text('Accept'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        );

      case ConnectionStatus.blocked:
        return OutlinedButton.icon(
          onPressed: () => _openProfile(context),
          icon: const Icon(LucideIcons.ban, size: 16),
          label: const Text('Blocked'),
        );

      case ConnectionStatus.none:
        return ElevatedButton.icon(
          onPressed: () => _openProfile(context),
          icon: const Icon(LucideIcons.userPlus, size: 16),
          label: const Text('Connect'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        );
    }
  }

  Future<void> _withdraw(BuildContext context) async {
    final provider = context.read<UserProvider>();
    final ok = await provider.cancelRequest(student);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      ok
          ? 'Request withdrawn'
          : provider.lastActionError ?? 'That request could not be withdrawn.',
      icon: ok ? LucideIcons.userX : LucideIcons.circleAlert,
    );
  }

  Future<void> _accept(BuildContext context) async {
    final provider = context.read<UserProvider>();
    final ok = await provider.acceptRequest(student);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      ok
          ? 'Connected with ${student.name}!'
          : provider.lastActionError ?? 'That request could not be accepted.',
      icon: ok ? LucideIcons.checkCircle2 : LucideIcons.circleAlert,
    );
  }

  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentProfileScreen(user: student)),
    );
  }
}

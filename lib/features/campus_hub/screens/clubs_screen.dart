import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/campus_models.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../chat/screens/group_chat_screen.dart';

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();
    final clubs = campus.clubsByCategory(_category);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Campus Clubs'),
      ),
      body: campus.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: campus.clubCategories.map((c) {
                      final selected = _category == c;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(c),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _category = c),
                          labelStyle: TextStyle(
                            color: selected
                                ? theme.primaryColor
                                : theme.textTheme.bodyMedium?.color,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: selected
                                ? theme.primaryColor
                                : theme.dividerColor,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: clubs.isEmpty
                      ? const EmptyState(
                          icon: LucideIcons.tent,
                          title: 'No clubs found',
                          message: 'Try a different category.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: clubs.length,
                          itemBuilder: (context, index) =>
                              _buildCard(theme, campus, clubs[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCard(ThemeData theme, CampusProvider campus, Club club) {
    final joined = campus.isClubJoined(club.id);

    return AppCard(
      onTap: () => _showDetails(theme, campus, club),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                child: Icon(LucideIcons.tent,
                    color: theme.primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(club.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        TagChip(label: club.category),
                        const SizedBox(width: 8),
                        Text('${club.memberCount} members',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            club.description,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.textTheme.bodySmall?.color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.clock, size: 14, color: theme.primaryColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(club.meetingSchedule,
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 14),
          joined
              ? Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openChat(club),
                        icon: const Icon(LucideIcons.messageCircle, size: 16),
                        label: const Text('Open chat'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _toggleJoin(campus, club),
                      icon: const Icon(LucideIcons.checkCircle2, size: 16),
                      label: const Text('Joined'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.primaryColor,
                        side: BorderSide(color: theme.primaryColor),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _toggleJoin(campus, club),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Join Club'),
                  ),
                ),
        ],
      ),
    );
  }

  void _showDetails(ThemeData theme, CampusProvider campus, Club club) {
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
              Text(club.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(club.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              _row(theme, LucideIcons.user, 'Club lead', club.lead),
              _row(theme, LucideIcons.clock, 'Meets', club.meetingSchedule),
              _row(theme, LucideIcons.users, 'Members',
                  '${club.memberCount} students'),
              const SizedBox(height: 20),
              if (campus.isClubJoined(club.id)) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openChat(club);
                  },
                  icon: const Icon(LucideIcons.messageCircle, size: 18),
                  label: const Text('Open group chat'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _toggleJoin(campus, club);
                  },
                  child: const Text('Leave club'),
                ),
              ] else
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _toggleJoin(campus, club);
                  },
                  child: const Text('Join club'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Joining also creates the club's group chat, leaving removes it.
  void _toggleJoin(CampusProvider campus, Club club) {
    final chat = context.read<ChatProvider>();
    final joined = campus.toggleClubJoin(club.id);

    if (joined) {
      chat.joinGroupChat(
        id: club.id,
        conversationId: club.conversationId,
        name: club.name,
        kind: GroupKind.club,
        description: club.description,
        memberCount: club.memberCount + 1,
      );
      showAppSnackBar(
        context,
        'Joined ${club.name} — group chat added to Chats',
        icon: LucideIcons.messageCircle,
      );
    } else {
      chat.leaveGroupChat(club.id);
      showAppSnackBar(context, 'Left ${club.name}');
    }
  }

  void _openChat(Club club) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: club.id)),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.primaryColor),
          const SizedBox(width: 10),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

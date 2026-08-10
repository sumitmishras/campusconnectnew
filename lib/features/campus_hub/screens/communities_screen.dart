import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/campus_models.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../chat/screens/group_chat_screen.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _tab = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();

    var list = campus.communities;
    if (_tab == 'Departments') {
      list = list.where((c) => c.isDepartment).toList();
    } else if (_tab == 'Interests') {
      list = list.where((c) => !c.isDepartment).toList();
    } else if (_tab == 'Joined') {
      list = campus.joinedCommunities;
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.description.toLowerCase().contains(q))
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Communities'),
      ),
      body: campus.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: const InputDecoration(
                      hintText: 'Search communities...',
                      prefixIcon: Icon(LucideIcons.search, size: 20),
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children:
                        ['All', 'Departments', 'Interests', 'Joined'].map((t) {
                      final selected = _tab == t;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(t),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _tab = t),
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
                const SizedBox(height: 8),
                Expanded(
                  child: list.isEmpty
                      ? EmptyState(
                          icon: LucideIcons.users2,
                          title: 'Nothing here yet',
                          message: _tab == 'Joined'
                              ? 'Join a community and it will show up in this tab.'
                              : 'No community matches your search.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          itemBuilder: (context, index) =>
                              _buildCard(theme, campus, list[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCard(
      ThemeData theme, CampusProvider campus, Community community) {
    final joined = campus.isCommunityJoined(community.id);

    return AppCard(
      onTap: () => _showDetails(theme, campus, community),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
            child: Icon(
              community.isDepartment ? LucideIcons.building : LucideIcons.users,
              color: theme.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(community.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${community.memberCount} members',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.primaryColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (joined) ...[
            IconButton(
              icon: const Icon(LucideIcons.messageCircle),
              color: theme.primaryColor,
              tooltip: 'Open group chat',
              onPressed: () => _openChat(community),
            ),
            OutlinedButton(
              onPressed: () => _toggleJoin(campus, community),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.primaryColor,
                side: BorderSide(color: theme.primaryColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Joined'),
            ),
          ] else
            ElevatedButton(
              onPressed: () => _toggleJoin(campus, community),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Join'),
            ),
        ],
      ),
    );
  }

  /// Joining a community and appearing in its chat are the same INSERT into
  /// `conversation_members` — `CampusProvider` owns that write, and this only
  /// tells `ChatProvider` the thread is now in the student's list.
  void _toggleJoin(CampusProvider campus, Community community) {
    final chat = context.read<ChatProvider>();
    final joined = campus.toggleCommunityJoin(community.id);

    if (joined) {
      chat.joinGroupChat(
        id: community.id,
        conversationId: community.conversationId,
        name: community.name,
        kind: GroupKind.community,
        description: community.description,
        memberCount: community.memberCount + 1,
      );
      showAppSnackBar(
        context,
        'Joined ${community.name} — group chat added to Chats',
        icon: LucideIcons.messageCircle,
      );
    } else {
      chat.leaveGroupChat(community.id);
      showAppSnackBar(context, 'Left ${community.name}');
    }
  }

  void _openChat(Community community) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(groupId: community.id),
      ),
    );
  }

  void _showDetails(
      ThemeData theme, CampusProvider campus, Community community) {
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
              Text(community.name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${community.memberCount} members',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.primaryColor)),
              const SizedBox(height: 16),
              Text(community.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              if (campus.isCommunityJoined(community.id)) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openChat(community);
                  },
                  icon: const Icon(LucideIcons.messageCircle, size: 18),
                  label: const Text('Open group chat'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _toggleJoin(campus, community);
                  },
                  child: const Text('Leave community'),
                ),
              ] else
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _toggleJoin(campus, community);
                  },
                  child: const Text('Join community'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

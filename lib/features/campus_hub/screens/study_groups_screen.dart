import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/campus_models.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/models/connection_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/providers/chat_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../chat/screens/group_chat_screen.dart';
import '../../profile/screens/student_profile_screen.dart';

class StudyGroupsScreen extends StatelessWidget {
  const StudyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Study Groups'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Groups'),
              Tab(text: 'Find a partner'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showCreateSheet(context, campus),
          backgroundColor: theme.primaryColor,
          icon: const Icon(LucideIcons.plus, color: Colors.white),
          label: const Text('New group',
              style: TextStyle(color: Colors.white)),
        ),
        body: campus.isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildGroups(context, theme, campus),
                  const _StudyPartnersTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildGroups(
      BuildContext context, ThemeData theme, CampusProvider campus) {
    final groups = campus.studyGroups;
    if (groups.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.bookOpen,
        title: 'No study groups yet',
        message: 'Be the first to create one for your subject.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final joined = campus.isStudyGroupJoined(group.id);

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TagChip(label: group.subject, filled: true),
                  const Spacer(),
                  Text(
                    '${group.memberCount}/${group.maxMembers}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(group.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                group.description,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _meta(theme, LucideIcons.clock, group.schedule),
                  _meta(theme, LucideIcons.mapPin, group.venue),
                  _meta(theme, LucideIcons.user, 'Host: ${group.hostName}'),
                ],
              ),
              const SizedBox(height: 14),
              joined
                  ? Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    GroupChatScreen(groupId: group.id),
                              ),
                            ),
                            icon: const Icon(LucideIcons.messageCircle,
                                size: 16),
                            label: const Text('Open chat'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _toggleJoin(context, campus, group),
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
                        onPressed: group.isFull
                            ? null
                            : () => _toggleJoin(context, campus, group),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child:
                            Text(group.isFull ? 'Group is full' : 'Join group'),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  /// Joining also creates the study group's chat thread, leaving removes it.
  void _toggleJoin(
      BuildContext context, CampusProvider campus, StudyGroup group) {
    final chat = context.read<ChatProvider>();
    final joined = campus.toggleStudyGroupJoin(group.id);

    if (joined) {
      chat.joinGroupChat(
        id: group.id,
        conversationId: group.conversationId,
        name: group.title,
        kind: GroupKind.studyGroup,
        description: group.description,
        memberCount: group.memberCount + 1,
      );
      showAppSnackBar(
        context,
        'Joined ${group.title} — group chat added to Chats',
        icon: LucideIcons.messageCircle,
      );
    } else {
      chat.leaveGroupChat(group.id);
      showAppSnackBar(context, 'Left ${group.title}');
    }
  }

  Widget _meta(ThemeData theme, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.primaryColor),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  void _showCreateSheet(BuildContext context, CampusProvider campus) {
    final subjectController = TextEditingController();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final scheduleController = TextEditingController();
    final venueController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Text('Create a study group',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 20),
              CustomTextField(
                  label: 'Subject',
                  hint: 'e.g. Data Structures',
                  controller: subjectController),
              const SizedBox(height: 14),
              CustomTextField(
                  label: 'Group name',
                  hint: 'e.g. DSA Daily Grind',
                  controller: titleController),
              const SizedBox(height: 14),
              CustomTextField(
                label: 'What will you do?',
                hint: 'Describe the plan in a line or two',
                controller: descriptionController,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              CustomTextField(
                  label: 'Schedule',
                  hint: 'e.g. Mon–Fri, 8:00 PM',
                  controller: scheduleController),
              const SizedBox(height: 14),
              CustomTextField(
                  label: 'Venue',
                  hint: 'e.g. Library, 2nd Floor',
                  controller: venueController),
              const SizedBox(height: 24),
              CustomButton(
                text: 'Create group',
                onPressed: () async {
                  if (subjectController.text.trim().isEmpty ||
                      titleController.text.trim().isEmpty) {
                    showAppSnackBar(
                        sheetContext, 'Subject and group name are required',
                        icon: LucideIcons.circleAlert);
                    return;
                  }
                  final me = sheetContext.read<AuthProvider>().currentUser;
                  final chats = sheetContext.read<ChatProvider>();
                  final navigator = Navigator.of(sheetContext);
                  final messenger = ScaffoldMessenger.of(context);

                  // `create_study_group()` makes the group, its thread and the
                  // host's membership in one transaction, so this waits for the
                  // ids it allocated rather than guessing them.
                  final created = await campus.createStudyGroup(
                    subject: subjectController.text.trim(),
                    title: titleController.text.trim(),
                    description: descriptionController.text.trim().isEmpty
                        ? 'A study group for ${subjectController.text.trim()}.'
                        : descriptionController.text.trim(),
                    schedule: scheduleController.text.trim().isEmpty
                        ? 'To be decided'
                        : scheduleController.text.trim(),
                    venue: venueController.text.trim().isEmpty
                        ? 'To be decided'
                        : venueController.text.trim(),
                    hostName: me?.name ?? 'You',
                  );

                  navigator.pop();
                  if (created == null) {
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        content: Text(campus.lastActionError ??
                            'That study group could not be created.'),
                      ));
                    return;
                  }

                  // A brand new group starts with an empty thread.
                  chats.joinGroupChat(
                    id: created.id,
                    conversationId: created.conversationId,
                    name: created.title,
                    kind: GroupKind.studyGroup,
                    description: created.description,
                    memberCount: created.memberCount,
                  );
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.all(16),
                      content:
                          Text('Study group created — chat is ready in Chats'),
                    ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Students who listed "Study Partner" in what they are looking for.
class _StudyPartnersTab extends StatelessWidget {
  const _StudyPartnersTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.watch<UserProvider>();
    // Served by the repository rather than filtered out of whatever Discover
    // happened to have paged in, so this tab is not silently limited to the
    // first twenty students.
    final partners = userProvider.studentsLookingFor(const ['Study Partner']);

    if (userProvider.isLoadingPartners && partners.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (partners.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.users,
        title: 'Nobody available',
        message: 'No student is currently looking for a study partner.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: partners.length,
      itemBuilder: (context, index) {
        final user = partners[index];
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StudentProfileScreen(user: user)),
          ),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: user.profilePhotoUrl,
                name: user.name,
                showOnlineDot: true,
                isOnline: user.isOnline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${user.course} • ${user.year}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StudentProfileScreen(user: user)),
                ),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                child: Text(
                  userProvider.relationshipWith(user.id).isConnected
                      ? 'View'
                      : 'Connect',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

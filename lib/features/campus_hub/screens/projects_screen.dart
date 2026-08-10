import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/connection_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../profile/screens/student_profile_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

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
          title: const Text('Projects & Startups'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Open projects'),
              Tab(text: 'Find teammates'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showCreateSheet(context, campus),
          backgroundColor: theme.primaryColor,
          icon: const Icon(LucideIcons.plus, color: Colors.white),
          label: const Text('Post project',
              style: TextStyle(color: Colors.white)),
        ),
        body: campus.isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildProjects(context, theme, campus),
                  const _TeammatesTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildProjects(
      BuildContext context, ThemeData theme, CampusProvider campus) {
    final projects = campus.projects;
    if (projects.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.code,
        title: 'No projects listed',
        message: 'Post your idea and find teammates on campus.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        final applied = campus.hasAppliedToProject(project.id);

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TagChip(label: project.stage, filled: true),
                  const Spacer(),
                  Text('${project.applicantCount} applied',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 10),
              Text(project.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                project.description,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    project.techStack.map((t) => TagChip(label: t)).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.userPlus,
                      size: 14, color: theme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Looking for: ${project.rolesNeeded.join(', ')}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.primaryColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(LucideIcons.user,
                      size: 13, color: theme.textTheme.bodySmall?.color),
                  const SizedBox(width: 6),
                  Text('by ${project.ownerName}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: applied
                    ? OutlinedButton.icon(
                        onPressed: () {
                          campus.toggleProjectApplication(project.id);
                          showAppSnackBar(context, 'Application withdrawn');
                        },
                        icon: const Icon(LucideIcons.checkCircle2, size: 16),
                        label: const Text('Applied'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.primaryColor,
                          side: BorderSide(color: theme.primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () {
                          campus.toggleProjectApplication(project.id);
                          showAppSnackBar(context,
                              'Applied to ${project.title}. ${project.ownerName} will be notified.',
                              icon: LucideIcons.rocket);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Apply to join'),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateSheet(BuildContext context, CampusProvider campus) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final techController = TextEditingController();
    final rolesController = TextEditingController();
    var stage = 'Idea';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setSheetState) => Padding(
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
                Text('Post a project',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 20),
                CustomTextField(
                    label: 'Project title',
                    hint: 'e.g. Campus Lost & Found App',
                    controller: titleController),
                const SizedBox(height: 14),
                CustomTextField(
                  label: 'Description',
                  hint: 'What are you building and why?',
                  controller: descriptionController,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                Text('Stage',
                    style: Theme.of(sheetContext).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['Idea', 'Prototype', 'Building', 'Launched']
                      .map((s) => ChoiceChip(
                            label: Text(s),
                            selected: stage == s,
                            showCheckmark: false,
                            onSelected: (_) => setSheetState(() => stage = s),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),
                CustomTextField(
                    label: 'Tech stack',
                    hint: 'Flutter, Firebase (comma separated)',
                    controller: techController),
                const SizedBox(height: 14),
                CustomTextField(
                    label: 'Roles needed',
                    hint: 'UI Designer, Backend Dev (comma separated)',
                    controller: rolesController),
                const SizedBox(height: 24),
                CustomButton(
                  text: 'Post project',
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) {
                      showAppSnackBar(sheetContext, 'Please add a title',
                          icon: LucideIcons.circleAlert);
                      return;
                    }
                    final me = sheetContext.read<AuthProvider>().currentUser;
                    final navigator = Navigator.of(sheetContext);
                    final messenger = ScaffoldMessenger.of(context);

                    final ok = await campus.createProject(
                      title: titleController.text.trim(),
                      description: descriptionController.text.trim().isEmpty
                          ? 'Looking for teammates to build this.'
                          : descriptionController.text.trim(),
                      stage: stage,
                      techStack: _split(techController.text),
                      rolesNeeded: _split(rolesController.text),
                      ownerName: me?.name ?? 'You',
                    );

                    navigator.pop();
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        content: Text(ok
                            ? 'Project posted!'
                            : campus.lastActionError ??
                                'That project could not be posted.'),
                      ));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<String> _split(String raw) {
    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? ['Anyone interested'] : parts;
  }
}

/// Students open to project or startup collaboration.
class _TeammatesTab extends StatelessWidget {
  const _TeammatesTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.watch<UserProvider>();
    // Repository-backed for the same reason the study-partner tab is: an
    // "any of these purposes" query, not a filter over the current page.
    final people = userProvider.studentsLookingFor(
        const ['Project Partner', 'Startup Co-founder']);

    if (userProvider.isLoadingPartners && people.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (people.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.users,
        title: 'No teammates listed',
        message: 'Nobody is currently looking for project collaborations.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: people.length,
      itemBuilder: (context, index) {
        final user = people[index];
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StudentProfileScreen(user: user)),
          ),
          child: Row(
            children: [
              UserAvatar(imageUrl: user.profilePhotoUrl, name: user.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      user.lookingFor.contains('Startup Co-founder')
                          ? 'Startup Co-founder'
                          : 'Project Partner',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.primaryColor),
                    ),
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

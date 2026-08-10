import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/campus_models.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';

class PollsScreen extends StatelessWidget {
  const PollsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Campus Polls'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context, campus),
        backgroundColor: theme.primaryColor,
        icon: const Icon(LucideIcons.plus, color: Colors.white),
        label: const Text('New poll', style: TextStyle(color: Colors.white)),
      ),
      body: campus.isLoading
          ? const Center(child: CircularProgressIndicator())
          : campus.polls.isEmpty
              ? const EmptyState(
                  icon: LucideIcons.barChart3,
                  title: 'No polls yet',
                  message: 'Start one and see what the campus thinks.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: campus.polls.length,
                  itemBuilder: (context, index) =>
                      _buildPollCard(context, theme, campus, campus.polls[index]),
                ),
    );
  }

  Widget _buildPollCard(BuildContext context, ThemeData theme,
      CampusProvider campus, Poll poll) {
    final totalVotes = poll.totalVotes;

    return AppCard(
      padding: const EdgeInsets.all(20),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                child: Icon(LucideIcons.user,
                    size: 14, color: theme.primaryColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(poll.authorName, style: theme.textTheme.bodySmall),
              ),
              Text(_timeAgo(poll.createdAt), style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 14),
          Text(poll.question, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          ...poll.options.map((option) {
            final percentage = totalVotes == 0 ? 0.0 : option.votes / totalVotes;
            final isChoice = poll.votedOptionId == option.id;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: poll.hasVoted
                    ? null
                    : () {
                        campus.votePoll(poll.id, option.id);
                        showAppSnackBar(context, 'Vote recorded!',
                            icon: LucideIcons.barChart3);
                      },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isChoice
                          ? theme.primaryColor
                          : poll.hasVoted
                              ? theme.dividerColor.withValues(alpha: 0.3)
                              : theme.primaryColor.withValues(alpha: 0.6),
                      width: isChoice ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      if (poll.hasVoted)
                        FractionallySizedBox(
                          widthFactor: percentage.clamp(0.0, 1.0),
                          child: Container(
                            color: theme.primaryColor
                                .withValues(alpha: isChoice ? 0.25 : 0.12),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            if (isChoice) ...[
                              Icon(LucideIcons.checkCircle2,
                                  size: 16, color: theme.primaryColor),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                option.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: poll.hasVoted
                                      ? FontWeight.normal
                                      : FontWeight.w600,
                                  color: poll.hasVoted
                                      ? null
                                      : theme.primaryColor,
                                ),
                              ),
                            ),
                            if (poll.hasVoted)
                              Text(
                                '${(percentage * 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.titleMedium,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          Text(
            poll.hasVoted
                ? '$totalVotes votes • You voted'
                : '$totalVotes votes • Tap an option to vote',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showCreateSheet(BuildContext context, CampusProvider campus) {
    final questionController = TextEditingController();
    final optionControllers = [
      TextEditingController(),
      TextEditingController(),
    ];

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
                Text('Create a poll',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 20),
                CustomTextField(
                  label: 'Question',
                  hint: 'What do you want to ask the campus?',
                  controller: questionController,
                  maxLength: 120,
                ),
                const SizedBox(height: 16),
                ...List.generate(optionControllers.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CustomTextField(
                      label: 'Option ${i + 1}',
                      hint: 'Type an option',
                      controller: optionControllers[i],
                      maxLength: 40,
                      suffixIcon: optionControllers.length > 2
                          ? IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () => setSheetState(
                                  () => optionControllers.removeAt(i)),
                            )
                          : null,
                    ),
                  );
                }),
                if (optionControllers.length < 4)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setSheetState(
                          () => optionControllers.add(TextEditingController())),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Add option'),
                    ),
                  ),
                const SizedBox(height: 16),
                CustomButton(
                  text: 'Publish poll',
                  onPressed: () async {
                    final question = questionController.text.trim();
                    final options = optionControllers
                        .map((c) => c.text.trim())
                        .where((t) => t.isNotEmpty)
                        .toList();

                    if (question.isEmpty) {
                      showAppSnackBar(sheetContext, 'Add a question first',
                          icon: LucideIcons.circleAlert);
                      return;
                    }
                    if (options.length < 2) {
                      showAppSnackBar(
                          sheetContext, 'Add at least two options',
                          icon: LucideIcons.circleAlert);
                      return;
                    }

                    final me = sheetContext.read<AuthProvider>().currentUser;
                    final navigator = Navigator.of(sheetContext);
                    final messenger = ScaffoldMessenger.of(context);

                    // A poll and its options are created together — a poll
                    // with no options is not a poll.
                    final ok = await campus.createPoll(
                      question: question,
                      options: options,
                      authorName: me?.name ?? 'You',
                    );

                    navigator.pop();
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        content: Text(ok
                            ? 'Poll published!'
                            : campus.lastActionError ??
                                'That poll could not be published.'),
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
}

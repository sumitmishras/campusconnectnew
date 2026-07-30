import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/models/campus_models.dart';

class PollsScreen extends StatelessWidget {
  const PollsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campusProvider = context.watch<CampusProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Campus Polls', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
      ),
      body: campusProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: campusProvider.polls.length,
              itemBuilder: (context, index) {
                final poll = campusProvider.polls[index];
                return _buildPollCard(poll, theme, context, campusProvider);
              },
            ),
    );
  }

  Widget _buildPollCard(Poll poll, ThemeData theme, BuildContext context, CampusProvider provider) {
    int totalVotes = poll.options.fold(0, (sum, option) => sum + option.votes);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(poll.question, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          ...poll.options.map((option) {
            double percentage = totalVotes == 0 ? 0 : (option.votes / totalVotes);
            return GestureDetector(
              onTap: () {
                if (!poll.hasVoted) {
                  provider.votePoll(poll.id, option.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Vote cast successfully!')),
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: poll.hasVoted ? theme.dividerColor.withOpacity(0.1) : theme.primaryColor,
                  ),
                ),
                child: Stack(
                  children: [
                    if (poll.hasVoted)
                      FractionallySizedBox(
                        widthFactor: percentage,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            option.text,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: poll.hasVoted ? FontWeight.normal : FontWeight.bold,
                              color: poll.hasVoted ? null : theme.primaryColor,
                            ),
                          ),
                          if (poll.hasVoted)
                            Text(
                              '${(percentage * 100).toStringAsFixed(1)}%',
                              style: theme.textTheme.titleMedium,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(
            '$totalVotes votes',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/campus_models.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import 'event_detail_screen.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();
    final events = campus.events;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Campus Events'),
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
                    children: CampusProvider.eventCategories.map((c) {
                      final selected = campus.eventCategory == c;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(c),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (_) => campus.setEventCategory(c),
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
                  child: events.isEmpty
                      ? EmptyState(
                          icon: LucideIcons.calendarDays,
                          title: 'No events here',
                          message:
                              'Nothing scheduled under ${campus.eventCategory} right now.',
                          actionLabel: 'Show all events',
                          onAction: () => campus.setEventCategory('All'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: events.length,
                          itemBuilder: (context, index) =>
                              EventCard(event: events[index]),
                        ),
                ),
              ],
            ),
    );
  }
}

class EventCard extends StatelessWidget {
  final Event event;

  const EventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();
    final isJoined = campus.isEventJoined(event.id);
    final isSaved = campus.isEventSaved(event.id);

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TagChip(label: event.category, filled: true),
              const SizedBox(width: 8),
              if (event.daysAway <= 3 && !event.isPast)
                TagChip(
                  label: event.daysAway <= 0
                      ? 'Today'
                      : 'In ${event.daysAway} day${event.daysAway == 1 ? '' : 's'}',
                  icon: LucideIcons.clock,
                ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isSaved ? LucideIcons.bookmarkCheck : LucideIcons.bookmark,
                  size: 20,
                  color: isSaved
                      ? theme.primaryColor
                      : theme.textTheme.bodySmall?.color,
                ),
                tooltip: isSaved ? 'Remove from saved' : 'Save event',
                onPressed: () {
                  final saved = campus.toggleEventSaved(event.id);
                  showAppSnackBar(
                    context,
                    saved ? 'Event saved' : 'Removed from saved',
                    icon: LucideIcons.bookmark,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(event.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            event.description,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.textTheme.bodySmall?.color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _meta(theme, LucideIcons.calendar,
                  DateFormat('MMM dd, h:mm a').format(event.date)),
              _meta(theme, LucideIcons.mapPin, event.venue),
              _meta(theme, LucideIcons.users, '${event.goingCount} going'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: isJoined
                    ? OutlinedButton.icon(
                        onPressed: () {
                          campus.toggleEventJoin(event.id);
                          showAppSnackBar(context, 'Registration cancelled',
                              icon: LucideIcons.x);
                        },
                        icon: const Icon(LucideIcons.checkCircle2, size: 16),
                        label: const Text('Going'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.primaryColor,
                          side: BorderSide(color: theme.primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () {
                          campus.toggleEventJoin(event.id);
                          showAppSnackBar(
                              context, 'Registered for ${event.title}!',
                              icon: LucideIcons.partyPopper);
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Join Event'),
                      ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EventDetailScreen(event: event)),
                ),
                child: const Text('Details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.primaryColor),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

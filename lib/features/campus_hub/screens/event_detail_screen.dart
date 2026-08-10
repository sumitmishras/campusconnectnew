import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/models/campus_models.dart';
import '../../../core/providers/campus_provider.dart';
import '../../../core/widgets/app_widgets.dart';

class EventDetailScreen extends StatelessWidget {
  final Event event;

  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campus = context.watch<CampusProvider>();
    final current = campus.eventById(event.id) ?? event;
    final isJoined = campus.isEventJoined(current.id);
    final isSaved = campus.isEventSaved(current.id);
    final spotsLeft = current.maxParticipants - current.goingCount;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Event Details'),
        actions: [
          IconButton(
            icon: Icon(
                isSaved ? LucideIcons.bookmarkCheck : LucideIcons.bookmark),
            color: isSaved ? theme.primaryColor : null,
            onPressed: () {
              final saved = campus.toggleEventSaved(current.id);
              showAppSnackBar(
                  context, saved ? 'Event saved' : 'Removed from saved');
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.share2),
            onPressed: () => showAppSnackBar(
              context,
              'Event link copied to clipboard',
              icon: LucideIcons.link,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primaryColor, theme.colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Icon(_iconFor(current.category),
                  size: 56, color: Colors.white.withValues(alpha: 0.9)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TagChip(label: current.category, filled: true),
              const SizedBox(width: 8),
              TagChip(label: current.fee, icon: LucideIcons.ticket),
            ],
          ),
          const SizedBox(height: 14),
          Text(current.title, style: theme.textTheme.displaySmall),
          const SizedBox(height: 8),
          Text('Organised by ${current.organizer}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          _infoTile(theme, LucideIcons.calendar, 'When',
              DateFormat('EEEE, MMMM dd yyyy • h:mm a').format(current.date)),
          _infoTile(theme, LucideIcons.mapPin, 'Where', current.venue),
          _infoTile(theme, LucideIcons.users, 'Attendance',
              '${current.goingCount} going • ${spotsLeft > 0 ? '$spotsLeft spots left' : 'Waitlist only'}'),
          const SizedBox(height: 24),
          Text('About this event', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(current.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text('What to bring', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          ...[
            'Your CU student ID card',
            'A laptop if the session is hands-on',
            'Reach the venue 15 minutes early',
          ].map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.checkCircle2,
                      size: 16, color: theme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(item, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(current.fee, style: theme.textTheme.titleMedium),
                    Text('${current.goingCount} attending',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final joined = campus.toggleEventJoin(current.id);
                    showAppSnackBar(
                      context,
                      joined
                          ? 'You are registered for ${current.title}'
                          : 'Registration cancelled',
                      icon: joined
                          ? LucideIcons.partyPopper
                          : LucideIcons.x,
                    );
                  },
                  icon: Icon(
                      isJoined ? LucideIcons.checkCircle2 : LucideIcons.ticket,
                      size: 18),
                  label: Text(isJoined ? 'You are going' : 'Register'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isJoined
                        ? theme.primaryColor.withValues(alpha: 0.15)
                        : theme.primaryColor,
                    foregroundColor:
                        isJoined ? theme.primaryColor : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'Technical':
        return LucideIcons.code;
      case 'Sports':
        return LucideIcons.trophy;
      case 'Cultural':
        return LucideIcons.partyPopper;
      default:
        return LucideIcons.bookOpen;
    }
  }

  Widget _infoTile(
      ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: theme.primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

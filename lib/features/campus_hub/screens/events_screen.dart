import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/campus_provider.dart';
import 'package:intl/intl.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campusProvider = context.watch<CampusProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Campus Events', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
      ),
      body: campusProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: campusProvider.events.length,
              itemBuilder: (context, index) {
                final event = campusProvider.events[index];
                return _buildEventCard(event, theme, context);
              },
            ),
    );
  }

  Widget _buildEventCard(event, ThemeData theme, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  event.category,
                  style: TextStyle(color: theme.primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.bookmark, color: theme.textTheme.bodySmall?.color, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(event.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            event.description,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(LucideIcons.calendar, size: 16, color: theme.primaryColor),
              const SizedBox(width: 8),
              Text(DateFormat('MMM dd, yyyy').format(event.date), style: theme.textTheme.bodySmall),
              const SizedBox(width: 16),
              Icon(LucideIcons.mapPin, size: 16, color: theme.primaryColor),
              const SizedBox(width: 8),
              Expanded(child: Text(event.venue, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Registered for Event!')),
                );
              },
              child: const Text('Join Event'),
            ),
          ),
        ],
      ),
    );
  }
}

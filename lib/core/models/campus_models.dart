import 'user_model.dart';

class Event {
  final String id;
  final String title;
  final String description;
  final String category;
  final String organizer;
  final DateTime date;
  final String venue;
  final int maxParticipants;
  final List<String> participantIds;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.organizer,
    required this.date,
    required this.venue,
    required this.maxParticipants,
    this.participantIds = const [],
  });
}

class Community {
  final String id;
  final String name;
  final String description;
  final bool isDepartment;
  final int memberCount;

  Community({
    required this.id,
    required this.name,
    required this.description,
    required this.isDepartment,
    this.memberCount = 0,
  });
}

class Poll {
  final String id;
  final String question;
  final List<PollOption> options;
  final String authorId;
  final bool hasVoted;

  Poll({
    required this.id,
    required this.question,
    required this.options,
    required this.authorId,
    this.hasVoted = false,
  });
}

class PollOption {
  final String id;
  final String text;
  final int votes;

  PollOption({
    required this.id,
    required this.text,
    this.votes = 0,
  });
}

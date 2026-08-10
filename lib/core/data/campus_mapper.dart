import '../models/campus_models.dart';

/// Translates the Campus Hub tables into the models the screens already speak.
///
/// The denormalised counters (`going_count`, `member_count`, `vote_count`,
/// `applicant_count`) are read as-is: they are maintained by triggers, and
/// counting rows per card would be the most expensive query in the app.
class CampusMapper {
  const CampusMapper._();

  /// Columns per table, listed rather than `*`, so adding a column cannot
  /// silently change what every Hub open downloads.
  static const eventColumns = '''
    id, title, description, category, cover_url, organizer_name, organizer_id,
    starts_at, ends_at, venue, max_participants, going_count,
    fee_amount, fee_currency, conversation_id
  ''';

  static const communityColumns = '''
    id, conversation_id, name, description, cover_url,
    is_department, is_auto_join
  ''';

  static const clubColumns = '''
    id, conversation_id, name, category, description, meeting_schedule,
    logo_url, lead_name, requires_approval
  ''';

  static const studyGroupColumns = '''
    id, conversation_id, subject, title, description, schedule, venue,
    host_id, max_members, is_open
  ''';

  static const projectColumns = '''
    id, conversation_id, title, description, stage, tech_stack, roles_needed,
    owner_id, owner_name, team_size, applicant_count, cover_url
  ''';

  static const pollColumns = '''
    id, question, author_id, author_name, allow_multiple, total_votes,
    closes_at, created_at
  ''';

  static const notificationColumns = '''
    id, kind, title, body, actor_id, target_type, target_id,
    deep_link, read_at, created_at
  ''';

  // ----------------------------------------------------------------- events

  static Event eventFromRow(Map<String, dynamic> row) {
    return Event(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      category: row['category'] as String? ?? 'Technical',
      organizer: row['organizer_name'] as String? ?? 'Campus Connect',
      date: parseDate(row['starts_at']) ?? DateTime.now(),
      venue: row['venue'] as String? ?? '',
      // `max_participants` is nullable — an uncapped event still needs a
      // number for "spots left", and going_count keeps that honest.
      maxParticipants: _int(row['max_participants'], fallback: 0),
      goingCount: _int(row['going_count']),
      fee: formatFee(row['fee_amount'], row['fee_currency'] as String?),
      coverUrl: row['cover_url'] as String? ?? '',
      conversationId: row['conversation_id'] as String?,
    );
  }

  /// `fee_amount numeric(10,2)` arrives as a String from PostgREST, because
  /// JSON has no exact decimal type.
  static String formatFee(Object? amount, String? currency) {
    final value = _double(amount);
    if (value <= 0) return 'Free';
    final symbol = (currency ?? 'INR') == 'INR' ? '₹' : '${currency ?? ''} ';
    final rounded = value.roundToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '$symbol$rounded';
  }

  // ------------------------------------------------------------ communities

  static Community communityFromRow(Map<String, dynamic> row) {
    return Community(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String?,
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      isDepartment: row['is_department'] as bool? ?? false,
      isAutoJoin: row['is_auto_join'] as bool? ?? false,
      memberCount: _memberCount(row),
      coverUrl: row['cover_url'] as String? ?? '',
    );
  }

  static Club clubFromRow(Map<String, dynamic> row) {
    return Club(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String?,
      name: row['name'] as String? ?? '',
      category: row['category'] as String? ?? 'Technical',
      description: row['description'] as String? ?? '',
      meetingSchedule: row['meeting_schedule'] as String? ?? 'To be announced',
      lead: row['lead_name'] as String? ?? 'Not assigned',
      memberCount: _memberCount(row),
      logoUrl: row['logo_url'] as String? ?? '',
      requiresApproval: row['requires_approval'] as bool? ?? false,
    );
  }

  static StudyGroup studyGroupFromRow(Map<String, dynamic> row) {
    return StudyGroup(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String?,
      subject: row['subject'] as String? ?? '',
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      schedule: row['schedule'] as String? ?? 'To be decided',
      venue: row['venue'] as String? ?? 'To be decided',
      hostId: row['host_id'] as String? ?? '',
      hostName: _embeddedName(row['profiles']) ?? 'A student',
      memberCount: _memberCount(row),
      maxMembers: _int(row['max_members'], fallback: 8),
      isOpen: row['is_open'] as bool? ?? true,
    );
  }

  static Project projectFromRow(Map<String, dynamic> row) {
    return Project(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String?,
      title: row['title'] as String? ?? '',
      description: row['description'] as String? ?? '',
      // The DB constraint is lower case ('idea', 'building'); the cards show
      // it capitalised, and the create sheet offers capitalised labels.
      stage: stageLabel(row['stage'] as String?),
      techStack: _stringList(row['tech_stack']),
      rolesNeeded: _stringList(row['roles_needed']),
      ownerId: row['owner_id'] as String? ?? '',
      ownerName: row['owner_name'] as String? ?? 'A student',
      teamSize: _int(row['team_size'], fallback: 1),
      applicantCount: _int(row['applicant_count']),
      coverUrl: row['cover_url'] as String? ?? '',
    );
  }

  /// `projects.stage` only accepts these values, so a label the create sheet
  /// offers has to be folded onto one of them.
  static String stageWire(String label) {
    switch (label.toLowerCase()) {
      case 'idea':
        return 'idea';
      case 'prototype':
      case 'planning':
        return 'planning';
      case 'building':
        return 'building';
      case 'testing':
        return 'testing';
      case 'launched':
        return 'launched';
      case 'archived':
        return 'archived';
      default:
        return 'idea';
    }
  }

  static String stageLabel(String? wire) {
    switch (wire) {
      case 'planning':
        return 'Prototype';
      case 'building':
        return 'Building';
      case 'testing':
        return 'Testing';
      case 'launched':
        return 'Launched';
      case 'archived':
        return 'Archived';
      default:
        return 'Idea';
    }
  }

  // ------------------------------------------------------------------ polls

  /// [votedOptionIds] comes from this student's own `poll_votes` rows — the
  /// only ballots RLS lets them read, which is what makes an anonymous poll
  /// actually anonymous.
  static Poll pollFromRow(
    Map<String, dynamic> row, {
    Set<String> votedOptionIds = const {},
  }) {
    final rawOptions = row['poll_options'];
    final options = <PollOption>[];
    if (rawOptions is List) {
      final sorted = rawOptions.whereType<Map>().toList()
        ..sort((a, b) => _int(a['position']).compareTo(_int(b['position'])));
      for (final option in sorted) {
        options.add(PollOption(
          id: option['id'] as String,
          text: option['text'] as String? ?? '',
          votes: _int(option['vote_count']),
        ));
      }
    }

    final mine = options.firstWhere(
      (o) => votedOptionIds.contains(o.id),
      orElse: () => PollOption(id: '', text: ''),
    );

    return Poll(
      id: row['id'] as String,
      question: row['question'] as String? ?? '',
      options: options,
      authorId: row['author_id'] as String? ?? '',
      authorName: row['author_name'] as String? ?? 'A student',
      createdAt: parseDate(row['created_at']),
      hasVoted: mine.id.isNotEmpty,
      votedOptionId: mine.id.isEmpty ? null : mine.id,
      closesAt: parseDate(row['closes_at']),
      allowMultiple: row['allow_multiple'] as bool? ?? false,
    );
  }

  // ---------------------------------------------------------- notifications

  static CampusNotification notificationFromRow(Map<String, dynamic> row) {
    return CampusNotification(
      id: row['id'] as String,
      type: CampusNotificationTypeWire.parse(row['kind']),
      title: row['title'] as String? ?? '',
      body: row['body'] as String? ?? '',
      timestamp: parseDate(row['created_at']) ?? DateTime.now(),
      isRead: row['read_at'] != null,
      deepLink: row['deep_link'] as String? ?? '',
      actorId: row['actor_id'] as String?,
      targetType: row['target_type'] as String?,
      targetId: row['target_id'] as String?,
    );
  }

  // --------------------------------------------------------------- helpers

  /// Every joinable entity keeps its member count on the conversation, because
  /// `conversation_members` is the membership table (see `0005_campus_hub.sql`).
  static int _memberCount(Map<String, dynamic> row) {
    final conversation = row['conversations'];
    if (conversation is Map) return _int(conversation['member_count']);
    if (conversation is List && conversation.isNotEmpty) {
      final first = conversation.first;
      if (first is Map) return _int(first['member_count']);
    }
    return 0;
  }

  static String? _embeddedName(Object? value) {
    if (value is Map) return value['full_name'] as String?;
    if (value is List && value.isNotEmpty && value.first is Map) {
      return (value.first as Map)['full_name'] as String?;
    }
    return null;
  }

  static List<String> _stringList(Object? value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    if (value is DateTime) return value.toLocal();
    return null;
  }
}

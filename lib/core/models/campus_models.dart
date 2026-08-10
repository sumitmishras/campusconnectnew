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
  final int goingCount;

  /// Display string ('Free' or '₹200'), formatted from `fee_amount` /
  /// `fee_currency` when the row is mapped.
  final String fee;

  /// Object in the public `campus-assets` bucket, if the organiser set one.
  final String coverUrl;

  /// Big events get a discussion thread; small ones do not.
  final String? conversationId;

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
    this.goingCount = 0,
    this.fee = 'Free',
    this.coverUrl = '',
    this.conversationId,
  });

  bool get isPast => date.isBefore(DateTime.now());

  int get daysAway => date.difference(DateTime.now()).inDays;

  Event copyWith({
    int? goingCount,
    List<String>? participantIds,
    String? coverUrl,
  }) {
    return Event(
      id: id,
      title: title,
      description: description,
      category: category,
      organizer: organizer,
      date: date,
      venue: venue,
      maxParticipants: maxParticipants,
      participantIds: participantIds ?? this.participantIds,
      goingCount: goingCount ?? this.goingCount,
      fee: fee,
      coverUrl: coverUrl ?? this.coverUrl,
      conversationId: conversationId,
    );
  }
}

class Community {
  final String id;
  final String name;
  final String description;
  final bool isDepartment;
  final int memberCount;

  /// The thread this community's membership *is* — joining the community and
  /// appearing in its chat are one INSERT into `conversation_members`.
  final String conversationId;

  /// Department hubs are joined automatically and cannot be left by hand.
  final bool isAutoJoin;

  final String coverUrl;

  Community({
    required this.id,
    required this.name,
    required this.description,
    required this.isDepartment,
    this.memberCount = 0,
    String? conversationId,
    this.isAutoJoin = false,
    this.coverUrl = '',
  }) : conversationId = conversationId ?? id;

  Community copyWith({int? memberCount}) => Community(
        id: id,
        name: name,
        description: description,
        isDepartment: isDepartment,
        memberCount: memberCount ?? this.memberCount,
        conversationId: conversationId,
        isAutoJoin: isAutoJoin,
        coverUrl: coverUrl,
      );
}

class Club {
  final String id;
  final String name;
  final String category;
  final String description;
  final String meetingSchedule;
  final String lead;
  final int memberCount;
  final String conversationId;
  final String logoUrl;
  final bool requiresApproval;

  Club({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.meetingSchedule,
    required this.lead,
    this.memberCount = 0,
    String? conversationId,
    this.logoUrl = '',
    this.requiresApproval = false,
  }) : conversationId = conversationId ?? id;

  Club copyWith({int? memberCount}) => Club(
        id: id,
        name: name,
        category: category,
        description: description,
        meetingSchedule: meetingSchedule,
        lead: lead,
        memberCount: memberCount ?? this.memberCount,
        conversationId: conversationId,
        logoUrl: logoUrl,
        requiresApproval: requiresApproval,
      );
}

class StudyGroup {
  final String id;
  final String subject;
  final String title;
  final String description;
  final String schedule;
  final String venue;
  final String hostId;
  final String hostName;
  final int memberCount;
  final int maxMembers;
  final String conversationId;

  /// `false` once the group fills up — maintained by
  /// `tg_study_group_capacity`, so the cap lives in one place.
  final bool isOpen;

  StudyGroup({
    required this.id,
    required this.subject,
    required this.title,
    required this.description,
    required this.schedule,
    required this.venue,
    required this.hostId,
    required this.hostName,
    this.memberCount = 1,
    this.maxMembers = 8,
    String? conversationId,
    this.isOpen = true,
  }) : conversationId = conversationId ?? id;

  bool get isFull => memberCount >= maxMembers || !isOpen;

  StudyGroup copyWith({int? memberCount, bool? isOpen}) => StudyGroup(
        id: id,
        subject: subject,
        title: title,
        description: description,
        schedule: schedule,
        venue: venue,
        hostId: hostId,
        hostName: hostName,
        memberCount: memberCount ?? this.memberCount,
        maxMembers: maxMembers,
        conversationId: conversationId,
        isOpen: isOpen ?? this.isOpen,
      );
}

class Project {
  final String id;
  final String title;
  final String description;
  final String stage;
  final List<String> techStack;
  final List<String> rolesNeeded;
  final String ownerId;
  final String ownerName;
  final int teamSize;
  final int applicantCount;

  /// Object in the public `campus-assets` bucket.
  final String coverUrl;

  final String? conversationId;

  Project({
    required this.id,
    required this.title,
    required this.description,
    required this.stage,
    required this.techStack,
    required this.rolesNeeded,
    required this.ownerId,
    required this.ownerName,
    this.teamSize = 1,
    this.applicantCount = 0,
    this.coverUrl = '',
    this.conversationId,
  });

  Project copyWith({int? applicantCount, String? coverUrl}) => Project(
        id: id,
        title: title,
        description: description,
        stage: stage,
        techStack: techStack,
        rolesNeeded: rolesNeeded,
        ownerId: ownerId,
        ownerName: ownerName,
        teamSize: teamSize,
        applicantCount: applicantCount ?? this.applicantCount,
        coverUrl: coverUrl ?? this.coverUrl,
        conversationId: conversationId,
      );
}

class Poll {
  final String id;
  final String question;
  final List<PollOption> options;
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final bool hasVoted;
  final String? votedOptionId;
  final DateTime? closesAt;
  final bool allowMultiple;

  Poll({
    required this.id,
    required this.question,
    required this.options,
    required this.authorId,
    this.authorName = 'A student',
    DateTime? createdAt,
    this.hasVoted = false,
    this.votedOptionId,
    this.closesAt,
    this.allowMultiple = false,
  }) : createdAt = createdAt ?? DateTime.now();

  int get totalVotes => options.fold(0, (sum, o) => sum + o.votes);

  bool get isClosed => closesAt != null && closesAt!.isBefore(DateTime.now());

  Poll copyWith({
    List<PollOption>? options,
    bool? hasVoted,
    String? votedOptionId,
  }) {
    return Poll(
      id: id,
      question: question,
      options: options ?? this.options,
      authorId: authorId,
      authorName: authorName,
      createdAt: createdAt,
      hasVoted: hasVoted ?? this.hasVoted,
      votedOptionId: votedOptionId ?? this.votedOptionId,
      closesAt: closesAt,
      allowMultiple: allowMultiple,
    );
  }
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

/// Mirrors `public.notification_kind`.
enum CampusNotificationType {
  connection,
  message,
  event,
  poll,
  club,
  project,
  system,
}

extension CampusNotificationTypeWire on CampusNotificationType {
  static const _names = {
    CampusNotificationType.connection: 'connection',
    CampusNotificationType.message: 'message',
    CampusNotificationType.event: 'event',
    CampusNotificationType.poll: 'poll',
    CampusNotificationType.club: 'club',
    CampusNotificationType.project: 'project',
    CampusNotificationType.system: 'system',
  };

  String get wire => _names[this]!;

  static CampusNotificationType parse(Object? value) {
    if (value is CampusNotificationType) return value;
    if (value is String) {
      for (final entry in _names.entries) {
        if (entry.value == value) return entry.key;
      }
    }
    return CampusNotificationType.system;
  }
}

class CampusNotification {
  final String id;
  final CampusNotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;

  /// Route the app follows when the row is tapped, e.g. `/chat/<uuid>`.
  final String deepLink;
  final String? actorId;
  final String? targetType;
  final String? targetId;

  CampusNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.deepLink = '',
    this.actorId,
    this.targetType,
    this.targetId,
  });

  CampusNotification copyWith({bool? isRead}) => CampusNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
        deepLink: deepLink,
        actorId: actorId,
        targetType: targetType,
        targetId: targetId,
      );
}

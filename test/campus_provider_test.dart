import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/core/data/repositories/campus_repository.dart';
import 'package:campus_connect/core/models/campus_models.dart';
import 'package:campus_connect/core/providers/campus_provider.dart';

/// Records the writes and can be told to fail one, so the rollback path is
/// tested rather than assumed.
class _FakeCampusRepository implements CampusRepository {
  _FakeCampusRepository({required this.snapshot});

  CampusSnapshot snapshot;

  final _changes = StreamController<CampusChange>.broadcast();
  final List<String> calls = [];

  /// Actions that should throw. Keyed by the string recorded in [calls].
  final Set<String> failing = {};

  int fetchAllCount = 0;
  bool closed = false;

  Future<void> _record(String call) async {
    calls.add(call);
    if (failing.contains(call)) throw CampusFailure('$call refused');
  }

  @override
  Future<CampusSnapshot> fetchAll() async {
    fetchAllCount++;
    return snapshot;
  }

  @override
  Future<List<Event>> fetchEvents({int limit = 100}) async {
    calls.add('fetchEvents');
    return snapshot.events;
  }

  @override
  Future<List<Poll>> fetchPolls({int limit = 50}) async {
    calls.add('fetchPolls');
    return snapshot.polls;
  }

  @override
  Future<List<CampusNotification>> fetchNotifications({int limit = 50}) async {
    calls.add('fetchNotifications');
    return snapshot.notifications;
  }

  @override
  Future<void> setEventRsvp({required String eventId, required bool going}) =>
      _record('rsvp:$eventId:$going');

  @override
  Future<void> setEventSaved({required String eventId, required bool saved}) =>
      _record('save:$eventId:$saved');

  @override
  Future<void> joinConversation(String conversationId) =>
      _record('join:$conversationId');

  @override
  Future<void> leaveConversation(String conversationId) =>
      _record('leave:$conversationId');

  @override
  Future<StudyGroup> createStudyGroup({
    required String subject,
    required String title,
    required String description,
    required String schedule,
    required String venue,
    required String hostName,
    int maxMembers = 8,
  }) async {
    await _record('createStudyGroup:$title');
    return StudyGroup(
      id: 'sg-new',
      conversationId: 'conv-sg-new',
      subject: subject,
      title: title,
      description: description,
      schedule: schedule,
      venue: venue,
      hostId: 'me',
      hostName: hostName,
      maxMembers: maxMembers,
    );
  }

  @override
  Future<void> setProjectApplication({
    required String projectId,
    required bool applied,
  }) =>
      _record('apply:$projectId:$applied');

  @override
  Future<Project> createProject({
    required String title,
    required String description,
    required String stage,
    required List<String> techStack,
    required List<String> rolesNeeded,
    required String ownerName,
    Uint8List? coverBytes,
    String coverFileName = 'cover.jpg',
  }) async {
    await _record('createProject:$title');
    return Project(
      id: 'p-new',
      title: title,
      description: description,
      stage: stage,
      techStack: techStack,
      rolesNeeded: rolesNeeded,
      ownerId: 'me',
      ownerName: ownerName,
    );
  }

  @override
  Future<void> votePoll({required String pollId, required String optionId}) =>
      _record('vote:$pollId:$optionId');

  @override
  Future<Poll> createPoll({
    required String question,
    required List<String> options,
    required String authorName,
  }) async {
    await _record('createPoll:$question');
    return Poll(
      id: 'poll-new',
      question: question,
      authorId: 'me',
      authorName: authorName,
      options: [
        for (var i = 0; i < options.length; i++)
          PollOption(id: 'o$i', text: options[i]),
      ],
    );
  }

  @override
  Future<void> markNotificationRead(String id) => _record('read:$id');

  @override
  Future<void> markAllNotificationsRead() => _record('readAll');

  @override
  Future<void> clearNotifications() => _record('clear');

  @override
  Stream<CampusChange> changes() => _changes.stream;

  @override
  Future<void> close() async {
    closed = true;
    await _changes.close();
  }

  void push(CampusChange change) => _changes.add(change);
}

void main() {
  late _FakeCampusRepository repo;
  late CampusProvider provider;

  CampusSnapshot buildSnapshot() => CampusSnapshot(
        events: [
          Event(
            id: 'e1',
            title: 'TechnoVate 2026 Hackathon',
            description: '36 hours of building',
            category: 'Technical',
            organizer: 'CodeChef CU Chapter',
            date: DateTime.now().add(const Duration(days: 3)),
            venue: 'Block 6, Auditorium',
            maxParticipants: 200,
            goingCount: 40,
          ),
          Event(
            id: 'e2',
            title: 'Inter-Department Football Cup',
            description: 'Eight departments, one trophy',
            category: 'Sports',
            organizer: 'Sports Council',
            date: DateTime.now().add(const Duration(days: 9)),
            venue: 'Ground',
            maxParticipants: 100,
            goingCount: 12,
          ),
        ],
        communities: [
          Community(
            id: 'c1',
            conversationId: 'conv-c1',
            name: 'Computer Science Hub',
            description: 'Notes and notices',
            isDepartment: true,
            memberCount: 300,
          ),
        ],
        clubs: [
          Club(
            id: 'cl1',
            conversationId: 'conv-cl1',
            name: 'CodeChef CU Chapter',
            category: 'Technical',
            description: 'Weekly contests',
            meetingSchedule: 'Sat 5pm',
            lead: 'Riya Sharma',
            memberCount: 40,
          ),
        ],
        studyGroups: [
          StudyGroup(
            id: 'sg1',
            conversationId: 'conv-sg1',
            subject: 'DBMS',
            title: 'DBMS Doubt Circle',
            description: 'Normalisation',
            schedule: 'Tue & Thu',
            venue: 'Block 6',
            hostId: 'riya',
            hostName: 'Riya Sharma',
            memberCount: 4,
            maxMembers: 8,
          ),
        ],
        projects: [
          Project(
            id: 'pr1',
            title: 'Campus Lost & Found App',
            description: 'Post and claim lost items',
            stage: 'Building',
            techStack: const ['Flutter'],
            rolesNeeded: const ['UI Designer'],
            ownerId: 'kabir',
            ownerName: 'Kabir Singh',
            applicantCount: 3,
          ),
        ],
        polls: [
          Poll(
            id: 'po1',
            question: 'Which mess serves the best dinner?',
            authorId: 'riya',
            options: [
              PollOption(id: 'o1', text: 'Block 1 Mess', votes: 10),
              PollOption(id: 'o2', text: 'Food Court', votes: 6),
            ],
          ),
        ],
        notifications: [
          CampusNotification(
            id: 'n1',
            type: CampusNotificationType.connection,
            title: 'New connection request',
            body: 'Riya wants to connect',
            timestamp: DateTime.now(),
          ),
          CampusNotification(
            id: 'n2',
            type: CampusNotificationType.event,
            title: 'Event reminder',
            body: 'Starts tomorrow',
            timestamp: DateTime.now(),
            isRead: true,
          ),
        ],
        joinedConversationIds: const {'conv-c1'},
      );

  setUp(() {
    repo = _FakeCampusRepository(snapshot: buildSnapshot());
    provider = CampusProvider(repository: repo);
  });

  tearDown(() => provider.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('loading', () {
    test('every list comes from the repository', () async {
      await settle();

      expect(repo.fetchAllCount, 1);
      expect(provider.isLoading, isFalse);
      expect(provider.events, hasLength(2));
      expect(provider.communities, hasLength(1));
      expect(provider.clubs, hasLength(1));
      expect(provider.studyGroups, hasLength(1));
      expect(provider.projects, hasLength(1));
      expect(provider.polls, hasLength(1));
      expect(provider.notifications, hasLength(2));
      expect(provider.unreadNotificationCount, 1);
    });

    test('membership is resolved through the conversation, not the entity id',
        () async {
      await settle();

      expect(provider.isCommunityJoined('c1'), isTrue);
      expect(provider.isClubJoined('cl1'), isFalse);
      expect(provider.isStudyGroupJoined('sg1'), isFalse);
      expect(provider.joinedCommunities.single.id, 'c1');
    });

    test('the category filter narrows events without refetching', () async {
      await settle();
      provider.setEventCategory('Sports');

      expect(provider.events.single.title, 'Inter-Department Football Cup');
      expect(repo.fetchAllCount, 1);
    });
  });

  group('events', () {
    test('RSVP flips the card, adjusts the count and writes through', () async {
      await settle();
      expect(provider.toggleEventJoin('e1'), isTrue);

      expect(provider.isEventJoined('e1'), isTrue);
      expect(provider.eventById('e1')!.goingCount, 41);
      expect(provider.joinedEvents.single.id, 'e1');

      await settle();
      expect(repo.calls, contains('rsvp:e1:true'));
    });

    test('a refused RSVP rolls the card back and explains why', () async {
      await settle();
      repo.failing.add('rsvp:e1:true');

      provider.toggleEventJoin('e1');
      await settle();

      expect(provider.isEventJoined('e1'), isFalse);
      expect(provider.eventById('e1')!.goingCount, 40);
      expect(provider.lastActionError, contains('refused'));
    });

    test('saving an event writes a bookmark', () async {
      await settle();
      expect(provider.toggleEventSaved('e2'), isTrue);
      await settle();

      expect(provider.savedEvents.single.id, 'e2');
      expect(repo.calls, contains('save:e2:true'));
    });
  });

  group('membership', () {
    test('joining a club joins its conversation', () async {
      await settle();
      expect(provider.toggleClubJoin('cl1'), isTrue);

      expect(provider.isClubJoined('cl1'), isTrue);
      expect(provider.clubs.single.memberCount, 41);

      await settle();
      expect(repo.calls, contains('join:conv-cl1'));
    });

    test('leaving a community leaves its conversation', () async {
      await settle();
      expect(provider.toggleCommunityJoin('c1'), isFalse);

      expect(provider.isCommunityJoined('c1'), isFalse);
      expect(provider.communities.single.memberCount, 299);

      await settle();
      expect(repo.calls, contains('leave:conv-c1'));
    });

    test('a refused join puts the button back', () async {
      await settle();
      repo.failing.add('join:conv-sg1');

      provider.toggleStudyGroupJoin('sg1');
      await settle();

      expect(provider.isStudyGroupJoined('sg1'), isFalse);
      expect(provider.studyGroups.single.memberCount, 4);
      expect(provider.lastActionError, contains('refused'));
    });

    test('creating a study group returns its ids and joins the host', () async {
      await settle();
      final created = await provider.createStudyGroup(
        subject: 'OS',
        title: 'OS Concepts Crew',
        description: 'Scheduling and deadlocks',
        schedule: 'Wed & Sat',
        venue: 'Block 3',
        hostName: 'Sumit Mishra',
      );

      expect(created, isNotNull);
      expect(created!.conversationId, 'conv-sg-new');
      expect(provider.studyGroups.first.id, 'sg-new');
      expect(provider.isStudyGroupJoined('sg-new'), isTrue);
    });

    test('a refused creation returns null with a message', () async {
      await settle();
      repo.failing.add('createStudyGroup:Too many');

      final created = await provider.createStudyGroup(
        subject: 'OS',
        title: 'Too many',
        description: '',
        schedule: '',
        venue: '',
        hostName: 'Sumit Mishra',
      );

      expect(created, isNull);
      expect(provider.lastActionError, contains('refused'));
      expect(provider.studyGroups, hasLength(1));
    });
  });

  group('projects and polls', () {
    test('applying bumps the applicant count and writes through', () async {
      await settle();
      expect(provider.toggleProjectApplication('pr1'), isTrue);

      expect(provider.hasAppliedToProject('pr1'), isTrue);
      expect(provider.projects.single.applicantCount, 4);

      await settle();
      expect(repo.calls, contains('apply:pr1:true'));
    });

    test('withdrawing is a state change, not a second application', () async {
      await settle();
      provider.toggleProjectApplication('pr1');
      await settle();
      expect(provider.toggleProjectApplication('pr1'), isFalse);
      await settle();

      expect(provider.hasAppliedToProject('pr1'), isFalse);
      expect(provider.projects.single.applicantCount, 3);
      expect(repo.calls, contains('apply:pr1:false'));
    });

    test('voting locks the poll and records the option', () async {
      await settle();
      provider.votePoll('po1', 'o1');
      await settle();

      final poll = provider.polls.single;
      expect(poll.hasVoted, isTrue);
      expect(poll.votedOptionId, 'o1');
      expect(poll.options.first.votes, 11);
      expect(repo.calls, contains('vote:po1:o1'));
    });

    test('a second vote on a locked poll is ignored', () async {
      await settle();
      provider.votePoll('po1', 'o1');
      await settle();
      repo.calls.clear();

      provider.votePoll('po1', 'o2');
      await settle();

      expect(provider.polls.single.votedOptionId, 'o1');
      expect(repo.calls, isEmpty);
    });

    test('a refused vote rolls the tally back', () async {
      await settle();
      repo.failing.add('vote:po1:o2');

      provider.votePoll('po1', 'o2');
      await settle();

      final poll = provider.polls.single;
      expect(poll.hasVoted, isFalse);
      expect(poll.options.last.votes, 6);
      expect(provider.lastActionError, contains('refused'));
    });

    test('creating a poll puts it at the top of the feed', () async {
      await settle();
      final ok = await provider.createPoll(
        question: 'Best study spot?',
        options: const ['Library', 'Block 6'],
        authorName: 'Sumit Mishra',
      );

      expect(ok, isTrue);
      expect(provider.polls.first.question, 'Best study spot?');
      expect(provider.polls.first.options, hasLength(2));
    });
  });

  group('notifications', () {
    test('marking one read writes only read_at', () async {
      await settle();
      provider.markNotificationRead('n1');
      await settle();

      expect(provider.unreadNotificationCount, 0);
      expect(repo.calls, contains('read:n1'));
    });

    test('clearing hides them all and calls the function', () async {
      await settle();
      provider.clearNotifications();
      await settle();

      expect(provider.notifications, isEmpty);
      expect(repo.calls, contains('clear'));
    });

    test('a refused clear brings them back', () async {
      await settle();
      repo.failing.add('clear');

      provider.clearNotifications();
      await settle();

      expect(provider.notifications, hasLength(2));
      expect(provider.lastActionError, contains('refused'));
    });
  });

  group('realtime', () {
    test('a notification event re-reads only notifications', () async {
      await settle();
      repo.calls.clear();

      repo.push(CampusChange.notifications);
      await settle();

      expect(repo.calls, contains('fetchNotifications'));
      expect(repo.calls, isNot(contains('fetchPolls')));
      expect(repo.fetchAllCount, 1);
    });

    test('a poll event re-reads the tallies', () async {
      await settle();
      repo.calls.clear();

      repo.push(CampusChange.polls);
      await settle();

      expect(repo.calls, contains('fetchPolls'));
    });

    test('an event change re-reads the events list', () async {
      await settle();
      repo.calls.clear();

      repo.push(CampusChange.events);
      await settle();

      expect(repo.calls, contains('fetchEvents'));
    });
  });

  test('disposing tears the repository down', () async {
    await settle();
    provider.dispose();
    await settle();
    expect(repo.closed, isTrue);

    provider = CampusProvider(
      repository: _FakeCampusRepository(snapshot: CampusSnapshot.empty),
    );
  });
}

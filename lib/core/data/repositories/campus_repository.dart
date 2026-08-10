import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/campus_models.dart';
import '../../services/realtime_status.dart';
import '../campus_mapper.dart';
import 'bookmark_repository.dart';
import 'storage_repository.dart';

/// Raised for anything the student should see a message about.
class CampusFailure implements Exception {
  final String message;
  const CampusFailure(this.message);
  @override
  String toString() => message;
}

/// Everything the Campus Hub renders, in one value.
///
/// Fetched together because the hub screen shows a count from every one of
/// them before the student taps anything, and because the "have I joined /
/// saved / applied" sets have to arrive with the lists — otherwise every card
/// renders its join button in the wrong state for a frame.
class CampusSnapshot {
  final List<Event> events;
  final List<Community> communities;
  final List<Club> clubs;
  final List<StudyGroup> studyGroups;
  final List<Project> projects;
  final List<Poll> polls;
  final List<CampusNotification> notifications;

  /// Threads this student is an active member of. Membership in a community,
  /// club, study group or project team *is* a `conversation_members` row, so
  /// this one set answers "have I joined" for all four.
  final Set<String> joinedConversationIds;

  final Set<String> goingEventIds;
  final Set<String> savedEventIds;
  final Set<String> appliedProjectIds;

  const CampusSnapshot({
    this.events = const [],
    this.communities = const [],
    this.clubs = const [],
    this.studyGroups = const [],
    this.projects = const [],
    this.polls = const [],
    this.notifications = const [],
    this.joinedConversationIds = const {},
    this.goingEventIds = const {},
    this.savedEventIds = const {},
    this.appliedProjectIds = const {},
  });

  static const empty = CampusSnapshot();
}

/// What changed, for the realtime subscription. The provider re-reads the part
/// that moved rather than trusting a replicated row it would have to map twice.
enum CampusChange { notifications, polls, events }

abstract class CampusRepository {
  Future<CampusSnapshot> fetchAll();

  /// RSVP. `going_count` is maintained by `tg_event_rsvp_counts`, so the caller
  /// should re-read or adjust its own copy.
  Future<void> setEventRsvp({required String eventId, required bool going});

  Future<void> setEventSaved({required String eventId, required bool saved});

  /// Covers communities, clubs, study groups and project teams — one pair of
  /// functions, because they share one membership table.
  Future<void> joinConversation(String conversationId);
  Future<void> leaveConversation(String conversationId);

  Future<StudyGroup> createStudyGroup({
    required String subject,
    required String title,
    required String description,
    required String schedule,
    required String venue,
    required String hostName,
    int maxMembers = 8,
  });

  Future<void> setProjectApplication({
    required String projectId,
    required bool applied,
  });

  Future<Project> createProject({
    required String title,
    required String description,
    required String stage,
    required List<String> techStack,
    required List<String> rolesNeeded,
    required String ownerName,
    Uint8List? coverBytes,
    String coverFileName = 'cover.jpg',
  });

  Future<void> votePoll({required String pollId, required String optionId});

  Future<Poll> createPoll({
    required String question,
    required List<String> options,
    required String authorName,
  });

  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();
  Future<void> clearNotifications();

  /// Fresh notifications for the bell, refreshed poll tallies, updated events.
  Stream<CampusChange> changes();

  Future<List<CampusNotification>> fetchNotifications({int limit = 50});
  Future<List<Poll>> fetchPolls({int limit = 50});
  Future<List<Event>> fetchEvents({int limit = 100});

  Future<void> close();
}

// =====================================================================
// Supabase
// =====================================================================

class SupabaseCampusRepository implements CampusRepository {
  SupabaseCampusRepository(this._client, this._storage, this._bookmarks);

  final SupabaseClient _client;
  final StorageRepository _storage;

  /// `bookmarks` is one polymorphic table with one owner; saved events go
  /// through it rather than being written from here.
  final BookmarkRepository _bookmarks;

  final _changes = StreamController<CampusChange>.broadcast();
  RealtimeChannel? _channel;

  /// Cached because every insert into a campus table needs it and it never
  /// changes for a given student.
  String? _universityId;

  String get _me => _client.auth.currentUser?.id ?? '';

  @override
  Future<CampusSnapshot> fetchAll() async {
    final me = _me;
    if (me.isEmpty) return CampusSnapshot.empty;

    // All eleven reads in parallel. Each one is a single indexed scan over one
    // campus's rows, and the hub screen needs a count from every table before
    // the student taps anything.
    final results = await Future.wait([
      _events(),
      _communities(),
      _clubs(),
      _studyGroups(),
      _projects(),
      _polls(),
      _notifications(limit: 50),
      _joinedConversationIds(me),
      _rsvps(me),
      _bookmarks.fetchIds(BookmarkTarget.event),
      _appliedProjectIds(me),
    ]);

    return CampusSnapshot(
      events: results[0] as List<Event>,
      communities: results[1] as List<Community>,
      clubs: results[2] as List<Club>,
      studyGroups: results[3] as List<StudyGroup>,
      projects: results[4] as List<Project>,
      polls: results[5] as List<Poll>,
      notifications: results[6] as List<CampusNotification>,
      joinedConversationIds: results[7] as Set<String>,
      goingEventIds: results[8] as Set<String>,
      savedEventIds: results[9] as Set<String>,
      appliedProjectIds: results[10] as Set<String>,
    );
  }

  // ------------------------------------------------------------------ reads

  @override
  Future<List<Event>> fetchEvents({int limit = 100}) => _events(limit: limit);

  Future<List<Event>> _events({int limit = 100}) async {
    // Soonest first, cancelled ones left out — matching events_upcoming_idx.
    final rows = await _client
        .from('events')
        .select(CampusMapper.eventColumns)
        .eq('is_cancelled', false)
        .order('starts_at')
        .limit(limit);
    return rows.map(CampusMapper.eventFromRow).toList();
  }

  Future<List<Community>> _communities({int limit = 100}) async {
    final rows = await _client
        .from('communities')
        .select('${CampusMapper.communityColumns}, conversations(member_count)')
        .order('is_department', ascending: false)
        .order('name')
        .limit(limit);
    return rows.map(CampusMapper.communityFromRow).toList();
  }

  Future<List<Club>> _clubs({int limit = 100}) async {
    final rows = await _client
        .from('clubs')
        .select('${CampusMapper.clubColumns}, conversations(member_count)')
        .order('name')
        .limit(limit);
    return rows.map(CampusMapper.clubFromRow).toList();
  }

  Future<List<StudyGroup>> _studyGroups({int limit = 100}) async {
    final rows = await _client
        .from('study_groups')
        .select('''
          ${CampusMapper.studyGroupColumns},
          conversations(member_count),
          profiles(full_name)
        ''')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(CampusMapper.studyGroupFromRow).toList();
  }

  Future<List<Project>> _projects({int limit = 100}) async {
    final rows = await _client
        .from('projects')
        .select(CampusMapper.projectColumns)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(CampusMapper.projectFromRow).toList();
  }

  @override
  Future<List<Poll>> fetchPolls({int limit = 50}) => _polls(limit: limit);

  Future<List<Poll>> _polls({int limit = 50}) async {
    final me = _me;

    // Campus-wide polls only: a thread-scoped poll belongs in that thread, and
    // the Polls screen is the campus feed.
    final results = await Future.wait([
      _client
          .from('polls')
          .select('${CampusMapper.pollColumns}, '
              'poll_options(id, position, text, vote_count)')
          .isFilter('conversation_id', null)
          .order('created_at', ascending: false)
          .limit(limit),
      if (me.isEmpty)
        Future.value(const <Map<String, dynamic>>[])
      else
        _client.from('poll_votes').select('poll_id, option_id').eq('user_id', me),
    ]);

    final votes = <String, Set<String>>{};
    for (final row in results[1]) {
      final poll = row['poll_id'] as String?;
      final option = row['option_id'] as String?;
      if (poll == null || option == null) continue;
      votes.putIfAbsent(poll, () => <String>{}).add(option);
    }

    return results[0]
        .map((row) => CampusMapper.pollFromRow(
              row,
              votedOptionIds: votes[row['id']] ?? const {},
            ))
        .toList();
  }

  @override
  Future<List<CampusNotification>> fetchNotifications({int limit = 50}) =>
      _notifications(limit: limit);

  Future<List<CampusNotification>> _notifications({int limit = 50}) async {
    final me = _me;
    if (me.isEmpty) return const [];

    // `id` is a v7 uuid, so ordering by it is ordering by time and
    // notifications_feed_idx alone serves this.
    final rows = await _client
        .from('notifications')
        .select(CampusMapper.notificationColumns)
        .eq('user_id', me)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(CampusMapper.notificationFromRow).toList();
  }

  Future<Set<String>> _joinedConversationIds(String me) async {
    final rows = await _client
        .from('conversation_members')
        .select('conversation_id')
        .eq('user_id', me)
        .isFilter('left_at', null);
    return rows.map((r) => r['conversation_id'] as String).toSet();
  }

  Future<Set<String>> _rsvps(String me) async {
    final rows = await _client
        .from('event_rsvps')
        .select('event_id, state')
        .eq('user_id', me)
        .eq('state', 'going');
    return rows.map((r) => r['event_id'] as String).toSet();
  }

  Future<Set<String>> _appliedProjectIds(String me) async {
    final rows = await _client
        .from('project_applications')
        .select('project_id, state')
        .eq('user_id', me)
        .eq('state', 'pending');
    return rows.map((r) => r['project_id'] as String).toSet();
  }

  Future<String> _universityIdOrThrow() async {
    final cached = _universityId;
    if (cached != null) return cached;

    final me = _me;
    if (me.isEmpty) throw const CampusFailure('Sign in again to continue.');

    final row = await _client
        .from('profiles')
        .select('university_id')
        .eq('id', me)
        .maybeSingle();

    final id = row?['university_id'] as String?;
    if (id == null) throw const CampusFailure('Your profile is incomplete.');
    return _universityId = id;
  }

  // ----------------------------------------------------------------- writes

  @override
  Future<void> setEventRsvp({
    required String eventId,
    required bool going,
  }) async {
    final me = _me;
    if (me.isEmpty) throw const CampusFailure('Sign in again to continue.');

    try {
      if (going) {
        await _client.from('event_rsvps').upsert({
          'event_id': eventId,
          'user_id': me,
          'state': 'going',
        });
      } else {
        await _client
            .from('event_rsvps')
            .delete()
            .eq('event_id', eventId)
            .eq('user_id', me);
      }
    } on PostgrestException catch (e) {
      throw CampusFailure(_readable(e));
    }
  }

  @override
  Future<void> setEventSaved({
    required String eventId,
    required bool saved,
  }) async {
    try {
      await _bookmarks.set(
        targetType: BookmarkTarget.event,
        targetId: eventId,
        saved: saved,
      );
    } on PostgrestException catch (e) {
      throw CampusFailure(_readable(e));
    }
  }

  @override
  Future<void> joinConversation(String conversationId) async {
    try {
      await _client
          .rpc('join_group', params: {'p_conversation_id': conversationId});
    } on PostgrestException catch (e) {
      // 23514 is the study-group capacity check.
      throw CampusFailure(
          e.code == '23514' ? 'This group is full.' : _readable(e));
    }
  }

  @override
  Future<void> leaveConversation(String conversationId) async {
    try {
      await _client
          .rpc('leave_group', params: {'p_conversation_id': conversationId});
    } on PostgrestException catch (e) {
      throw CampusFailure(_readable(e));
    }
  }

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
    try {
      // The group, its thread and the host's membership are created together —
      // `study_groups.conversation_id` is NOT NULL and the client cannot
      // insert a conversation, so this function is the only way in.
      final row = Map<String, dynamic>.from(
        await _client.rpc('create_study_group', params: {
          'p_subject': subject,
          'p_title': title,
          'p_description': description,
          'p_schedule': schedule,
          'p_venue': venue,
          'p_max_members': maxMembers,
        }) as Map,
      );

      return StudyGroup(
        id: row['id'] as String,
        conversationId: row['conversation_id'] as String?,
        subject: row['subject'] as String? ?? subject,
        title: row['title'] as String? ?? title,
        description: row['description'] as String? ?? description,
        schedule: row['schedule'] as String? ?? schedule,
        venue: row['venue'] as String? ?? venue,
        hostId: row['host_id'] as String? ?? _me,
        hostName: hostName,
        memberCount: 1,
        maxMembers: (row['max_members'] as int?) ?? maxMembers,
      );
    } on PostgrestException catch (e) {
      throw CampusFailure(e.code == '53400'
          ? 'You have created too many study groups today.'
          : _readable(e));
    }
  }

  @override
  Future<void> setProjectApplication({
    required String projectId,
    required bool applied,
  }) async {
    final me = _me;
    if (me.isEmpty) throw const CampusFailure('Sign in again to continue.');

    try {
      if (applied) {
        await _client.from('project_applications').insert({
          'project_id': projectId,
          'user_id': me,
          'state': 'pending',
        });
      } else {
        // DELETE has no policy on this table by design — withdrawing is a
        // state change, so the owner still sees that an application existed.
        await _client
            .from('project_applications')
            .update({'state': 'withdrawn', 'decided_at': _now()})
            .eq('project_id', projectId)
            .eq('user_id', me)
            .eq('state', 'pending');
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // Already applied.
      throw CampusFailure(_readable(e));
    }
  }

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
    final me = _me;
    if (me.isEmpty) throw const CampusFailure('Sign in again to continue.');
    final university = await _universityIdOrThrow();

    var coverUrl = '';
    if (coverBytes != null && coverBytes.isNotEmpty) {
      try {
        coverUrl = await _storage.uploadCampusAsset(
          bytes: coverBytes,
          fileName: coverFileName,
          folder: 'projects',
        );
      } on StorageFailure {
        // A cover that could not be uploaded is not worth losing the project
        // over; it posts without one.
      }
    }

    try {
      final row = await _client
          .from('projects')
          .insert({
            'university_id': university,
            'owner_id': me,
            'owner_name': ownerName,
            'title': title,
            'description': description,
            'stage': CampusMapper.stageWire(stage),
            'tech_stack': techStack,
            'roles_needed': rolesNeeded,
            if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
          })
          .select(CampusMapper.projectColumns)
          .single();

      return CampusMapper.projectFromRow(row);
    } on PostgrestException catch (e) {
      throw CampusFailure(_readable(e));
    }
  }

  @override
  Future<void> votePoll({
    required String pollId,
    required String optionId,
  }) async {
    final me = _me;
    if (me.isEmpty) throw const CampusFailure('Sign in again to continue.');

    try {
      // `tg_poll_single_choice` replaces any previous vote, so a re-vote on a
      // single-choice poll is an insert, not an update.
      await _client.from('poll_votes').insert({
        'poll_id': pollId,
        'option_id': optionId,
        'user_id': me,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // Same option, voted twice.
      throw CampusFailure(_readable(e));
    }
  }

  @override
  Future<Poll> createPoll({
    required String question,
    required List<String> options,
    required String authorName,
  }) async {
    try {
      // A poll with no options is not a poll, so the row and its options are
      // created in one function (0012) rather than two client inserts.
      final row = Map<String, dynamic>.from(
        await _client.rpc('create_poll', params: {
          'p_question': question,
          'p_options': options,
        }) as Map,
      );
      return CampusMapper.pollFromRow(row);
    } on PostgrestException catch (e) {
      throw CampusFailure(e.code == '53400'
          ? 'You have created too many polls today.'
          : _readable(e));
    }
  }

  @override
  Future<void> markNotificationRead(String id) async {
    final me = _me;
    if (me.isEmpty) return;
    try {
      // `read_at` is the only column the grants leave writable here.
      await _client
          .from('notifications')
          .update({'read_at': _now()})
          .eq('user_id', me)
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw CampusFailure(_readable(e));
    }
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final me = _me;
    if (me.isEmpty) return;
    try {
      await _client
          .from('notifications')
          .update({'read_at': _now()})
          .eq('user_id', me)
          .isFilter('read_at', null);
    } on PostgrestException catch (e) {
      throw CampusFailure(_readable(e));
    }
  }

  @override
  Future<void> clearNotifications() async {
    try {
      // DELETE is revoked on `notifications`, so clearing is a function (0012).
      await _client.rpc('clear_my_notifications');
    } on PostgrestException catch (e) {
      throw CampusFailure(_readable(e));
    }
  }

  // -------------------------------------------------------------- realtime

  @override
  Stream<CampusChange> changes() {
    _subscribe();
    return _changes.stream;
  }

  void _subscribe() {
    if (_channel != null) return;
    final me = _me;
    if (me.isEmpty) return;

    _channel = _client.channel('cc-campus')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        // notifications is hash partitioned on user_id and published via the
        // partition root, so this filter is what keeps the socket quiet.
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: me,
        ),
        callback: (_) => _emit(CampusChange.notifications),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'poll_options',
        callback: (_) => _emit(CampusChange.polls),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'polls',
        callback: (_) => _emit(CampusChange.polls),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'events',
        callback: (_) => _emit(CampusChange.events),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'events',
        callback: (_) => _emit(CampusChange.events),
      )
      // A re-join means the notifications, tallies and RSVPs that changed
      // while the socket was down were never delivered.
      ..subscribe(realtimeStatus('cc-campus', onRejoin: () {
        _emit(CampusChange.notifications);
        _emit(CampusChange.polls);
        _emit(CampusChange.events);
      }));
  }

  void _emit(CampusChange change) {
    if (_changes.isClosed) return;
    _changes.add(change);
  }

  @override
  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {
        // Already gone.
      }
    }
    await _changes.close();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static String _readable(PostgrestException e) {
    if (e.code == '42501') {
      return e.message.isEmpty
          ? 'You do not have access to that yet.'
          : e.message;
    }
    return e.message.isEmpty ? 'Something went wrong. Please try again.' : e.message;
  }
}

// =====================================================================
// Mock
// =====================================================================

/// Serves the Campus Hub from the generated fixtures, applying the same
/// semantics the Supabase implementation applies in SQL — capacity caps, single
/// -choice voting, "one live application per project".
///
/// The fixture snapshot is injected rather than reached for directly, so this
/// stays a repository and `MockDataGenerator` stays a fixture.
class MockCampusRepository implements CampusRepository {
  MockCampusRepository({
    required CampusSnapshot Function() seed,
    required String Function() newId,
    this.latency = const Duration(milliseconds: 600),
  })  : _seed = seed,
        _newId = newId;

  final CampusSnapshot Function() _seed;
  final String Function() _newId;
  final Duration latency;

  final _changes = StreamController<CampusChange>.broadcast();

  final List<Event> _events = [];
  final List<Community> _communities = [];
  final List<Club> _clubs = [];
  final List<StudyGroup> _studyGroups = [];
  final List<Project> _projects = [];
  final List<Poll> _polls = [];
  final List<CampusNotification> _notifications = [];
  final Set<String> _joined = {};
  final Set<String> _going = {};
  final Set<String> _saved = {};
  final Set<String> _applied = {};

  bool _seeded = false;

  /// Mutations are kept rather than discarded, so a pull-to-refresh in mock
  /// mode reads back what the student just did — the same thing a refresh
  /// against Postgres does.
  void _ensureSeeded() {
    if (_seeded) return;
    _seeded = true;
    final snapshot = _seed();
    _events.addAll(snapshot.events);
    _communities.addAll(snapshot.communities);
    _clubs.addAll(snapshot.clubs);
    _studyGroups.addAll(snapshot.studyGroups);
    _projects.addAll(snapshot.projects);
    _polls.addAll(snapshot.polls);
    _notifications.addAll(snapshot.notifications);
    _joined.addAll(snapshot.joinedConversationIds);
    _going.addAll(snapshot.goingEventIds);
    _saved.addAll(snapshot.savedEventIds);
    _applied.addAll(snapshot.appliedProjectIds);
  }

  @override
  Future<CampusSnapshot> fetchAll() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    _ensureSeeded();
    return CampusSnapshot(
      events: List.of(_events),
      communities: List.of(_communities),
      clubs: List.of(_clubs),
      studyGroups: List.of(_studyGroups),
      projects: List.of(_projects),
      polls: List.of(_polls),
      notifications: List.of(_notifications),
      joinedConversationIds: Set.of(_joined),
      goingEventIds: Set.of(_going),
      savedEventIds: Set.of(_saved),
      appliedProjectIds: Set.of(_applied),
    );
  }

  @override
  Future<List<Event>> fetchEvents({int limit = 100}) async {
    _ensureSeeded();
    return List.of(_events);
  }

  @override
  Future<List<Poll>> fetchPolls({int limit = 50}) async {
    _ensureSeeded();
    return List.of(_polls);
  }

  @override
  Future<List<CampusNotification>> fetchNotifications({int limit = 50}) async {
    _ensureSeeded();
    return List.of(_notifications);
  }

  @override
  Future<void> setEventRsvp({
    required String eventId,
    required bool going,
  }) async {
    _ensureSeeded();
    final index = _events.indexWhere((e) => e.id == eventId);
    if (index == -1) return;

    if (going ? !_going.add(eventId) : !_going.remove(eventId)) return;
    // Mirrors tg_event_rsvp_counts.
    _events[index] = _events[index]
        .copyWith(goingCount: _events[index].goingCount + (going ? 1 : -1));
  }

  @override
  Future<void> setEventSaved({
    required String eventId,
    required bool saved,
  }) async {
    _ensureSeeded();
    if (saved) {
      _saved.add(eventId);
    } else {
      _saved.remove(eventId);
    }
  }

  @override
  Future<void> joinConversation(String conversationId) async {
    _ensureSeeded();
    _joined.add(conversationId);
    _applyMemberDelta(conversationId, 1);
  }

  @override
  Future<void> leaveConversation(String conversationId) async {
    _ensureSeeded();
    if (_joined.remove(conversationId)) _applyMemberDelta(conversationId, -1);
  }

  /// The counter lives on the conversation server-side and is maintained by a
  /// trigger; here it is applied to whichever entity owns that thread.
  void _applyMemberDelta(String conversationId, int delta) {
    for (var i = 0; i < _communities.length; i++) {
      if (_communities[i].conversationId != conversationId) continue;
      _communities[i] = _communities[i]
          .copyWith(memberCount: _communities[i].memberCount + delta);
      return;
    }
    for (var i = 0; i < _clubs.length; i++) {
      if (_clubs[i].conversationId != conversationId) continue;
      _clubs[i] = _clubs[i].copyWith(memberCount: _clubs[i].memberCount + delta);
      return;
    }
    for (var i = 0; i < _studyGroups.length; i++) {
      if (_studyGroups[i].conversationId != conversationId) continue;
      final next = _studyGroups[i].memberCount + delta;
      _studyGroups[i] = _studyGroups[i].copyWith(
        memberCount: next,
        // tg_study_group_capacity closes the group the moment it fills.
        isOpen: next < _studyGroups[i].maxMembers,
      );
      return;
    }
  }

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
    _ensureSeeded();
    final id = _newId();
    final group = StudyGroup(
      id: id,
      conversationId: id,
      subject: subject,
      title: title,
      description: description,
      schedule: schedule,
      venue: venue,
      hostId: 'me',
      hostName: hostName,
      memberCount: 1,
      maxMembers: maxMembers,
    );
    _studyGroups.insert(0, group);
    _joined.add(id);
    return group;
  }

  @override
  Future<void> setProjectApplication({
    required String projectId,
    required bool applied,
  }) async {
    _ensureSeeded();
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index == -1) return;

    if (applied ? !_applied.add(projectId) : !_applied.remove(projectId)) return;
    _projects[index] = _projects[index].copyWith(
      applicantCount: _projects[index].applicantCount + (applied ? 1 : -1),
    );
  }

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
    _ensureSeeded();
    final project = Project(
      id: _newId(),
      title: title,
      description: description,
      stage: stage,
      techStack: techStack,
      rolesNeeded: rolesNeeded,
      ownerId: 'me',
      ownerName: ownerName,
    );
    _projects.insert(0, project);
    return project;
  }

  @override
  Future<void> votePoll({
    required String pollId,
    required String optionId,
  }) async {
    _ensureSeeded();
    final index = _polls.indexWhere((p) => p.id == pollId);
    if (index == -1) return;

    final poll = _polls[index];
    _polls[index] = poll.copyWith(
      options: poll.options
          .map((o) => o.id == optionId
              ? PollOption(id: o.id, text: o.text, votes: o.votes + 1)
              : o)
          .toList(),
      hasVoted: true,
      votedOptionId: optionId,
    );
  }

  @override
  Future<Poll> createPoll({
    required String question,
    required List<String> options,
    required String authorName,
  }) async {
    _ensureSeeded();
    final poll = Poll(
      id: _newId(),
      question: question,
      authorId: 'me',
      authorName: authorName,
      options: options.map((t) => PollOption(id: _newId(), text: t)).toList(),
    );
    _polls.insert(0, poll);
    return poll;
  }

  @override
  Future<void> markNotificationRead(String id) async {
    _ensureSeeded();
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;
    _notifications[index] = _notifications[index].copyWith(isRead: true);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    _ensureSeeded();
    for (var i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
  }

  @override
  Future<void> clearNotifications() async {
    _ensureSeeded();
    _notifications.clear();
  }

  @override
  Stream<CampusChange> changes() => _changes.stream;

  @override
  Future<void> close() => _changes.close();
}

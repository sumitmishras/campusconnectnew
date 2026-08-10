import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/repositories/campus_repository.dart';
import '../data/repositories/repositories.dart';
import '../models/campus_models.dart';

/// The Campus Hub: events, communities, clubs, study groups, projects, polls
/// and notifications.
///
/// Nothing in here knows whether it is talking to Postgres or to fixtures —
/// [CampusRepository] answers that, and [Repositories] chose which one at
/// startup.
///
/// Every toggle is **optimistic**: the tap is reflected immediately, the write
/// goes out behind it, and a failure puts the card back and leaves a message in
/// [lastActionError]. The alternative is a spinner on a button whose result is
/// almost never in doubt.
class CampusProvider with ChangeNotifier {
  CampusProvider({CampusRepository? repository})
      : _repo = repository ?? Repositories.campus {
    _load();
    _listen();
  }

  final CampusRepository _repo;

  List<Event> _events = [];
  List<Community> _communities = [];
  List<Club> _clubs = [];
  List<StudyGroup> _studyGroups = [];
  List<Project> _projects = [];
  List<Poll> _polls = [];
  List<CampusNotification> _notifications = [];
  bool _isLoading = false;
  String? _lastActionError;

  final Set<String> _joinedEventIds = {};
  final Set<String> _savedEventIds = {};

  /// Membership in a community, club, study group or project team *is* a
  /// `conversation_members` row, so one set answers "have I joined" for all of
  /// them — see the note at the top of `0005_campus_hub.sql`.
  final Set<String> _joinedConversationIds = {};

  final Set<String> _appliedProjectIds = {};

  /// Notifications hidden by "Clear all" while the delete is in flight.
  final Set<String> _hiddenNotificationIds = {};

  String _eventCategory = 'All';

  StreamSubscription<CampusChange>? _changeSub;

  bool get isLoading => _isLoading;
  List<Community> get communities => _communities;
  List<Club> get clubs => _clubs;
  List<StudyGroup> get studyGroups => _studyGroups;
  List<Project> get projects => _projects;
  List<Poll> get polls => _polls;
  List<CampusNotification> get notifications => _notifications
      .where((n) => !_hiddenNotificationIds.contains(n.id))
      .toList();
  String get eventCategory => _eventCategory;

  /// Set when an optimistic action was rolled back.
  String? get lastActionError => _lastActionError;

  void clearActionError() {
    if (_lastActionError == null) return;
    _lastActionError = null;
    notifyListeners();
  }

  static const eventCategories = ['All', 'Technical', 'Workshop', 'Cultural', 'Sports'];

  Future<void> _load() async {
    _isLoading = true;
    notifyListeners();

    try {
      _apply(await _repo.fetchAll());
    } catch (_) {
      // An unreachable hub is an empty one; every screen has an empty state
      // and pull-to-refresh is the way back.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _apply(CampusSnapshot snapshot) {
    _events = List.of(snapshot.events);
    _communities = List.of(snapshot.communities);
    _clubs = List.of(snapshot.clubs);
    _studyGroups = List.of(snapshot.studyGroups);
    _projects = List.of(snapshot.projects);
    _polls = List.of(snapshot.polls);
    _notifications = List.of(snapshot.notifications);

    _joinedConversationIds
      ..clear()
      ..addAll(snapshot.joinedConversationIds);
    _joinedEventIds
      ..clear()
      ..addAll(snapshot.goingEventIds);
    _savedEventIds
      ..clear()
      ..addAll(snapshot.savedEventIds);
    _appliedProjectIds
      ..clear()
      ..addAll(snapshot.appliedProjectIds);
    _hiddenNotificationIds.clear();
  }

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();
    try {
      _apply(await _repo.fetchAll());
    } catch (_) {
      // Keep what is on screen.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _listen() {
    _changeSub = _repo.changes().listen(_onChange);
  }

  /// Realtime tells us *what* moved; the affected list is re-read rather than
  /// patched from a replicated row, so a poll tally and its "have I voted" flag
  /// can never disagree.
  Future<void> _onChange(CampusChange change) async {
    try {
      switch (change) {
        case CampusChange.notifications:
          _notifications = await _repo.fetchNotifications();
        case CampusChange.polls:
          _polls = await _repo.fetchPolls();
        case CampusChange.events:
          _events = await _repo.fetchEvents();
      }
      notifyListeners();
    } catch (_) {
      // Ignore: the next full refresh will agree.
    }
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _repo.close();
    super.dispose();
  }

  /// Applies the change, notifies immediately, and puts it back if the write
  /// fails. Mirrors `UserProvider._mutate`.
  void _commit({
    required Future<void> Function() write,
    required VoidCallback revert,
    required String fallbackMessage,
  }) {
    _lastActionError = null;
    unawaited(write().catchError((Object error) {
      revert();
      _lastActionError =
          error is CampusFailure ? error.message : fallbackMessage;
      notifyListeners();
    }));
  }

  // ----------------------------------------------------------------- events

  List<Event> get events {
    if (_eventCategory == 'All') return _events;
    return _events.where((e) => e.category == _eventCategory).toList();
  }

  List<Event> get upcomingEvents =>
      _events.where((e) => !e.isPast).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  List<Event> get joinedEvents =>
      _events.where((e) => _joinedEventIds.contains(e.id)).toList();

  List<Event> get savedEvents =>
      _events.where((e) => _savedEventIds.contains(e.id)).toList();

  Event? eventById(String id) {
    for (final e in _events) {
      if (e.id == id) return e;
    }
    return null;
  }

  void setEventCategory(String category) {
    _eventCategory = category;
    notifyListeners();
  }

  bool isEventJoined(String eventId) => _joinedEventIds.contains(eventId);
  bool isEventSaved(String eventId) => _savedEventIds.contains(eventId);

  /// Returns `true` when the student just joined, `false` when they left.
  bool toggleEventJoin(String eventId) {
    final index = _events.indexWhere((e) => e.id == eventId);
    if (index == -1) return false;

    final joining = !_joinedEventIds.contains(eventId);
    final before = _events[index];

    if (joining) {
      _joinedEventIds.add(eventId);
    } else {
      _joinedEventIds.remove(eventId);
    }
    // `going_count` is kept by tg_event_rsvp_counts server-side; this is the
    // same arithmetic applied locally so the card does not wait for a refetch.
    _events[index] = before.copyWith(
      goingCount: before.goingCount + (joining ? 1 : -1),
    );
    notifyListeners();

    _commit(
      write: () => _repo.setEventRsvp(eventId: eventId, going: joining),
      revert: () {
        if (joining) {
          _joinedEventIds.remove(eventId);
        } else {
          _joinedEventIds.add(eventId);
        }
        final at = _events.indexWhere((e) => e.id == eventId);
        if (at != -1) _events[at] = before;
      },
      fallbackMessage: 'That registration could not be saved.',
    );

    return joining;
  }

  bool toggleEventSaved(String eventId) {
    final saved = !_savedEventIds.contains(eventId);
    if (saved) {
      _savedEventIds.add(eventId);
    } else {
      _savedEventIds.remove(eventId);
    }
    notifyListeners();

    _commit(
      write: () => _repo.setEventSaved(eventId: eventId, saved: saved),
      revert: () {
        if (saved) {
          _savedEventIds.remove(eventId);
        } else {
          _savedEventIds.add(eventId);
        }
      },
      fallbackMessage: 'That event could not be saved.',
    );

    return saved;
  }

  // ------------------------------------------------------------ communities

  Community? communityById(String id) {
    for (final c in _communities) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool isCommunityJoined(String id) =>
      _isJoined(communityById(id)?.conversationId);

  bool _isJoined(String? conversationId) =>
      conversationId != null && _joinedConversationIds.contains(conversationId);

  List<Community> get joinedCommunities =>
      _communities.where((c) => _isJoined(c.conversationId)).toList();

  bool toggleCommunityJoin(String communityId) {
    final index = _communities.indexWhere((c) => c.id == communityId);
    if (index == -1) return false;

    final community = _communities[index];
    final joining = !_isJoined(community.conversationId);

    _setMembership(community.conversationId, joining);
    _communities[index] = community.copyWith(
      memberCount: community.memberCount + (joining ? 1 : -1),
    );
    notifyListeners();

    _commitMembership(
      conversationId: community.conversationId,
      joining: joining,
      revert: () {
        _setMembership(community.conversationId, !joining);
        final at = _communities.indexWhere((c) => c.id == communityId);
        if (at != -1) _communities[at] = community;
      },
    );

    return joining;
  }

  void _setMembership(String conversationId, bool joined) {
    if (joined) {
      _joinedConversationIds.add(conversationId);
    } else {
      _joinedConversationIds.remove(conversationId);
    }
  }

  void _commitMembership({
    required String conversationId,
    required bool joining,
    required VoidCallback revert,
  }) {
    _commit(
      write: () => joining
          ? _repo.joinConversation(conversationId)
          : _repo.leaveConversation(conversationId),
      revert: revert,
      fallbackMessage: joining
          ? 'You could not be added to that group.'
          : 'You could not be removed from that group.',
    );
  }

  // ------------------------------------------------------------------ clubs

  Club? clubById(String id) {
    for (final c in _clubs) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool isClubJoined(String id) => _isJoined(clubById(id)?.conversationId);

  List<Club> clubsByCategory(String category) => category == 'All'
      ? _clubs
      : _clubs.where((c) => c.category == category).toList();

  List<String> get clubCategories {
    final set = _clubs.map((c) => c.category).toSet().toList()..sort();
    return ['All', ...set];
  }

  bool toggleClubJoin(String clubId) {
    final index = _clubs.indexWhere((c) => c.id == clubId);
    if (index == -1) return false;

    final club = _clubs[index];
    final joining = !_isJoined(club.conversationId);

    _setMembership(club.conversationId, joining);
    _clubs[index] = club.copyWith(
      memberCount: club.memberCount + (joining ? 1 : -1),
    );
    notifyListeners();

    _commitMembership(
      conversationId: club.conversationId,
      joining: joining,
      revert: () {
        _setMembership(club.conversationId, !joining);
        final at = _clubs.indexWhere((c) => c.id == clubId);
        if (at != -1) _clubs[at] = club;
      },
    );

    return joining;
  }

  // ----------------------------------------------------------- study groups

  StudyGroup? studyGroupById(String id) {
    for (final g in _studyGroups) {
      if (g.id == id) return g;
    }
    return null;
  }

  bool isStudyGroupJoined(String id) =>
      _isJoined(studyGroupById(id)?.conversationId);

  bool toggleStudyGroupJoin(String groupId) {
    final index = _studyGroups.indexWhere((g) => g.id == groupId);
    if (index == -1) return false;

    final group = _studyGroups[index];
    final joining = !_isJoined(group.conversationId);

    _setMembership(group.conversationId, joining);
    _studyGroups[index] = group.copyWith(
      memberCount: group.memberCount + (joining ? 1 : -1),
    );
    notifyListeners();

    _commitMembership(
      conversationId: group.conversationId,
      joining: joining,
      revert: () {
        _setMembership(group.conversationId, !joining);
        final at = _studyGroups.indexWhere((g) => g.id == groupId);
        if (at != -1) _studyGroups[at] = group;
      },
    );

    return joining;
  }

  /// Returns the created group so the caller can open its chat thread, or null
  /// with [lastActionError] set.
  ///
  /// Not optimistic: the group, its thread and the host's membership are
  /// created together by `create_study_group()`, and the caller needs the ids
  /// that function allocated.
  Future<StudyGroup?> createStudyGroup({
    required String subject,
    required String title,
    required String description,
    required String schedule,
    required String venue,
    required String hostName,
    int maxMembers = 8,
  }) async {
    _lastActionError = null;
    try {
      final group = await _repo.createStudyGroup(
        subject: subject,
        title: title,
        description: description,
        schedule: schedule,
        venue: venue,
        hostName: hostName,
        maxMembers: maxMembers,
      );

      _studyGroups.insert(0, group);
      _joinedConversationIds.add(group.conversationId);
      notifyListeners();
      return group;
    } on CampusFailure catch (e) {
      _lastActionError = e.message;
      notifyListeners();
      return null;
    }
  }

  // --------------------------------------------------------------- projects

  bool hasAppliedToProject(String id) => _appliedProjectIds.contains(id);

  bool toggleProjectApplication(String projectId) {
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index == -1) return false;

    final before = _projects[index];
    final applying = !_appliedProjectIds.contains(projectId);

    if (applying) {
      _appliedProjectIds.add(projectId);
    } else {
      _appliedProjectIds.remove(projectId);
    }
    _projects[index] = before.copyWith(
      applicantCount: before.applicantCount + (applying ? 1 : -1),
    );
    notifyListeners();

    _commit(
      write: () => _repo.setProjectApplication(
        projectId: projectId,
        applied: applying,
      ),
      revert: () {
        if (applying) {
          _appliedProjectIds.remove(projectId);
        } else {
          _appliedProjectIds.add(projectId);
        }
        final at = _projects.indexWhere((p) => p.id == projectId);
        if (at != -1) _projects[at] = before;
      },
      fallbackMessage: 'That application could not be sent.',
    );

    return applying;
  }

  Future<bool> createProject({
    required String title,
    required String description,
    required String stage,
    required List<String> techStack,
    required List<String> rolesNeeded,
    required String ownerName,
    Uint8List? coverBytes,
    String coverFileName = 'cover.jpg',
  }) async {
    _lastActionError = null;
    try {
      final project = await _repo.createProject(
        title: title,
        description: description,
        stage: stage,
        techStack: techStack,
        rolesNeeded: rolesNeeded,
        ownerName: ownerName,
        coverBytes: coverBytes,
        coverFileName: coverFileName,
      );
      _projects.insert(0, project);
      notifyListeners();
      return true;
    } on CampusFailure catch (e) {
      _lastActionError = e.message;
      notifyListeners();
      return false;
    }
  }

  // ------------------------------------------------------------------ polls

  void votePoll(String pollId, String optionId) {
    final index = _polls.indexWhere((p) => p.id == pollId);
    if (index == -1) return;

    final poll = _polls[index];
    if (poll.hasVoted || poll.isClosed) return;

    final options = poll.options
        .map((o) => o.id == optionId
            ? PollOption(id: o.id, text: o.text, votes: o.votes + 1)
            : o)
        .toList();

    _polls[index] = poll.copyWith(
      options: options,
      hasVoted: true,
      votedOptionId: optionId,
    );
    notifyListeners();

    _commit(
      write: () => _repo.votePoll(pollId: pollId, optionId: optionId),
      revert: () {
        final at = _polls.indexWhere((p) => p.id == pollId);
        if (at != -1) _polls[at] = poll;
      },
      fallbackMessage: 'That vote could not be recorded.',
    );
  }

  Future<bool> createPoll({
    required String question,
    required List<String> options,
    required String authorName,
  }) async {
    _lastActionError = null;
    try {
      final poll = await _repo.createPoll(
        question: question,
        options: options,
        authorName: authorName,
      );
      _polls.insert(0, poll);
      notifyListeners();
      return true;
    } on CampusFailure catch (e) {
      _lastActionError = e.message;
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------- notifications

  int get unreadNotificationCount =>
      notifications.where((n) => !n.isRead).length;

  void markNotificationRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1 || _notifications[index].isRead) return;

    final before = _notifications[index];
    _notifications[index] = before.copyWith(isRead: true);
    notifyListeners();

    _commit(
      write: () => _repo.markNotificationRead(id),
      revert: () {
        final at = _notifications.indexWhere((n) => n.id == id);
        if (at != -1) _notifications[at] = before;
      },
      fallbackMessage: 'That notification could not be updated.',
    );
  }

  void markAllNotificationsRead() {
    final before = List.of(_notifications);
    _notifications =
        _notifications.map((n) => n.copyWith(isRead: true)).toList();
    notifyListeners();

    _commit(
      write: _repo.markAllNotificationsRead,
      revert: () => _notifications = before,
      fallbackMessage: 'Those notifications could not be updated.',
    );
  }

  void clearNotifications() {
    final before = List.of(_notifications);
    _hiddenNotificationIds.addAll(before.map((n) => n.id));
    _notifications = [];
    notifyListeners();

    _commit(
      write: _repo.clearNotifications,
      revert: () {
        _hiddenNotificationIds.clear();
        _notifications = before;
      },
      fallbackMessage: 'Those notifications could not be cleared.',
    );
  }
}

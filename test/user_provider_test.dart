import 'dart:async';

import 'package:campus_connect/core/data/repositories/connection_repository.dart';
import 'package:campus_connect/core/data/repositories/discover_repository.dart';
import 'package:campus_connect/core/models/connection_model.dart';
import 'package:campus_connect/core/models/discover_query.dart';
import 'package:campus_connect/core/models/page_result.dart';
import 'package:campus_connect/core/models/report_reason.dart';
import 'package:campus_connect/core/models/user_model.dart';
import 'package:campus_connect/core/providers/user_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------- fixtures

User _user(String id, {String name = 'Student', String department = 'Computer Science', String year = '3rd Year'}) =>
    User(
      id: id,
      name: '$name $id',
      username: id,
      email: '$id@cuchd.in',
      uid: '21BCS0000',
      phoneNumber: '',
      department: department,
      course: 'B.E. CSE',
      year: year,
      bio: '',
      interests: const [],
      languages: const [],
      lookingFor: const ['Study Partner'],
      profilePhotoUrl: '',
      lastActive: DateTime(2026, 1, 1),
    );

final _me = _user('me', name: 'Me');

Connection _connection({
  required String id,
  required String requester,
  required String addressee,
  ConnectionState state = ConnectionState.pending,
  String purpose = 'Friendship',
}) =>
    Connection(
      id: id,
      requesterId: requester,
      addresseeId: addressee,
      state: state,
      purpose: purpose,
      createdAt: DateTime(2026, 1, 1),
    );

// ------------------------------------------------------------------- fakes

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover(this.students);

  List<User> students;
  Object? failWith;
  int fetchCount = 0;
  DiscoverQuery? lastQuery;

  @override
  Future<PageResult<User>> fetchStudents({
    required DiscoverQuery query,
    int offset = 0,
    int limit = kDiscoverPageSize,
  }) async {
    fetchCount++;
    lastQuery = query;
    if (failWith != null) throw failWith!;

    final matches =
        students.where((s) => !query.excludeIds.contains(s.id)).toList();
    if (offset >= matches.length) {
      return PageResult<User>(
          items: const [], hasMore: false, nextOffset: offset);
    }
    final end = (offset + limit).clamp(0, matches.length);
    return PageResult(
      items: matches.sublist(offset, end),
      hasMore: end < matches.length,
      nextOffset: end,
    );
  }

  @override
  Future<List<User>> fetchByPurpose(
    List<String> purposes, {
    Set<String> excludeIds = const {},
    int limit = 60,
  }) async {
    if (failWith != null) throw failWith!;
    return students
        .where((s) => !excludeIds.contains(s.id))
        .where((s) => s.lookingFor.any(purposes.contains))
        .toList();
  }
}

class _FakeConnections implements ConnectionRepository {
  // Assigned per test rather than passed in, so a test can change the graph
  // after the provider already has a reference to this.
  List<ConnectionEntry> entries = const [];
  List<User> blocked = const [];

  /// Thrown by the next write. Cleared after it fires, so a test can fail one
  /// call and let the next succeed.
  Object? failNextWrite;
  Object? failFetch;
  final List<String> calls = [];

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> changes(String me) => _changes.stream;

  /// Stands in for a `connections` row arriving over Realtime.
  void pushChange() => _changes.add(null);

  @override
  Future<void> close() async {
    if (!_changes.isClosed) await _changes.close();
  }

  Object? _takeFailure() {
    final failure = failNextWrite;
    failNextWrite = null;
    return failure;
  }

  int fetchEntriesCount = 0;

  @override
  Future<List<ConnectionEntry>> fetchEntries(String me) async {
    fetchEntriesCount++;
    if (failFetch != null) throw failFetch!;
    return List.of(entries);
  }

  @override
  Future<List<User>> fetchBlocked(String me) async {
    if (failFetch != null) throw failFetch!;
    return List.of(blocked);
  }

  @override
  Future<ConnectionEntry> sendRequest({
    required String me,
    required User other,
    required String purpose,
    String? message,
  }) async {
    calls.add('send:${other.id}');
    final failure = _takeFailure();
    if (failure != null) throw failure;
    return ConnectionEntry(
      connection: _connection(
        id: 'saved-${other.id}',
        requester: me,
        addressee: other.id,
        purpose: purpose,
      ),
      other: other,
    );
  }

  @override
  Future<Connection> updateState({
    required String me,
    required Connection connection,
    required ConnectionState state,
  }) async {
    calls.add('${state.wire}:${connection.id}');
    final failure = _takeFailure();
    if (failure != null) throw failure;
    return connection.copyWith(state: state, respondedAt: DateTime(2026, 2, 1));
  }

  @override
  Future<void> block({
    required String me,
    required User other,
    String? reason,
  }) async {
    calls.add('block:${other.id}');
    final failure = _takeFailure();
    if (failure != null) throw failure;
  }

  @override
  Future<void> unblock({required String me, required String otherId}) async {
    calls.add('unblock:$otherId');
    final failure = _takeFailure();
    if (failure != null) throw failure;
  }

  @override
  Future<void> report({
    required String me,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    calls.add('report:$targetId:${reason.wire}');
    final failure = _takeFailure();
    if (failure != null) throw failure;
  }
}

// ------------------------------------------------------------------- tests

void main() {
  late List<User> students;
  late _FakeDiscover discover;
  late _FakeConnections connections;
  late UserProvider provider;

  /// Lets every pending microtask and zero-delay future finish.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

  UserProvider build({Duration debounce = Duration.zero}) {
    return UserProvider(
      discover: discover,
      connections: connections,
      searchDebounce: debounce,
    );
  }

  Future<UserProvider> signedIn({Duration debounce = Duration.zero}) async {
    final p = build(debounce: debounce);
    p.syncCurrentUser(_me);
    await settle();
    return p;
  }

  setUp(() {
    students = List.generate(25, (i) => _user('s$i'));
    discover = _FakeDiscover(students);
    connections = _FakeConnections();
  });

  tearDown(() => provider.dispose());

  group('bootstrap', () {
    test('nothing loads until someone is signed in', () async {
      provider = build();
      await settle();

      expect(discover.fetchCount, 0);
      expect(provider.students, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test('signing in loads the first page and the connection graph', () async {
      provider = await signedIn();

      expect(discover.fetchCount, 1);
      expect(provider.students, hasLength(kDiscoverPageSize));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('the signed-in student is never in their own Discover list',
        () async {
      provider = await signedIn();
      expect(discover.lastQuery!.excludeIds, contains('me'));
    });

    test('signing out clears everything', () async {
      provider = await signedIn();
      provider.syncCurrentUser(null);
      await settle();

      expect(provider.students, isEmpty);
      expect(provider.connections, isEmpty);
      expect(provider.blockedStudents, isEmpty);
    });
  });

  group('pagination', () {
    test('loadMore appends the next page', () async {
      provider = await signedIn();
      expect(provider.students, hasLength(20));
      expect(provider.hasMore, isTrue);

      await provider.loadMore();
      expect(provider.students, hasLength(25));
      expect(provider.hasMore, isFalse);
    });

    test('loadMore is a no-op once the end is reached', () async {
      provider = await signedIn();
      await provider.loadMore();
      final calls = discover.fetchCount;

      await provider.loadMore();
      expect(discover.fetchCount, calls);
    });

    test('a student who shifts between pages is not shown twice', () async {
      provider = await signedIn();
      // Simulates a row moving: page two now starts with someone page one
      // already had.
      discover.students = [...students.sublist(19)];

      await provider.loadMore();
      final ids = provider.students.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('changing a filter starts again from page one', () async {
      provider = await signedIn();
      await provider.loadMore();
      expect(provider.students, hasLength(25));

      provider.applyAdvancedFilters(gender: 'Female');
      await settle();
      expect(provider.students, hasLength(20));
    });
  });

  group('search', () {
    test('reaches the repository', () async {
      provider = await signedIn();
      provider.searchStudents('aarav');
      await settle();

      expect(discover.lastQuery!.search, 'aarav');
    });

    test('a burst of keystrokes is one query', () async {
      provider = await signedIn(debounce: const Duration(milliseconds: 40));
      final before = discover.fetchCount;

      provider.searchStudents('a');
      provider.searchStudents('aa');
      provider.searchStudents('aar');
      provider.searchStudents('aara');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(discover.fetchCount, before + 1);
      expect(discover.lastQuery!.search, 'aara');
    });

    test('typing back to the same term does not refetch', () async {
      provider = await signedIn();
      provider.searchStudents('aarav');
      await settle();
      final calls = discover.fetchCount;

      provider.searchStudents('aarav');
      await settle();
      expect(discover.fetchCount, calls);
    });

    test('clearing search and filters resets both', () async {
      provider = await signedIn();
      provider.searchStudents('aarav');
      provider.applyAdvancedFilters(department: 'AI & ML');
      await settle();

      provider.clearSearchAndFilters();
      await settle();

      expect(provider.query, '');
      expect(provider.departmentFilter, DiscoverQuery.any);
      expect(discover.lastQuery!.search, '');
    });

    test('clearing filters leaves the search term alone', () async {
      provider = await signedIn();
      provider.searchStudents('aarav');
      await settle();

      provider.clearFilters();
      await settle();

      expect(provider.query, 'aarav');
      expect(discover.lastQuery!.search, 'aarav');
    });
  });

  group('filters', () {
    test('every facet reaches the query', () async {
      provider = await signedIn();
      provider.applyAdvancedFilters(
        department: 'AI & ML',
        year: '2nd Year',
        gender: 'Female',
        lookingFor: 'Networking',
        interests: const ['Coding'],
      );
      await settle();

      final query = discover.lastQuery!;
      expect(query.department, 'AI & ML');
      expect(query.year, '2nd Year');
      expect(query.gender, 'Female');
      expect(query.lookingFor, 'Networking');
      expect(query.interests, ['Coding']);
      expect(provider.activeFilterCount, 5);
    });

    test('they persist until cleared', () async {
      provider = await signedIn();
      provider.applyAdvancedFilters(department: 'AI & ML');
      await settle();

      provider.searchStudents('x');
      await settle();

      expect(provider.departmentFilter, 'AI & ML');
      expect(discover.lastQuery!.department, 'AI & ML');
    });

    test('re-applying the same facets does not refetch', () async {
      provider = await signedIn();
      provider.applyAdvancedFilters(department: 'AI & ML');
      await settle();
      final calls = discover.fetchCount;

      provider.applyAdvancedFilters(department: 'AI & ML');
      await settle();
      expect(discover.fetchCount, calls);
    });

    test('"same department" resolves against the signed-in student', () async {
      provider = await signedIn();
      provider.setQuickFilter(DiscoverFilter.sameDepartment);
      await settle();

      expect(discover.lastQuery!.department, _me.department);
    });

    test('"online now" and "recently active" reach the query', () async {
      provider = await signedIn();

      provider.setQuickFilter(DiscoverFilter.online);
      await settle();
      expect(discover.lastQuery!.onlineOnly, isTrue);

      provider.setQuickFilter(DiscoverFilter.recentlyActive);
      await settle();
      expect(discover.lastQuery!.recentlyActive, isTrue);
    });

    test('a quick filter contradicting a facet is empty without a round trip',
        () async {
      provider = await signedIn();
      provider.applyAdvancedFilters(department: 'Management');
      await settle();
      final calls = discover.fetchCount;

      provider.setQuickFilter(DiscoverFilter.sameDepartment);
      await settle();

      expect(provider.students, isEmpty);
      expect(discover.fetchCount, calls);
    });

    test('editing my own department re-runs "same department"', () async {
      provider = await signedIn();
      provider.setQuickFilter(DiscoverFilter.sameDepartment);
      await settle();
      final calls = discover.fetchCount;

      provider.syncCurrentUser(_me.copyWith(department: 'AI & ML'));
      await settle();

      expect(discover.fetchCount, calls + 1);
      expect(discover.lastQuery!.department, 'AI & ML');
    });

    test('an unrelated profile edit does not disturb the list', () async {
      provider = await signedIn();
      final calls = discover.fetchCount;

      provider.syncCurrentUser(_me.copyWith(bio: 'new bio'));
      await settle();

      expect(discover.fetchCount, calls);
    });
  });

  group('error states', () {
    test('a failed first page surfaces an error and an empty list', () async {
      discover.failWith = Exception('offline');
      provider = await signedIn();

      expect(provider.error, isNotNull);
      expect(provider.students, isEmpty);
    });

    test('retry recovers', () async {
      discover.failWith = Exception('offline');
      provider = await signedIn();
      expect(provider.error, isNotNull);

      discover.failWith = null;
      await provider.retry();

      expect(provider.error, isNull);
      expect(provider.students, hasLength(20));
    });

    test('a failed later page keeps the students already on screen', () async {
      provider = await signedIn();
      expect(provider.students, hasLength(20));

      discover.failWith = Exception('offline');
      await provider.loadMore();

      expect(provider.error, isNotNull);
      expect(provider.students, hasLength(20));
    });

    test('a failed connections load does not blank Discover', () async {
      connections.failFetch = Exception('offline');
      provider = await signedIn();

      expect(provider.connectionsError, isNotNull);
      expect(provider.students, hasLength(20));
      expect(provider.error, isNull);
    });
  });

  group('live connection graph', () {
    /// Longer than the provider's coalescing window.
    Future<void> settleRealtime() =>
        Future<void>.delayed(const Duration(milliseconds: 450));

    test('a request arriving reloads the graph without a pull to refresh',
        () async {
      provider = await signedIn();
      final before = connections.fetchEntriesCount;
      expect(provider.receivedRequests, isEmpty);

      // What the other student's phone writes when they tap Connect.
      connections.entries = [
        ConnectionEntry(
          connection: _connection(id: 'c9', requester: 's7', addressee: 'me'),
          other: students[7],
        ),
      ];
      connections.pushChange();
      await settleRealtime();

      expect(connections.fetchEntriesCount, greaterThan(before));
      expect(provider.relationshipWith('s7'), ConnectionStatus.incoming);
      expect(provider.receivedRequests.map((u) => u.id), ['s7']);
    });

    test('a burst of events costs one reload, not one each', () async {
      provider = await signedIn();
      final before = connections.fetchEntriesCount;

      // Accepting writes the row and the trigger touches it again; both come
      // back within milliseconds of each other.
      connections
        ..pushChange()
        ..pushChange()
        ..pushChange();
      await settleRealtime();

      expect(connections.fetchEntriesCount, before + 1);
    });

    test('the reload never flips the tab back to a spinner', () async {
      provider = await signedIn();

      connections.pushChange();
      await settleRealtime();

      expect(provider.isLoadingConnections, isFalse);
    });
  });

  group('relationship state', () {
    setUp(() {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(
              id: 'c1', requester: 'me', addressee: 's1'), // outgoing
          other: students[1],
        ),
        ConnectionEntry(
          connection: _connection(
              id: 'c2', requester: 's2', addressee: 'me'), // incoming
          other: students[2],
        ),
        ConnectionEntry(
          connection: _connection(
            id: 'c3',
            requester: 'me',
            addressee: 's3',
            state: ConnectionState.accepted,
          ),
          other: students[3],
        ),
      ];
      connections.blocked = [students[4]];
    });

    test('reports all six states correctly', () async {
      provider = await signedIn();

      expect(provider.relationshipWith('s0'), ConnectionStatus.none);
      expect(provider.relationshipWith('s1'), ConnectionStatus.outgoing);
      expect(provider.relationshipWith('s2'), ConnectionStatus.incoming);
      expect(provider.relationshipWith('s3'), ConnectionStatus.connected);
      expect(provider.relationshipWith('s4'), ConnectionStatus.blocked);
      expect(provider.relationshipWith('nobody'), ConnectionStatus.none);
    });

    test('the tabs split by direction', () async {
      provider = await signedIn();

      expect(provider.sentRequests.map((u) => u.id), ['s1']);
      expect(provider.receivedRequests.map((u) => u.id), ['s2']);
      expect(provider.connections.map((u) => u.id), ['s3']);
    });

    test('the purpose comes back with the request', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(
            id: 'c1',
            requester: 's1',
            addressee: 'me',
            purpose: 'Study Partner',
          ),
          other: students[1],
        ),
      ];
      provider = await signedIn();

      expect(provider.requestPurpose('s1'), 'Study Partner');
    });

    test('blocked students are excluded from the Discover query', () async {
      provider = await signedIn();
      expect(discover.lastQuery!.excludeIds, contains('s4'));
    });
  });

  group('optimistic actions', () {
    test('sending shows as outgoing before the write lands', () async {
      provider = await signedIn();
      final future = provider.sendConnectionRequest(students[0], 'Networking');

      // Not awaited yet — this is the frame the student actually sees.
      expect(provider.relationshipWith('s0'), ConnectionStatus.outgoing);
      expect(provider.requestPurpose('s0'), 'Networking');

      expect(await future, isTrue);
      expect(provider.relationshipWith('s0'), ConnectionStatus.outgoing);
      expect(provider.entryFor('s0')!.id, 'saved-s0');
    });

    test('a failed send rolls back and explains why', () async {
      provider = await signedIn();
      connections.failNextWrite = const ConnectionFailure('Daily limit hit');

      final ok = await provider.sendConnectionRequest(students[0], 'Friendship');

      expect(ok, isFalse);
      expect(provider.relationshipWith('s0'), ConnectionStatus.none);
      expect(provider.lastActionError, 'Daily limit hit');
    });

    test('accepting flips to connected and sticks', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(id: 'c1', requester: 's1', addressee: 'me'),
          other: students[1],
        ),
      ];
      provider = await signedIn();

      expect(await provider.acceptRequest(students[1]), isTrue);
      expect(provider.relationshipWith('s1'), ConnectionStatus.connected);
      expect(provider.receivedRequests, isEmpty);
      expect(provider.connections.map((u) => u.id), ['s1']);
    });

    test('a failed accept puts the request back', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(id: 'c1', requester: 's1', addressee: 'me'),
          other: students[1],
        ),
      ];
      provider = await signedIn();
      connections.failNextWrite =
          const ConnectionFailure('This request has already been answered.');

      expect(await provider.acceptRequest(students[1]), isFalse);
      expect(provider.relationshipWith('s1'), ConnectionStatus.incoming);
      expect(provider.receivedRequests.map((u) => u.id), ['s1']);
      expect(provider.lastActionError,
          'This request has already been answered.');
    });

    test('declining removes it, and a failure restores it', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(id: 'c1', requester: 's1', addressee: 'me'),
          other: students[1],
        ),
      ];
      provider = await signedIn();

      connections.failNextWrite = const ConnectionFailure('nope');
      expect(await provider.declineRequest(students[1]), isFalse);
      expect(provider.receivedRequests.map((u) => u.id), ['s1']);

      expect(await provider.declineRequest(students[1]), isTrue);
      expect(provider.receivedRequests, isEmpty);
      expect(provider.relationshipWith('s1'), ConnectionStatus.none);
    });

    test('withdrawing sends the withdrawn state', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(id: 'c1', requester: 'me', addressee: 's1'),
          other: students[1],
        ),
      ];
      provider = await signedIn();

      expect(await provider.cancelRequest(students[1]), isTrue);
      expect(connections.calls, contains('withdrawn:c1'));
      expect(provider.sentRequests, isEmpty);
    });

    test('removing a connection cancels it, the only legal way out', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(
            id: 'c1',
            requester: 'me',
            addressee: 's1',
            state: ConnectionState.accepted,
          ),
          other: students[1],
        ),
      ];
      provider = await signedIn();

      expect(await provider.removeConnection(students[1]), isTrue);
      expect(connections.calls, contains('cancelled:c1'));
      expect(provider.connections, isEmpty);
      expect(provider.relationshipWith('s1'), ConnectionStatus.none);
    });

    test('ignoring hides the request without writing anything', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(id: 'c1', requester: 's1', addressee: 'me'),
          other: students[1],
        ),
      ];
      provider = await signedIn();

      provider.ignoreRequest(students[1]);

      expect(provider.receivedRequests, isEmpty);
      expect(provider.isIgnored('s1'), isTrue);
      // Still pending as far as the backend is concerned.
      expect(provider.relationshipWith('s1'), ConnectionStatus.incoming);
      expect(connections.calls, isEmpty);

      provider.unignoreRequest(students[1]);
      expect(provider.receivedRequests.map((u) => u.id), ['s1']);
    });
  });

  group('blocking', () {
    test('blocking drops them from Discover and the connection graph',
        () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(
            id: 'c1',
            requester: 'me',
            addressee: 's1',
            state: ConnectionState.accepted,
          ),
          other: students[1],
        ),
      ];
      provider = await signedIn();
      expect(provider.students.map((s) => s.id), contains('s1'));

      expect(await provider.blockUser(students[1]), isTrue);

      expect(provider.relationshipWith('s1'), ConnectionStatus.blocked);
      expect(provider.students.map((s) => s.id), isNot(contains('s1')));
      expect(provider.connections, isEmpty);
      expect(provider.blockedStudents.map((u) => u.id), ['s1']);
    });

    test('a failed block puts the card and the connection back', () async {
      connections.entries = [
        ConnectionEntry(
          connection: _connection(
            id: 'c1',
            requester: 'me',
            addressee: 's1',
            state: ConnectionState.accepted,
          ),
          other: students[1],
        ),
      ];
      provider = await signedIn();
      connections.failNextWrite = const ConnectionFailure('offline');

      expect(await provider.blockUser(students[1]), isFalse);

      expect(provider.relationshipWith('s1'), ConnectionStatus.connected);
      expect(provider.students.map((s) => s.id), contains('s1'));
      expect(provider.connections.map((u) => u.id), ['s1']);
      expect(provider.blockedStudents, isEmpty);
    });

    test('unblocking works, and rolls back on failure', () async {
      connections.blocked = [students[1]];
      provider = await signedIn();
      expect(provider.isBlocked('s1'), isTrue);

      connections.failNextWrite = const ConnectionFailure('offline');
      expect(await provider.unblockUser(students[1]), isFalse);
      expect(provider.isBlocked('s1'), isTrue);

      expect(await provider.unblockUser(students[1]), isTrue);
      expect(provider.isBlocked('s1'), isFalse);
    });
  });

  group('reporting', () {
    test('sends the enum value, not the label', () async {
      provider = await signedIn();

      expect(
        await provider.reportUser(students[1], ReportReason.impersonation),
        isTrue,
      );
      expect(connections.calls, contains('report:s1:impersonation'));
      expect(provider.isReported('s1'), isTrue);
    });

    test('a failed report is not remembered as sent', () async {
      provider = await signedIn();
      connections.failNextWrite = const ConnectionFailure('rate limited');

      expect(await provider.reportUser(students[1], ReportReason.spam), isFalse);
      expect(provider.isReported('s1'), isFalse);
      expect(provider.lastActionError, 'rate limited');
    });
  });

  group('partner shortlists', () {
    test('come from the repository, not the loaded page', () async {
      provider = await signedIn();

      // First call is a miss and kicks off the fetch.
      expect(provider.studentsLookingFor(const ['Study Partner']), isEmpty);
      await settle();

      final partners = provider.studentsLookingFor(const ['Study Partner']);
      expect(partners, hasLength(25));
    });

    test('blocked students never appear in one', () async {
      connections.blocked = [students[1]];
      provider = await signedIn();

      provider.studentsLookingFor(const ['Study Partner']);
      await settle();

      final partners = provider.studentsLookingFor(const ['Study Partner']);
      expect(partners.map((u) => u.id), isNot(contains('s1')));
    });
  });

  group('bookmarks', () {
    test('toggle on and off, resolving through the profile cache', () async {
      provider = await signedIn();

      expect(provider.toggleBookmark('s1'), isTrue);
      expect(provider.isBookmarked('s1'), isTrue);
      expect(provider.bookmarkedStudents.map((u) => u.id), ['s1']);

      expect(provider.toggleBookmark('s1'), isFalse);
      expect(provider.bookmarkedStudents, isEmpty);
    });

    test('blocking someone drops their bookmark', () async {
      provider = await signedIn();
      provider.toggleBookmark('s1');

      await provider.blockUser(students[1]);
      expect(provider.isBookmarked('s1'), isFalse);
    });
  });
}

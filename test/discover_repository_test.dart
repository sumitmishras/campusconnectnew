import 'package:campus_connect/core/data/repositories/discover_repository.dart';
import 'package:campus_connect/core/models/discover_query.dart';
import 'package:campus_connect/core/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

User _student({
  required String id,
  String name = 'Aarav Sharma',
  String username = 'aarav',
  String department = 'Computer Science',
  String course = 'B.E. CSE',
  String year = '3rd Year',
  String gender = 'Male',
  List<String> interests = const ['Coding'],
  List<String> lookingFor = const ['Study Partner'],
  bool isOnline = false,
  Duration seenAgo = const Duration(days: 3),
  bool hideActiveStatus = false,
}) {
  return User(
    id: id,
    name: name,
    username: username,
    email: '$username@cuchd.in',
    uid: '21BCS0000',
    phoneNumber: '',
    gender: gender,
    department: department,
    course: course,
    year: year,
    bio: '',
    interests: interests,
    languages: const ['Hindi'],
    lookingFor: lookingFor,
    profilePhotoUrl: '',
    isOnline: isOnline,
    lastActive: DateTime.now().subtract(seenAgo),
    hideActiveStatus: hideActiveStatus,
  );
}

void main() {
  late List<User> fixture;
  late MockDiscoverRepository repo;

  setUp(() {
    fixture = [
      _student(id: 'a', name: 'Aarav Sharma', username: 'aarav'),
      _student(
        id: 'b',
        name: 'Bhavya Singh',
        username: 'bhavya',
        gender: 'Female',
        department: 'AI & ML',
        course: 'B.E. AI & ML',
        year: '2nd Year',
        interests: const ['Photography', 'Music'],
        lookingFor: const ['Friendship'],
        isOnline: true,
        seenAgo: Duration.zero,
      ),
      _student(
        id: 'c',
        name: 'Chirag Verma',
        username: 'chirag',
        year: '4th Year',
        interests: const ['Coding', 'Startups'],
        lookingFor: const ['Project Partner', 'Study Partner'],
        seenAgo: const Duration(hours: 2),
      ),
      _student(
        id: 'd',
        name: 'Diya Patel',
        username: 'diya',
        gender: 'Female',
        department: 'Management',
        course: 'BBA',
        interests: const ['Dance'],
        lookingFor: const ['Networking'],
        isOnline: true,
        hideActiveStatus: true,
        seenAgo: Duration.zero,
      ),
    ];
    repo = MockDiscoverRepository(
      students: () => fixture,
      latency: Duration.zero,
    );
  });

  Future<List<User>> run(DiscoverQuery query) async =>
      (await repo.fetchStudents(query: query, limit: 50)).items;

  group('pagination', () {
    test('a page reports where the next one starts', () async {
      final page = await repo.fetchStudents(
          query: const DiscoverQuery(), offset: 0, limit: 2);

      expect(page.items.map((u) => u.id), ['a', 'b']);
      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 2);
    });

    test('the last page says so', () async {
      final page = await repo.fetchStudents(
          query: const DiscoverQuery(), offset: 2, limit: 2);

      expect(page.items.map((u) => u.id), ['c', 'd']);
      expect(page.hasMore, isFalse);
      expect(page.nextOffset, 4);
    });

    test('an offset past the end is empty rather than an error', () async {
      final page = await repo.fetchStudents(
          query: const DiscoverQuery(), offset: 99, limit: 2);

      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('walking every page visits each student exactly once', () async {
      final seen = <String>[];
      var offset = 0;
      var hasMore = true;

      while (hasMore) {
        final page = await repo.fetchStudents(
            query: const DiscoverQuery(), offset: offset, limit: 3);
        seen.addAll(page.items.map((u) => u.id));
        offset = page.nextOffset;
        hasMore = page.hasMore;
      }

      expect(seen, ['a', 'b', 'c', 'd']);
    });
  });

  group('search', () {
    test('matches a name', () async {
      final result = await run(const DiscoverQuery(search: 'bhavya'));
      expect(result.map((u) => u.id), ['b']);
    });

    test('matches a department', () async {
      final result = await run(const DiscoverQuery(search: 'management'));
      expect(result.map((u) => u.id), ['d']);
    });

    test('matches a course', () async {
      final result = await run(const DiscoverQuery(search: 'bba'));
      expect(result.map((u) => u.id), ['d']);
    });

    test('matches a year', () async {
      final result = await run(const DiscoverQuery(search: '4th'));
      expect(result.map((u) => u.id), ['c']);
    });

    test('matches an interest', () async {
      final result = await run(const DiscoverQuery(search: 'photography'));
      expect(result.map((u) => u.id), ['b']);
    });

    test('matches what someone is looking for', () async {
      final result = await run(const DiscoverQuery(search: 'networking'));
      expect(result.map((u) => u.id), ['d']);
    });

    test('is case insensitive and partial', () async {
      final result = await run(const DiscoverQuery(search: 'CHIR'));
      expect(result.map((u) => u.id), ['c']);
    });

    test('a term nothing matches returns an empty page, not everything',
        () async {
      final result = await run(const DiscoverQuery(search: 'zzzzz'));
      expect(result, isEmpty);
    });
  });

  group('facets', () {
    test('department', () async {
      final result = await run(const DiscoverQuery(department: 'AI & ML'));
      expect(result.map((u) => u.id), ['b']);
    });

    test('year', () async {
      final result = await run(const DiscoverQuery(year: '3rd Year'));
      expect(result.map((u) => u.id), ['a', 'd']);
    });

    test('gender', () async {
      final result = await run(const DiscoverQuery(gender: 'Female'));
      expect(result.map((u) => u.id), ['b', 'd']);
    });

    test('looking for', () async {
      final result =
          await run(const DiscoverQuery(lookingFor: 'Study Partner'));
      expect(result.map((u) => u.id), ['a', 'c']);
    });

    test('interests overlap — any of them, not all', () async {
      final result =
          await run(const DiscoverQuery(interests: ['Dance', 'Startups']));
      expect(result.map((u) => u.id), ['c', 'd']);
    });

    test('facets combine with AND', () async {
      final result = await run(const DiscoverQuery(
        department: 'Computer Science',
        year: '3rd Year',
        gender: 'Male',
        lookingFor: 'Study Partner',
        interests: ['Coding'],
      ));
      expect(result.map((u) => u.id), ['a']);
    });

    test('a combination nobody satisfies is empty', () async {
      final result = await run(const DiscoverQuery(
        department: 'Management',
        year: '4th Year',
      ));
      expect(result, isEmpty);
    });

    test('search and facets combine', () async {
      final result = await run(
          const DiscoverQuery(search: 'coding', department: 'Computer Science'));
      expect(result.map((u) => u.id), ['a', 'c']);
    });
  });

  group('presence', () {
    test('online only', () async {
      final result = await run(const DiscoverQuery(onlineOnly: true));
      // 'd' is online but hides their active status, so they must not be
      // filterable by it either — otherwise the switch leaks.
      expect(result.map((u) => u.id), ['b']);
    });

    test('recently active includes the last few hours', () async {
      final result = await run(const DiscoverQuery(recentlyActive: true));
      expect(result.map((u) => u.id), containsAll(['b', 'c']));
      expect(result.map((u) => u.id), isNot(contains('a')));
    });

    test('recently active is ordered by last seen', () async {
      final result = await run(const DiscoverQuery(recentlyActive: true));
      for (var i = 1; i < result.length; i++) {
        final earlier = result[i - 1].lastActive;
        final later = result[i].lastActive;
        // An unknown last-seen sorts last, so it may only follow another one.
        if (earlier == null) {
          expect(later, isNull);
          continue;
        }
        if (later == null) continue;
        expect(earlier.isAfter(later) || earlier == later, isTrue);
      }
    });
  });

  group('exclusions', () {
    test('excluded ids never appear', () async {
      final result = await run(const DiscoverQuery(excludeIds: {'a', 'c'}));
      expect(result.map((u) => u.id), ['b', 'd']);
    });

    test('exclusions apply before pagination, so pages stay full', () async {
      final page = await repo.fetchStudents(
        query: const DiscoverQuery(excludeIds: {'a'}),
        offset: 0,
        limit: 2,
      );
      expect(page.items.map((u) => u.id), ['b', 'c']);
      expect(page.hasMore, isTrue);
    });
  });

  group('fetchByPurpose', () {
    test('returns anyone with any of the purposes', () async {
      final result =
          await repo.fetchByPurpose(const ['Project Partner', 'Networking']);
      expect(result.map((u) => u.id), ['c', 'd']);
    });

    test('honours exclusions', () async {
      final result = await repo
          .fetchByPurpose(const ['Study Partner'], excludeIds: {'a'});
      expect(result.map((u) => u.id), ['c']);
    });

    test('an empty purpose list asks for nothing', () async {
      expect(await repo.fetchByPurpose(const []), isEmpty);
    });
  });

  group('DiscoverQuery', () {
    test('equal queries compare equal, which is what skips a refetch', () {
      const a = DiscoverQuery(search: 'x', interests: ['Coding']);
      const b = DiscoverQuery(search: 'x', interests: ['Coding']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a changed facet is a different query', () {
      const a = DiscoverQuery(department: 'Computer Science');
      const b = DiscoverQuery(department: 'AI & ML');
      expect(a, isNot(b));
    });

    test('counts only the advanced facets', () {
      expect(const DiscoverQuery(search: 'x').activeFacetCount, 0);
      expect(const DiscoverQuery(onlineOnly: true).activeFacetCount, 0);
      expect(
        const DiscoverQuery(
          department: 'Computer Science',
          gender: 'Male',
          interests: ['Coding'],
        ).activeFacetCount,
        3,
      );
    });

    test('parses the year label the pickers produce', () {
      expect(const DiscoverQuery(year: '1st Year').studyYear, 1);
      expect(const DiscoverQuery(year: '4th Year').studyYear, 4);
      expect(const DiscoverQuery().studyYear, isNull);
    });

    test('clearing facets leaves search and presence alone', () {
      const query = DiscoverQuery(
        search: 'aarav',
        department: 'Computer Science',
        onlineOnly: true,
      );
      final cleared = query.clearedFacets();

      expect(cleared.search, 'aarav');
      expect(cleared.onlineOnly, isTrue);
      expect(cleared.department, DiscoverQuery.any);
    });
  });
}

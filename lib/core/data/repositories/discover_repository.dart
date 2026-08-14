import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/discover_query.dart';
import '../../models/page_result.dart';
import '../../models/user_model.dart';
import '../profile_mapper.dart';

/// Reads for the Discover tab.
///
/// Separate from [ProfileRepository] because the questions are different
/// shapes: that one answers "give me this student", this one answers "give me
/// the next twenty students matching these facets". Merging them would give
/// one interface with two unrelated halves.
///
/// Every method is paginated. Discover used to hold all 120 generated students
/// in memory and re-filter them on each rebuild, which is fine at 120 and not
/// at a real campus.
abstract class DiscoverRepository {
  /// One page of students matching [query], skipping the first [offset].
  ///
  /// Never includes the signed-in student, and never includes anyone in
  /// `query.excludeIds`.
  Future<PageResult<User>> fetchStudents({
    required DiscoverQuery query,
    int offset = 0,
    int limit = kDiscoverPageSize,
  });

  /// Students who listed any of [purposes] in "looking for".
  ///
  /// Its own method rather than a [fetchStudents] call because the two
  /// "find a partner" tabs want a whole short list at once, not an infinite
  /// scroll — and because folding it into the paginated path would mean those
  /// tabs silently showing only the students Discover happened to have loaded.
  Future<List<User>> fetchByPurpose(
    List<String> purposes, {
    Set<String> excludeIds = const {},
    int limit = 60,
  });
}

/// Page size for the Discover list. One screen holds roughly six cards, so
/// twenty is three screens of runway before the next fetch is needed.
const int kDiscoverPageSize = 20;

/// "Recently active" means online, or seen inside this window.
const Duration kRecentlyActiveWindow = Duration(hours: 6);

// =====================================================================
// Supabase
// =====================================================================

class SupabaseDiscoverRepository implements DiscoverRepository {
  SupabaseDiscoverRepository(this._client);

  final SupabaseClient _client;

  /// Profile columns plus the relations a card renders. Presence is embedded
  /// so the online dot does not cost a second round trip per card.
  ///
  /// `!inner` is switched on only when presence is being filtered: an inner
  /// join would otherwise drop every student whose presence row has not been
  /// written yet, and `tg_handle_new_auth_user` creates it — but a row
  /// imported by other means might not have one.
  static String _select({required bool innerPresence}) => '''
    ${ProfileMapper.columns},
    profile_badges!profile_badges_profile_id_fkey(badges(label)),
    user_presence${innerPresence ? '!inner' : ''}(is_online, last_active)
  ''';

  @override
  Future<PageResult<User>> fetchStudents({
    required DiscoverQuery query,
    int offset = 0,
    int limit = kDiscoverPageSize,
  }) async {
    final rows = await _run(query, offset: offset, limit: limit);

    // One row more than asked for is how "is there another page" is answered
    // without a second COUNT query — which on a filtered profiles scan costs
    // as much as the page itself.
    final hasMore = rows.length > limit;
    final page = hasMore ? rows.sublist(0, limit) : rows;

    return PageResult(
      items: page.map(ProfileMapper.fromRow).toList(),
      hasMore: hasMore,
      nextOffset: offset + page.length,
    );
  }

  @override
  Future<List<User>> fetchByPurpose(
    List<String> purposes, {
    Set<String> excludeIds = const {},
    int limit = 60,
  }) async {
    if (purposes.isEmpty) return const [];

    var builder = _client
        .from('profiles')
        .select(_select(innerPresence: false))
        .eq('discoverable', true)
        // `overlaps` is `&&` on the text[] column, which is what
        // profiles_looking_for_gin indexes.
        .overlaps('looking_for', purposes);

    builder = _excludeSelf(builder);
    for (final id in excludeIds) {
      builder = builder.neq('id', id);
    }

    final rows = await builder
        .order('created_at', ascending: false)
        .order('id')
        .limit(limit);

    return rows.map(ProfileMapper.fromRow).toList();
  }

  Future<List<Map<String, dynamic>>> _run(
    DiscoverQuery query, {
    required int offset,
    required int limit,
  }) {
    final needsPresence = query.onlineOnly || query.recentlyActive;

    var builder = _client
        .from('profiles')
        .select(_select(innerPresence: needsPresence))
        // RLS already limits reads to this campus and hides blocked students
        // both ways; `discoverable` is the one thing it deliberately does not
        // enforce, because a connected student stays readable after opting
        // out of Discover.
        .eq('discoverable', true);

    builder = _excludeSelf(builder);

    for (final id in query.excludeIds) {
      builder = builder.neq('id', id);
    }

    if (query.department != DiscoverQuery.any) {
      builder = builder.eq('department', query.department);
    }

    // Year of study is derived, not stored. Translating the label back to an
    // admission year is what lets this hit profiles_discover_idx instead of
    // scanning and computing study_year() per row.
    final studyYear = query.studyYear;
    if (studyYear != null) {
      builder = builder.eq(
        'admission_year',
        ProfileMapper.admissionYearForStudyYear(studyYear),
      );
    }

    if (query.gender != DiscoverQuery.any) {
      builder = builder.eq('gender', query.gender);
    }

    if (query.lookingFor != DiscoverQuery.any) {
      builder = builder.contains('looking_for', [query.lookingFor]);
    }

    if (query.interests.isNotEmpty) {
      builder = builder.overlaps('interests', query.interests);
    }

    if (query.onlineOnly) {
      builder = builder.eq('user_presence.is_online', true);
    } else if (query.recentlyActive) {
      final cutoff = DateTime.now().toUtc().subtract(kRecentlyActiveWindow);
      builder = builder.gte(
        'user_presence.last_active',
        cutoff.toIso8601String(),
      );
    }

    if (query.hasSearch) {
      final filter = _searchFilter(query.search);
      if (filter != null) builder = builder.or(filter);
    }

    // A total order, so a row cannot appear on two pages or on neither.
    // `created_at desc` alone is not enough: two profiles created in the same
    // millisecond would tie, and the tie could break differently per request.
    return builder
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + limit);
  }

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _excludeSelf(
    PostgrestFilterBuilder<List<Map<String, dynamic>>> builder,
  ) {
    final me = _client.auth.currentUser?.id;
    return me == null ? builder : builder.neq('id', me);
  }

  /// Free-text search across the columns a student would actually type into.
  ///
  /// `ilike` on full_name is served by profiles_name_trgm_idx. department and
  /// course are low-cardinality and the campus row count is small, so their
  /// scan cost is not worth another index.
  ///
  /// Note the asymmetry with Mock Mode, which is documented rather than
  /// papered over: `interests` and `looking_for` are matched by exact array
  /// containment here (`cs`), because PostgREST cannot express a substring
  /// match against an array element. Typing "Coding" finds the interest;
  /// typing "cod" does not. Closing that gap needs `interests` folded into
  /// `profiles.search_vector`, which is a migration and out of scope here.
  static String? _searchFilter(String raw) {
    final term = _sanitise(raw);
    if (term.isEmpty) return null;

    return [
      'full_name.ilike.*$term*',
      'username.ilike.*$term*',
      'department.ilike.*$term*',
      'course.ilike.*$term*',
      'interests.cs.{"$term"}',
      'looking_for.cs.{"$term"}',
    ].join(',');
  }

  /// PostgREST's `or` grammar is comma and parenthesis delimited, and array
  /// literals are brace delimited. Anything the student types that collides
  /// with that would either break the filter or change its meaning, so it is
  /// stripped rather than escaped — there is no escape syntax to use.
  static String _sanitise(String value) =>
      value.trim().replaceAll(RegExp(r'[,()\{\}"\\*%]'), '').trim();
}

// =====================================================================
// Mock
// =====================================================================

/// Serves Discover from the generated fixtures, applying the same query
/// semantics the Supabase implementation applies in SQL.
///
/// The fixture list is injected rather than reached for directly, so this
/// stays a repository and `MockDataGenerator` stays a fixture.
class MockDiscoverRepository implements DiscoverRepository {
  MockDiscoverRepository({
    required List<User> Function() students,
    this.latency = const Duration(milliseconds: 350),
  }) : _students = students;

  final List<User> Function() _students;

  /// Kept short and configurable: it exists so the loading states are
  /// reachable by hand, and tests set it to zero.
  final Duration latency;

  @override
  Future<PageResult<User>> fetchStudents({
    required DiscoverQuery query,
    int offset = 0,
    int limit = kDiscoverPageSize,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    final matches = _apply(query);
    if (offset >= matches.length) {
      return PageResult<User>(items: const [], hasMore: false, nextOffset: offset);
    }

    final end = (offset + limit).clamp(0, matches.length);
    final page = matches.sublist(offset, end);

    return PageResult(
      items: page,
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
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (purposes.isEmpty) return const [];

    return _students()
        .where((s) => !excludeIds.contains(s.id))
        .where((s) => s.lookingFor.any(purposes.contains))
        .take(limit)
        .toList();
  }

  List<User> _apply(DiscoverQuery query) {
    Iterable<User> result =
        _students().where((s) => !query.excludeIds.contains(s.id));

    if (query.hasSearch) {
      final q = query.search.toLowerCase();
      result = result.where((s) =>
          s.name.toLowerCase().contains(q) ||
          s.username.toLowerCase().contains(q) ||
          s.department.toLowerCase().contains(q) ||
          s.course.toLowerCase().contains(q) ||
          s.year.toLowerCase().contains(q) ||
          s.interests.any((i) => i.toLowerCase().contains(q)) ||
          s.lookingFor.any((l) => l.toLowerCase().contains(q)));
    }

    if (query.department != DiscoverQuery.any) {
      result = result.where((s) => s.department == query.department);
    }
    if (query.year != DiscoverQuery.any) {
      result = result.where((s) => s.year == query.year);
    }
    if (query.gender != DiscoverQuery.any) {
      result = result.where((s) => s.gender == query.gender);
    }
    if (query.lookingFor != DiscoverQuery.any) {
      result = result.where((s) => s.lookingFor.contains(query.lookingFor));
    }
    if (query.interests.isNotEmpty) {
      // Overlap, matching `&&` on the Supabase side — any interest, not all.
      result = result.where((s) => s.interests.any(query.interests.contains));
    }

    if (query.onlineOnly) {
      result = result.where((s) => s.isOnline && !s.hideActiveStatus);
    } else if (query.recentlyActive) {
      final cutoff = DateTime.now().toUtc().subtract(kRecentlyActiveWindow);
      // A student with no last-seen at all is not evidence of recent activity,
      // so they are not "recently active". They used to pass this filter
      // because an absent timestamp was being read back as `now`.
      result = result.where((s) =>
          (s.isOnline || (s.lastActive?.toUtc().isAfter(cutoff) ?? false)) &&
          !s.hideActiveStatus);
    }

    final list = result.toList();
    if (query.recentlyActive || query.onlineOnly) {
      // Unknown sorts last, behind everyone with an actual timestamp.
      list.sort((a, b) {
        final sa = a.lastActive;
        final sb = b.lastActive;
        if (sa == null && sb == null) return 0;
        if (sa == null) return 1;
        if (sb == null) return -1;
        return sb.compareTo(sa);
      });
    }
    return list;
  }
}

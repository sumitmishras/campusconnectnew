import 'package:supabase_flutter/supabase_flutter.dart' hide User;

/// What can be bookmarked. Mirrors the `target_type` check on
/// `public.bookmarks`, which is polymorphic on purpose: four bookmark tables to
/// gain a foreign key is not a trade worth making.
class BookmarkTarget {
  const BookmarkTarget._();

  static const event = 'event';
  static const project = 'project';
  static const poll = 'poll';
  static const profile = 'profile';
  static const club = 'club';
  static const studyGroup = 'study_group';
}

/// One owner for `public.bookmarks`, shared by the Campus Hub (saved events)
/// and Discover (saved students), because it is one table.
abstract class BookmarkRepository {
  /// The ids this student has saved of one kind.
  Future<Set<String>> fetchIds(String targetType);

  Future<void> set({
    required String targetType,
    required String targetId,
    required bool saved,
  });
}

// =====================================================================
// Supabase
// =====================================================================

class SupabaseBookmarkRepository implements BookmarkRepository {
  SupabaseBookmarkRepository(this._client);

  final SupabaseClient _client;

  String get _me => _client.auth.currentUser?.id ?? '';

  @override
  Future<Set<String>> fetchIds(String targetType) async {
    final me = _me;
    if (me.isEmpty) return const {};

    final rows = await _client
        .from('bookmarks')
        .select('target_id')
        .eq('user_id', me)
        .eq('target_type', targetType)
        .order('created_at', ascending: false);

    return rows.map((r) => r['target_id'] as String).toSet();
  }

  @override
  Future<void> set({
    required String targetType,
    required String targetId,
    required bool saved,
  }) async {
    final me = _me;
    if (me.isEmpty) return;

    if (saved) {
      // The primary key is (user_id, target_type, target_id), so saving twice
      // is the same outcome as saving once.
      await _client.from('bookmarks').upsert({
        'user_id': me,
        'target_type': targetType,
        'target_id': targetId,
      });
      return;
    }

    await _client
        .from('bookmarks')
        .delete()
        .eq('user_id', me)
        .eq('target_type', targetType)
        .eq('target_id', targetId);
  }
}

// =====================================================================
// Mock
// =====================================================================

/// In-memory bookmarks, so saving works with no credentials. Survives for the
/// life of the process, which is as long as the mock session does.
class MockBookmarkRepository implements BookmarkRepository {
  final Map<String, Set<String>> _byType = {};

  @override
  Future<Set<String>> fetchIds(String targetType) async =>
      Set.of(_byType[targetType] ?? const {});

  @override
  Future<void> set({
    required String targetType,
    required String targetId,
    required bool saved,
  }) async {
    final ids = _byType.putIfAbsent(targetType, () => <String>{});
    if (saved) {
      ids.add(targetId);
    } else {
      ids.remove(targetId);
    }
  }
}

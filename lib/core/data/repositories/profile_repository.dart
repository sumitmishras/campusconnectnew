import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/user_model.dart';
import '../mock_profile_store.dart';
import '../profile_mapper.dart';

/// Everything the app does with `public.profiles`.
///
/// The point of the interface is that no screen and no provider ever holds a
/// `SupabaseClient` or a mock list. They hold this, and which implementation
/// is behind it was decided once at startup.
abstract class ProfileRepository {
  /// The signed-in student's own row, badges included.
  /// Null when there is no session or onboarding was never finished.
  Future<User?> fetchCurrent();

  /// Another student's profile. Null when they are blocked, deleted, on a
  /// different campus, or simply not there — RLS decides, and from the
  /// client's side those cases are indistinguishable on purpose.
  Future<User?> fetchById(String id);

  /// Applies a column-shaped patch (see [ProfileMapper.toUpdate]) and returns
  /// the row as the database left it — not as the caller hoped it would be.
  /// Triggers and grants can both change the outcome.
  Future<User> update(String id, Map<String, dynamic> patch);

  /// Marks the student online and stamps `last_active`. Cheap enough to call
  /// on every resume; see the note in 0002 about why presence is its own
  /// table rather than a column on `profiles`.
  Future<void> setPresence({required bool online});
}


// =====================================================================
// Supabase
// =====================================================================

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  /// The profile columns plus the two embedded relations the UI needs.
  /// Fetching badges and presence in the same request keeps opening a profile
  /// to one round trip instead of three.
  ///
  /// The `!profile_badges_profile_id_fkey` hint is required, not decorative:
  /// `profile_badges` has two foreign keys to `profiles` (`profile_id` and
  /// `awarded_by`, the moderator who granted it). Given the choice PostgREST
  /// refuses to guess and fails the whole request with "more than one
  /// relationship was found", so the constraint has to be named.
  static String get _select => '''
    ${ProfileMapper.columns},
    profile_badges!profile_badges_profile_id_fkey(badges(label)),
    user_presence(is_online, last_active)
  ''';

  @override
  Future<User?> fetchCurrent() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return null;

    final row = await _client
        .from('profiles')
        .select(_select)
        .eq('id', id)
        .maybeSingle();

    if (row == null || row['onboarding_completed_at'] == null) return null;
    return ProfileMapper.fromRow(row);
  }

  @override
  Future<User?> fetchById(String id) async {
    final row = await _client
        .from('profiles')
        .select(_select)
        .eq('id', id)
        .maybeSingle();

    return row == null ? null : ProfileMapper.fromRow(row);
  }

  @override
  Future<User> update(String id, Map<String, dynamic> patch) async {
    final row = await _client
        .from('profiles')
        .update(patch)
        .eq('id', id)
        .select(_select)
        .single();

    return ProfileMapper.fromRow(row);
  }

  @override
  Future<void> setPresence({required bool online}) async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return;

    // UPDATE rather than upsert: `tg_handle_new_auth_user` creates the
    // presence row in the same transaction as the profile, so it always
    // exists, and `user_presence` has no INSERT policy by design.
    await _client.from('user_presence').update({
      'is_online': online,
      'last_active': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', id);
  }
}


// =====================================================================
// Mock
// =====================================================================

/// Serves the on-device profile and the generated students, so the app still
/// runs with no credentials.
///
/// The generated list is injected rather than reached for directly, which
/// keeps `MockDataGenerator` a fixture and keeps this a repository.
class MockProfileRepository implements ProfileRepository {
  MockProfileRepository({
    required MockProfileStore store,
    required List<User> Function() students,
  })  : _store = store,
        _students = students;

  final MockProfileStore _store;
  final List<User> Function() _students;

  @override
  Future<User?> fetchCurrent() => _store.read();

  @override
  Future<User?> fetchById(String id) async {
    final me = await _store.read();
    if (me != null && me.id == id) return me;
    for (final s in _students()) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<User> update(String id, Map<String, dynamic> patch) async {
    final current = await _store.read();
    if (current == null) {
      throw StateError('No signed-in student to update');
    }
    final updated = ProfileMapper.applyPatch(current, patch);
    await _store.write(updated);
    return updated;
  }

  @override
  Future<void> setPresence({required bool online}) async {
    // Nothing to persist offline; the mock student is always "online".
  }
}

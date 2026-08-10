import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../reference_data.dart';

/// Where the picker option lists come from.
///
/// `programs` holds one row per programme code, several of which share a
/// department, so departments are the distinct set. `tags` is the canonical
/// vocabulary for interests / languages / "looking for" — the reason it
/// exists is stated in `0002_identity_and_profiles.sql`: without it the tag
/// list turns into four thousand spellings of "photography".
abstract class ReferenceRepository {
  Future<ReferenceOptions> fetch();
}

// =====================================================================
// Supabase
// =====================================================================

class SupabaseReferenceRepository implements ReferenceRepository {
  SupabaseReferenceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ReferenceOptions> fetch() async {
    // Two round trips at startup, in parallel. Both tables are tiny and read
    // by every signed-in student, so Postgres keeps them in cache.
    final results = await Future.wait([
      _client.from('programs').select('department').eq('is_active', true),
      _client
          .from('tags')
          .select('label, category')
          .eq('is_active', true)
          .order('usage_count', ascending: false)
          .order('label'),
    ]);

    final departments = <String>{};
    for (final row in results[0]) {
      final value = row['department'] as String?;
      if (value != null && value.isNotEmpty) departments.add(value);
    }

    final interests = <String>[];
    final languages = <String>[];
    final purposes = <String>[];
    for (final row in results[1]) {
      final label = row['label'] as String?;
      if (label == null || label.isEmpty) continue;
      switch (row['category'] as String?) {
        case 'interest':
          interests.add(label);
        case 'language':
          languages.add(label);
        case 'looking_for':
          purposes.add(label);
      }
    }

    final sortedDepartments = departments.toList()..sort();

    return ReferenceOptions(
      departments: sortedDepartments,
      years: ReferenceOptions.defaultYears,
      interests: interests,
      languages: languages,
      purposes: purposes,
    );
  }
}

// =====================================================================
// Mock
// =====================================================================

/// Serves the built-in lists, so the pickers work with no credentials.
class MockReferenceRepository implements ReferenceRepository {
  const MockReferenceRepository();

  @override
  Future<ReferenceOptions> fetch() async => ReferenceOptions.fallback;
}

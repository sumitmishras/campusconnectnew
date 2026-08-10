import 'package:flutter/foundation.dart';

/// Everything that narrows the Discover list, in one value.
///
/// It is a value object with real equality on purpose: the provider compares
/// the query it is about to run against the one already on screen and skips
/// the round trip when nothing changed. That is what stops a filter sheet
/// being re-applied, or a debounced keystroke that landed back on the same
/// text, from refetching.
///
/// The facets are stored the way the UI holds them — `'Any'` for "no
/// preference", `'3rd Year'` rather than an admission year — and each
/// repository translates. Keeping the translation on the repository side is
/// what lets the Supabase implementation hit `profiles.admission_year`, which
/// is the indexed column, while the mock compares labels.
@immutable
class DiscoverQuery {
  /// Sentinel for "this facet is not applied".
  static const String any = 'Any';

  /// Free text typed into the search box.
  final String search;

  final String department;
  final String year;
  final String gender;
  final String lookingFor;

  /// Matches a student who has *any* of these (array overlap), not all of
  /// them. Requiring all of them empties the list almost immediately.
  final List<String> interests;

  final bool onlineOnly;

  /// Online, or seen within the last few hours.
  final bool recentlyActive;

  /// Students to leave out regardless of the facets: the signed-in student
  /// and anyone they have blocked. Supabase enforces both through RLS as
  /// well; this keeps Mock Mode honest and saves a round trip either way.
  final Set<String> excludeIds;

  const DiscoverQuery({
    this.search = '',
    this.department = any,
    this.year = any,
    this.gender = any,
    this.lookingFor = any,
    this.interests = const [],
    this.onlineOnly = false,
    this.recentlyActive = false,
    this.excludeIds = const {},
  });

  /// How many advanced facets are set. Drives the dot on the filter button and
  /// the "N filters applied" row — quick filters and search are shown
  /// elsewhere, so they are deliberately not counted.
  int get activeFacetCount {
    var n = 0;
    if (department != any) n++;
    if (year != any) n++;
    if (gender != any) n++;
    if (lookingFor != any) n++;
    if (interests.isNotEmpty) n++;
    return n;
  }

  bool get hasSearch => search.isNotEmpty;

  /// Year of study as a number, or null when the facet is off or unparseable.
  /// `'3rd Year'` → 3.
  int? get studyYear {
    if (year == any || year.isEmpty) return null;
    final match = RegExp(r'^(\d)').firstMatch(year);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  DiscoverQuery copyWith({
    String? search,
    String? department,
    String? year,
    String? gender,
    String? lookingFor,
    List<String>? interests,
    bool? onlineOnly,
    bool? recentlyActive,
    Set<String>? excludeIds,
  }) {
    return DiscoverQuery(
      search: search ?? this.search,
      department: department ?? this.department,
      year: year ?? this.year,
      gender: gender ?? this.gender,
      lookingFor: lookingFor ?? this.lookingFor,
      interests: interests ?? this.interests,
      onlineOnly: onlineOnly ?? this.onlineOnly,
      recentlyActive: recentlyActive ?? this.recentlyActive,
      excludeIds: excludeIds ?? this.excludeIds,
    );
  }

  /// Clears the advanced facets, leaving search and the quick filter alone —
  /// which is exactly what the "Clear" / "Reset" affordances promise.
  DiscoverQuery clearedFacets() => copyWith(
        department: any,
        year: any,
        gender: any,
        lookingFor: any,
        interests: const [],
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiscoverQuery &&
        other.search == search &&
        other.department == department &&
        other.year == year &&
        other.gender == gender &&
        other.lookingFor == lookingFor &&
        listEquals(other.interests, interests) &&
        other.onlineOnly == onlineOnly &&
        other.recentlyActive == recentlyActive &&
        setEquals(other.excludeIds, excludeIds);
  }

  @override
  int get hashCode => Object.hash(
        search,
        department,
        year,
        gender,
        lookingFor,
        Object.hashAll(interests),
        onlineOnly,
        recentlyActive,
        Object.hashAllUnordered(excludeIds),
      );

  @override
  String toString() => 'DiscoverQuery(search: "$search", department: $department, '
      'year: $year, gender: $gender, lookingFor: $lookingFor, '
      'interests: $interests, onlineOnly: $onlineOnly, '
      'recentlyActive: $recentlyActive, excluded: ${excludeIds.length})';
}

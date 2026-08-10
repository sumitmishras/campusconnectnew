/// The option lists the pickers render: departments, years of study,
/// interests, languages and "looking for" purposes.
///
/// These are reference data, not mock data — the registration wizard, the
/// Discover filter sheet and the profile editor all need them before any
/// student row exists. In Supabase mode they come from `public.programs` and
/// `public.tags` (seeded by `0011_seed_reference_data.sql`); with no
/// credentials, or before the first fetch lands, [ReferenceOptions.fallback]
/// is used so a picker is never empty.
class ReferenceOptions {
  final List<String> departments;
  final List<String> years;
  final List<String> interests;
  final List<String> languages;
  final List<String> purposes;

  const ReferenceOptions({
    required this.departments,
    required this.years,
    required this.interests,
    required this.languages,
    required this.purposes,
  });

  /// Year of study is derived from `admission_year` (see
  /// `ProfileMapper.studyYearLabel`), so it is a fixed list rather than a
  /// table — there is nothing to look up.
  static const defaultYears = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

  static const defaultDepartments = [
    'Computer Science',
    'AI & ML',
    'Information Technology',
    'Management',
    'Computer Applications',
    'Mechanical',
    'Civil',
    'Electrical',
  ];

  static const defaultInterests = [
    'Coding',
    'Dance',
    'Photography',
    'Music',
    'Gaming',
    'Football',
    'Cricket',
    'Startups',
    'Travel',
    'Fitness',
    'Reading',
    'Anime',
    'Debate',
    'Robotics',
  ];

  static const defaultLanguages = [
    'English',
    'Hindi',
    'Punjabi',
    'Telugu',
    'Tamil',
    'Marathi',
    'Bengali',
  ];

  static const defaultPurposes = [
    'Friendship',
    'Study Partner',
    'Coffee Chat',
    'Gym Partner',
    'Gaming Partner',
    'Project Partner',
    'Startup Co-founder',
    'Networking',
  ];

  static const fallback = ReferenceOptions(
    departments: defaultDepartments,
    years: defaultYears,
    interests: defaultInterests,
    languages: defaultLanguages,
    purposes: defaultPurposes,
  );

  /// Empty lists fall back rather than rendering a picker with nothing in it —
  /// a campus whose `tags` table was never seeded should still be usable.
  ReferenceOptions orFallback() => ReferenceOptions(
        departments: departments.isEmpty ? defaultDepartments : departments,
        years: years.isEmpty ? defaultYears : years,
        interests: interests.isEmpty ? defaultInterests : interests,
        languages: languages.isEmpty ? defaultLanguages : languages,
        purposes: purposes.isEmpty ? defaultPurposes : purposes,
      );
}

/// Process-wide cache for [ReferenceOptions].
///
/// Read synchronously from `build()` on purpose: these lists change about once
/// a semester, so making every picker await a future would cost a frame and
/// buy nothing. [load] is called once at startup and again after sign-in.
class ReferenceData {
  const ReferenceData._();

  static ReferenceOptions _current = ReferenceOptions.fallback;
  static bool _loaded = false;

  static ReferenceOptions get current => _current;

  static List<String> get departments => _current.departments;
  static List<String> get years => _current.years;
  static List<String> get interests => _current.interests;
  static List<String> get languages => _current.languages;
  static List<String> get purposes => _current.purposes;

  /// Fetches once and keeps the result. A failure leaves the fallback in
  /// place: an unreachable `tags` table should not stop a student editing
  /// their profile.
  static Future<void> load(Future<ReferenceOptions> Function() fetch) async {
    if (_loaded) return;
    try {
      _current = (await fetch()).orFallback();
      _loaded = true;
    } catch (_) {
      // Keep the fallback and allow a later attempt.
    }
  }

  static void reset() {
    _current = ReferenceOptions.fallback;
    _loaded = false;
  }
}

import '../models/user_model.dart';

/// Translates a `public.profiles` row into the [User] the UI already speaks.
///
/// The column names differ from the model's field names in a few places
/// (`full_name`, `university_uid`, `avatar_url`, `looking_for`) because the
/// schema follows Postgres convention and the model follows Dart's. Doing the
/// renaming in one place keeps that difference from leaking into every screen.
class ProfileMapper {
  const ProfileMapper._();

  /// Columns to request from PostgREST. Listing them explicitly rather than
  /// using `*` means adding a column to the table cannot silently change what
  /// the app downloads on every profile fetch.
  static const columns = '''
    id, full_name, username, email, university_uid, phone_e164, gender,
    department, course, admission_year, bio, campus_status, avatar_url,
    interests, languages, looking_for, trust_level, verification_level,
    hide_department, hide_year, hide_looking_for, hide_active_status,
    discoverable, allow_dm_from_anyone, onboarding_completed_at
  ''';

  /// `presence` overrides the embedded `user_presence` relation when the
  /// caller fetched it separately; normally it comes in with the row.
  static User fromRow(Map<String, dynamic> row, {Map<String, dynamic>? presence}) {
    final hideActive = row['hide_active_status'] as bool? ?? false;
    final live = presence ?? _embeddedPresence(row['user_presence']);

    return User(
      badges: _embeddedBadges(row['profile_badges']),
      id: row['id'] as String,
      name: row['full_name'] as String? ?? '',
      username: row['username'] as String? ?? '',
      email: row['email'] as String? ?? '',
      // The model shows the id the way it is printed on the ID card.
      uid: (row['university_uid'] as String? ?? '').toUpperCase(),
      phoneNumber: row['phone_e164'] as String? ?? '',
      gender: row['gender'] as String? ?? 'Prefer not to say',
      department: row['department'] as String? ?? '',
      course: row['course'] as String? ?? '',
      year: studyYearLabel(row['admission_year'] as int?),
      bio: row['bio'] as String? ?? '',
      interests: _stringList(row['interests']),
      languages: _stringList(row['languages']),
      lookingFor: _stringList(row['looking_for']),
      profilePhotoUrl: row['avatar_url'] as String? ?? '',
      trustLevel: TrustLevelWire.parse(row['trust_level']),
      verificationLevel: VerificationLevelWire.parse(row['verification_level']),
      // The privacy switch wins over whatever presence reports, so it cannot
      // leak through the embedded relation.
      isOnline: hideActive ? false : (live?['is_online'] as bool? ?? false),
      lastActive: _parseDate(live?['last_active']) ?? DateTime.now(),
      campusStatus: row['campus_status'] as String?,
      hideDepartment: row['hide_department'] as bool? ?? false,
      hideYear: row['hide_year'] as bool? ?? false,
      hideLookingFor: row['hide_looking_for'] as bool? ?? false,
      hideActiveStatus: hideActive,
    );
  }

  /// The columns a profile edit is allowed to write. Anything outside this set
  /// is rejected by the column-level grants in `0008_rls_policies.sql`, so
  /// sending it would fail the whole UPDATE rather than be ignored.
  static Map<String, dynamic> toUpdate({
    String? name,
    String? username,
    String? gender,
    String? bio,
    String? campusStatus,
    String? avatarUrl,
    List<String>? interests,
    List<String>? languages,
    List<String>? lookingFor,
    bool? hideDepartment,
    bool? hideYear,
    bool? hideLookingFor,
    bool? hideActiveStatus,
    bool? discoverable,
    bool? allowDmFromAnyone,
    bool markOnboarded = false,
  }) {
    return <String, dynamic>{
      'full_name': ?name,
      if (username != null) 'username': username.toLowerCase(),
      'gender': ?gender,
      'bio': ?bio,
      'campus_status': ?campusStatus,
      'avatar_url': ?avatarUrl,
      'interests': ?interests,
      'languages': ?languages,
      'looking_for': ?lookingFor,
      'hide_department': ?hideDepartment,
      'hide_year': ?hideYear,
      'hide_looking_for': ?hideLookingFor,
      'hide_active_status': ?hideActiveStatus,
      'discoverable': ?discoverable,
      'allow_dm_from_anyone': ?allowDmFromAnyone,
      if (markOnboarded) 'onboarding_completed_at': DateTime.now().toIso8601String(),
    };
  }

  /// Mirrors `public.study_year()` and `CuIdentity.yearOfStudy`: the academic
  /// session rolls over in July, and the result is clamped to 1..4.
  ///
  /// Derived rather than stored, on both sides, because it changes every July
  /// without anyone editing the row.
  static String studyYearLabel(int? admissionYear, {DateTime? now}) {
    if (admissionYear == null) return '';
    final at = now ?? DateTime.now();
    var elapsed = at.year - admissionYear + (at.month >= 7 ? 1 : 0);
    if (elapsed < 1) elapsed = 1;
    if (elapsed > 4) elapsed = 4;
    const suffixes = {1: 'st', 2: 'nd', 3: 'rd', 4: 'th'};
    return '$elapsed${suffixes[elapsed]} Year';
  }

  /// Inverse of [studyYearLabel], matching
  /// `public.admission_year_for_study_year()`. Discover filters by year, and
  /// only `admission_year` is indexed — so the label has to become a year
  /// before it reaches the query.
  static int admissionYearForStudyYear(int studyYear, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return at.year - studyYear + (at.month >= 7 ? 1 : 0);
  }

  /// Applies a column-shaped patch to a [User] in memory.
  ///
  /// Only Mock Mode needs this — with Supabase the database returns the new
  /// row and there is nothing to simulate. Keeping it beside [toUpdate] means
  /// the two stay in step: a column added to one has an obvious home in the
  /// other.
  static User applyPatch(User current, Map<String, dynamic> patch) {
    return current.copyWith(
      name: patch['full_name'] as String?,
      username: patch['username'] as String?,
      gender: patch['gender'] as String?,
      bio: patch['bio'] as String?,
      campusStatus: patch['campus_status'] as String?,
      profilePhotoUrl: patch['avatar_url'] as String?,
      interests: (patch['interests'] as List?)?.cast<String>(),
      languages: (patch['languages'] as List?)?.cast<String>(),
      lookingFor: (patch['looking_for'] as List?)?.cast<String>(),
      hideDepartment: patch['hide_department'] as bool?,
      hideYear: patch['hide_year'] as bool?,
      hideLookingFor: patch['hide_looking_for'] as bool?,
      hideActiveStatus: patch['hide_active_status'] as bool?,
    );
  }

  /// PostgREST returns `profile_badges(badges(label))` as a list of wrappers:
  /// `[{badges: {label: 'Moderator'}}]`. The UI wants the labels.
  static List<String> _embeddedBadges(Object? value) {
    if (value is! List) return const [];
    final labels = <String>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final badge = entry['badges'];
      if (badge is Map && badge['label'] != null) {
        labels.add(badge['label'].toString());
      }
    }
    return labels;
  }

  /// `user_presence` is one-to-one, so PostgREST usually embeds it as an
  /// object — but it emits a list when it cannot prove the relation is unique.
  /// Accept both rather than depending on which side it picks.
  static Map<String, dynamic>? _embeddedPresence(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  static List<String> _stringList(Object? value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

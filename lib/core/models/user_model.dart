enum TrustLevel { trusted, newVerified, limited, restricted, suspended }
enum VerificationLevel { none, phone, email, studentId, ambassador, clubRep }

// `ConnectionStatus` used to live here and was never referenced. It now lives
// in `connection_model.dart`, beside the row it is derived from, and carries
// the two cases this version was missing: which side sent the request, and
// whether the student is blocked.

/// Postgres enums travel as text, and ordinals are not stable — inserting a
/// value into the middle of `public.trust_level` would silently reinterpret
/// every stored row. So these serialise by name, matching the enum labels in
/// `supabase/migrations/0001_extensions_and_types.sql` exactly.
extension TrustLevelWire on TrustLevel {
  static const _names = {
    TrustLevel.trusted: 'trusted',
    TrustLevel.newVerified: 'new_verified',
    TrustLevel.limited: 'limited',
    TrustLevel.restricted: 'restricted',
    TrustLevel.suspended: 'suspended',
  };

  String get wire => _names[this]!;

  static TrustLevel parse(Object? value, {TrustLevel fallback = TrustLevel.newVerified}) {
    if (value is TrustLevel) return value;
    if (value is String) {
      for (final entry in _names.entries) {
        if (entry.value == value) return entry.key;
      }
    }
    // Tolerate the old ordinal encoding so a cached profile written by a
    // previous build still loads instead of throwing on startup.
    if (value is int && value >= 0 && value < TrustLevel.values.length) {
      return TrustLevel.values[value];
    }
    return fallback;
  }
}

extension VerificationLevelWire on VerificationLevel {
  static const _names = {
    VerificationLevel.none: 'none',
    VerificationLevel.phone: 'phone',
    VerificationLevel.email: 'email',
    VerificationLevel.studentId: 'student_id',
    VerificationLevel.ambassador: 'ambassador',
    VerificationLevel.clubRep: 'club_rep',
  };

  String get wire => _names[this]!;

  static VerificationLevel parse(Object? value,
      {VerificationLevel fallback = VerificationLevel.none}) {
    if (value is VerificationLevel) return value;
    if (value is String) {
      for (final entry in _names.entries) {
        if (entry.value == value) return entry.key;
      }
    }
    if (value is int && value >= 0 && value < VerificationLevel.values.length) {
      return VerificationLevel.values[value];
    }
    return fallback;
  }
}

class User {
  final String id;
  final String name;
  final String username;
  final String email;
  final String uid; // CU University ID, e.g. 21BCS5084
  final String phoneNumber;
  final String gender;
  final String department;
  final String course;
  final String year;
  final String bio;
  final List<String> interests;
  final List<String> languages;
  final List<String> lookingFor;
  final String profilePhotoUrl;

  final TrustLevel trustLevel;
  final VerificationLevel verificationLevel;
  final List<String> badges;
  final List<String> achievements;

  final bool isOnline;
  final DateTime lastActive;
  final String? campusStatus;

  // Privacy
  final bool hideDepartment;
  final bool hideYear;
  final bool hideLookingFor;
  final bool hideActiveStatus;

  User({
    required this.id,
    required this.name,
    required this.username,
    this.email = '',
    this.uid = '',
    required this.phoneNumber,
    this.gender = 'Prefer not to say',
    required this.department,
    required this.course,
    required this.year,
    required this.bio,
    required this.interests,
    required this.languages,
    required this.lookingFor,
    required this.profilePhotoUrl,
    this.trustLevel = TrustLevel.newVerified,
    this.verificationLevel = VerificationLevel.phone,
    this.badges = const [],
    this.achievements = const [],
    this.isOnline = false,
    required this.lastActive,
    this.campusStatus,
    this.hideDepartment = false,
    this.hideYear = false,
    this.hideLookingFor = false,
    this.hideActiveStatus = false,
  });

  bool get isVerified => verificationLevel != VerificationLevel.none;

  /// Short label for the highest verification the student holds.
  String get verificationLabel {
    switch (verificationLevel) {
      case VerificationLevel.none:
        return 'Unverified';
      case VerificationLevel.phone:
        return 'Phone Verified';
      case VerificationLevel.email:
        return 'CU Email Verified';
      case VerificationLevel.studentId:
        return 'Student ID Verified';
      case VerificationLevel.ambassador:
        return 'Campus Ambassador';
      case VerificationLevel.clubRep:
        return 'Club Representative';
    }
  }

  String get trustLabel {
    switch (trustLevel) {
      case TrustLevel.trusted:
        return 'Trusted Member';
      case TrustLevel.newVerified:
        return 'Newly Verified';
      case TrustLevel.limited:
        return 'Limited Access';
      case TrustLevel.restricted:
        return 'Restricted';
      case TrustLevel.suspended:
        return 'Suspended';
    }
  }

  /// Human friendly "last seen" text, honouring the privacy toggle.
  String get lastActiveLabel {
    if (hideActiveStatus) return '';
    if (isOnline) return 'Online now';
    final diff = DateTime.now().difference(lastActive);
    if (diff.inMinutes < 1) return 'Active just now';
    if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
    return 'Active ${diff.inDays}d ago';
  }

  int get completionPercentage {
    int score = 0;
    if (profilePhotoUrl.isNotEmpty) score += 20;
    if (bio.isNotEmpty) score += 20;
    if (interests.isNotEmpty) score += 15;
    if (languages.isNotEmpty) score += 10;
    if (lookingFor.isNotEmpty) score += 15;
    if (department.isNotEmpty && course.isNotEmpty && year.isNotEmpty) score += 20;
    return score;
  }

  /// The first thing the student should add to push completion higher.
  String get nextCompletionHint {
    if (profilePhotoUrl.isEmpty) return 'Add a profile photo to reach 100%';
    if (bio.isEmpty) return 'Write a short bio to reach 100%';
    if (interests.isEmpty) return 'Add your interests to reach 100%';
    if (lookingFor.isEmpty) return 'Tell people what you are looking for';
    if (languages.isEmpty) return 'Add the languages you speak';
    if (department.isEmpty || course.isEmpty || year.isEmpty) {
      return 'Complete your academic details';
    }
    return 'Your profile looks great!';
  }

  User copyWith({
    String? name,
    String? username,
    String? email,
    String? uid,
    String? phoneNumber,
    String? gender,
    String? department,
    String? course,
    String? year,
    String? bio,
    List<String>? interests,
    List<String>? languages,
    List<String>? lookingFor,
    String? profilePhotoUrl,
    TrustLevel? trustLevel,
    VerificationLevel? verificationLevel,
    List<String>? badges,
    List<String>? achievements,
    bool? isOnline,
    DateTime? lastActive,
    String? campusStatus,
    bool? hideDepartment,
    bool? hideYear,
    bool? hideLookingFor,
    bool? hideActiveStatus,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      uid: uid ?? this.uid,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender,
      department: department ?? this.department,
      course: course ?? this.course,
      year: year ?? this.year,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      languages: languages ?? this.languages,
      lookingFor: lookingFor ?? this.lookingFor,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      trustLevel: trustLevel ?? this.trustLevel,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      badges: badges ?? this.badges,
      achievements: achievements ?? this.achievements,
      isOnline: isOnline ?? this.isOnline,
      lastActive: lastActive ?? this.lastActive,
      campusStatus: campusStatus ?? this.campusStatus,
      hideDepartment: hideDepartment ?? this.hideDepartment,
      hideYear: hideYear ?? this.hideYear,
      hideLookingFor: hideLookingFor ?? this.hideLookingFor,
      hideActiveStatus: hideActiveStatus ?? this.hideActiveStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'email': email,
        'uid': uid,
        'phoneNumber': phoneNumber,
        'gender': gender,
        'department': department,
        'course': course,
        'year': year,
        'bio': bio,
        'interests': interests,
        'languages': languages,
        'lookingFor': lookingFor,
        'profilePhotoUrl': profilePhotoUrl,
        'trustLevel': trustLevel.wire,
        'verificationLevel': verificationLevel.wire,
        'badges': badges,
        'achievements': achievements,
        'campusStatus': campusStatus,
        'hideDepartment': hideDepartment,
        'hideYear': hideYear,
        'hideLookingFor': hideLookingFor,
        'hideActiveStatus': hideActiveStatus,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        uid: json['uid'] as String? ?? '',
        phoneNumber: json['phoneNumber'] as String? ?? '',
        gender: json['gender'] as String? ?? 'Prefer not to say',
        department: json['department'] as String? ?? '',
        course: json['course'] as String? ?? '',
        year: json['year'] as String? ?? '',
        bio: json['bio'] as String? ?? '',
        interests: (json['interests'] as List?)?.cast<String>() ?? const [],
        languages: (json['languages'] as List?)?.cast<String>() ?? const [],
        lookingFor: (json['lookingFor'] as List?)?.cast<String>() ?? const [],
        profilePhotoUrl: json['profilePhotoUrl'] as String? ?? '',
        trustLevel: TrustLevelWire.parse(json['trustLevel']),
        verificationLevel: VerificationLevelWire.parse(
            json['verificationLevel'],
            fallback: VerificationLevel.email),
        badges: (json['badges'] as List?)?.cast<String>() ?? const [],
        achievements: (json['achievements'] as List?)?.cast<String>() ?? const [],
        isOnline: true,
        lastActive: DateTime.now(),
        campusStatus: json['campusStatus'] as String?,
        hideDepartment: json['hideDepartment'] as bool? ?? false,
        hideYear: json['hideYear'] as bool? ?? false,
        hideLookingFor: json['hideLookingFor'] as bool? ?? false,
        hideActiveStatus: json['hideActiveStatus'] as bool? ?? false,
      );
}

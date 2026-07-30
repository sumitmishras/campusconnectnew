import 'package:uuid/uuid.dart';

enum TrustLevel { trusted, newVerified, limited, restricted, suspended }
enum VerificationLevel { none, phone, email, studentId, ambassador, clubRep }
enum ConnectionStatus { none, pendingSent, pendingReceived, connected }

class User {
  final String id;
  final String name;
  final String username;
  final String phoneNumber;
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
    required this.phoneNumber,
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

  User copyWith({
    String? name,
    String? bio,
    List<String>? interests,
    List<String>? lookingFor,
    String? profilePhotoUrl,
    String? campusStatus,
    bool? hideDepartment,
    bool? hideYear,
    bool? hideLookingFor,
    bool? hideActiveStatus,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      username: username,
      phoneNumber: phoneNumber,
      department: department,
      course: course,
      year: year,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      languages: languages,
      lookingFor: lookingFor ?? this.lookingFor,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      trustLevel: trustLevel,
      verificationLevel: verificationLevel,
      badges: badges,
      achievements: achievements,
      isOnline: isOnline,
      lastActive: lastActive,
      campusStatus: campusStatus ?? this.campusStatus,
      hideDepartment: hideDepartment ?? this.hideDepartment,
      hideYear: hideYear ?? this.hideYear,
      hideLookingFor: hideLookingFor ?? this.hideLookingFor,
      hideActiveStatus: hideActiveStatus ?? this.hideActiveStatus,
    );
  }
}

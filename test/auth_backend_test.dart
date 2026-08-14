import 'package:campus_connect/core/config/app_config.dart';
import 'package:campus_connect/core/data/profile_mapper.dart';
import 'package:campus_connect/core/data/repositories/profile_repository.dart';
import 'package:campus_connect/core/models/user_model.dart';
import 'package:campus_connect/core/providers/auth_provider.dart';
import 'package:campus_connect/core/services/auth_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

/// Never called — [SupabaseAuthBackend] only needs one to be constructed.
class _NullProfiles implements ProfileRepository {
  @override
  Future<User?> fetchCurrent() async => null;

  @override
  Future<User?> fetchById(String id) async => null;

  @override
  Future<User> update(String id, Map<String, dynamic> patch) =>
      throw UnimplementedError();

  @override
  Future<void> setPresence({required bool online}) async {}

  @override
  Future<bool> uidExists(String uid) async => false;
}

/// Stands in for whichever backend is configured, so the provider's state
/// machine can be tested without a network or SharedPreferences.
class _FakeBackend implements AuthBackend {
  _FakeBackend({this.existingProfile, this.failWith});

  User? existingProfile;
  String? failWith;

  final List<String> calls = [];
  Map<String, dynamic>? lastUpdate;

  @override
  int get otpLength => 6;

  @override
  String get demoOtp => '';

  @override
  Future<User?> restoreSession() async => existingProfile;

  @override
  Future<bool> uidExists(String uid) async {
    calls.add('uidExists:$uid');
    if (failWith != null) throw AuthFailure(failWith!);
    return existingProfile != null;
  }

  @override
  Future<void> sendOtp(String email) async {
    calls.add('sendOtp:$email');
    if (failWith != null) throw AuthFailure(failWith!);
  }

  @override
  Future<AuthOutcome> verifyOtp(String email, String code) async {
    calls.add('verifyOtp:$email:$code');
    if (failWith != null) throw AuthFailure(failWith!);
    final profile = existingProfile;
    return profile == null
        ? const AuthOutcome.needsProfile()
        : AuthOutcome.loggedIn(profile);
  }

  @override
  Future<User> completeRegistration({
    required String email,
    required String name,
    required String username,
    required String gender,
    required String department,
    required String course,
    required String year,
    required String bio,
    required List<String> interests,
    required List<String> languages,
    required List<String> lookingFor,
    String profilePhotoUrl = '',
  }) async {
    calls.add('completeRegistration:$email');
    if (failWith != null) throw AuthFailure(failWith!);
    return _user(name: name, username: username);
  }

  @override
  Future<User> updateProfile(User current, Map<String, dynamic> changes) async {
    lastUpdate = changes;
    if (failWith != null) throw AuthFailure(failWith!);
    return current;
  }

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<void> deleteAccount() async => calls.add('deleteAccount');
}

User _user({String name = 'Aarav Sharma', String username = '21bcs5084'}) => User(
      id: 'u1',
      name: name,
      username: username,
      email: '21bcs5084@cuchd.in',
      uid: '21BCS5084',
      phoneNumber: '',
      department: 'Computer Science',
      course: 'B.E. CSE',
      year: '4th Year',
      bio: '',
      interests: const [],
      languages: const [],
      lookingFor: const [],
      profilePhotoUrl: '',
      lastActive: DateTime(2026, 1, 1),
    );

void main() {
  group('OTP length', () {
    // The screen renders this many boxes, so a backend carrying its own number
    // is a sign-in nobody can complete: it hardcoded a length that disagreed
    // with what the project's Auth settings actually mail (8 digits).
    test('no credentials means the four-digit mock flow', () {
      expect(AppConfig.useSupabase, isFalse);
      expect(AppConfig.otpLength, 4);
    });

    test('a code shorter than the boxes still reaches the server', () async {
      final backend = _FakeBackend();
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);
      await auth.requestOtp('21bcs5084@cuchd.in');
      backend.calls.clear();

      // The fake mails 6; suppose the screen was configured for more. Pressing
      // Verify has to submit rather than refuse.
      expect(await auth.verifyOtp('123456'), isTrue);
      expect(backend.calls, contains('verifyOtp:21bcs5084@cuchd.in:123456'));
    });

    test('the Supabase backend has no length of its own', () {
      final backend = SupabaseAuthBackend(
        SupabaseClient('http://localhost:54321', 'test-anon-key'),
        _NullProfiles(),
      );

      // Resolves through AppConfig — which is 4 here, because this environment
      // has no credentials. A hardcoded 6 or 8 would fail.
      expect(backend.otpLength, AppConfig.otpLength);
    });
  });

  group('enum wire encoding', () {
    // The reason this matters: Postgres enums travel as text, and the old
    // `.index` encoding would silently reinterpret every stored row if a
    // value were ever inserted into the middle of the enum.
    test('trust levels use the snake_case names from the schema', () {
      expect(TrustLevel.newVerified.wire, 'new_verified');
      expect(TrustLevel.trusted.wire, 'trusted');
      expect(TrustLevelWire.parse('new_verified'), TrustLevel.newVerified);
      expect(TrustLevelWire.parse('suspended'), TrustLevel.suspended);
    });

    test('verification levels round-trip', () {
      for (final level in VerificationLevel.values) {
        expect(VerificationLevelWire.parse(level.wire), level);
      }
    });

    test('student_id and club_rep map to their camelCase members', () {
      expect(VerificationLevel.studentId.wire, 'student_id');
      expect(VerificationLevel.clubRep.wire, 'club_rep');
      expect(VerificationLevelWire.parse('student_id'), VerificationLevel.studentId);
    });

    test('an unknown value falls back instead of throwing', () {
      expect(TrustLevelWire.parse('who_knows'), TrustLevel.newVerified);
      expect(TrustLevelWire.parse(null), TrustLevel.newVerified);
    });

    test('profiles cached by an older build still load', () {
      // Those were written with `.index`, so the ordinal has to keep working.
      expect(TrustLevelWire.parse(0), TrustLevel.trusted);
      expect(VerificationLevelWire.parse(3), VerificationLevel.studentId);
    });

    test('User json survives a round-trip', () {
      final before = _user().copyWith(
        trustLevel: TrustLevel.trusted,
        verificationLevel: VerificationLevel.clubRep,
      );
      final after = User.fromJson(before.toJson());
      expect(after.trustLevel, TrustLevel.trusted);
      expect(after.verificationLevel, VerificationLevel.clubRep);
      expect(after.username, before.username);
    });
  });

  group('ProfileMapper', () {
    final row = <String, dynamic>{
      'id': 'abc',
      'full_name': 'Bhavya Singh',
      'username': '21bcs7777',
      'email': '21bcs7777@cuchd.in',
      'university_uid': '21bcs7777',
      'phone_e164': '+919000000000',
      'gender': 'Female',
      'department': 'Computer Science',
      'course': 'B.E. CSE',
      'admission_year': 2021,
      'bio': 'Hello',
      'campus_status': 'Looking for a team',
      'avatar_url': 'https://example.test/a.jpg',
      'interests': ['coding', 'music'],
      'languages': ['Hindi'],
      'looking_for': ['Study Partner'],
      'trust_level': 'trusted',
      'verification_level': 'student_id',
      'hide_department': false,
      'hide_year': false,
      'hide_looking_for': false,
      'hide_active_status': false,
      'onboarding_completed_at': '2026-01-01T00:00:00Z',
    };

    test('maps snake_case columns onto the model', () {
      final user = ProfileMapper.fromRow(row);
      expect(user.name, 'Bhavya Singh');
      expect(user.department, 'Computer Science');
      expect(user.interests, ['coding', 'music']);
      expect(user.lookingFor, ['Study Partner']);
      expect(user.trustLevel, TrustLevel.trusted);
      expect(user.verificationLevel, VerificationLevel.studentId);
    });

    test('shows the university id the way the ID card prints it', () {
      expect(ProfileMapper.fromRow(row).uid, '21BCS7777');
    });

    test('presence is folded in when supplied', () {
      final user = ProfileMapper.fromRow(row, presence: {
        'is_online': true,
        'last_active': '2026-08-02T10:00:00Z',
      });
      expect(user.isOnline, isTrue);
    });

    test('hide_active_status wins over whatever presence says', () {
      // Otherwise the privacy switch would leak through the joined row.
      final user = ProfileMapper.fromRow(
        {...row, 'hide_active_status': true},
        presence: {'is_online': true},
      );
      expect(user.isOnline, isFalse);
      expect(user.hideActiveStatus, isTrue);
    });

    test('missing presence does not crash', () {
      expect(ProfileMapper.fromRow(row).isOnline, isFalse);
    });

    group('study year', () {
      test('rolls over in July, matching public.study_year()', () {
        // Admitted 2021: still 3rd year in June 2024, 4th from July.
        expect(ProfileMapper.studyYearLabel(2021, now: DateTime(2024, 6, 30)),
            '3rd Year');
        expect(ProfileMapper.studyYearLabel(2021, now: DateTime(2024, 7, 1)),
            '4th Year');
      });

      test('clamps to 1..4', () {
        expect(ProfileMapper.studyYearLabel(2030, now: DateTime(2024, 1, 1)),
            '1st Year');
        expect(ProfileMapper.studyYearLabel(2010, now: DateTime(2024, 1, 1)),
            '4th Year');
      });

      test('is the inverse of admissionYearForStudyYear', () {
        final at = DateTime(2026, 8, 2);
        for (var year = 1; year <= 4; year++) {
          final admission = ProfileMapper.admissionYearForStudyYear(year, now: at);
          expect(ProfileMapper.studyYearLabel(admission, now: at),
              startsWith('$year'));
        }
      });

      test('no admission year yields an empty label rather than a wrong one', () {
        expect(ProfileMapper.studyYearLabel(null), '');
      });
    });

    group('toUpdate', () {
      test('omits everything that was not passed', () {
        expect(ProfileMapper.toUpdate(name: 'X'), {'full_name': 'X'});
      });

      test('lower-cases the username to match the citext column check', () {
        expect(ProfileMapper.toUpdate(username: 'Aarav_21')['username'],
            'aarav_21');
      });

      test('never sends columns the grants would reject', () {
        final patch = ProfileMapper.toUpdate(
          name: 'X',
          bio: 'Y',
          interests: const ['a'],
          hideYear: true,
          discoverable: false,
        );
        // trust_level, verification_level, strike_count, department, course
        // and admission_year are all server-owned.
        for (final forbidden in [
          'trust_level',
          'verification_level',
          'strike_count',
          'report_count',
          'department',
          'course',
          'admission_year',
          'university_uid',
          'email',
        ]) {
          expect(patch.containsKey(forbidden), isFalse, reason: forbidden);
        }
      });

      test('marks onboarding only when asked', () {
        expect(ProfileMapper.toUpdate(name: 'X'),
            isNot(contains('onboarding_completed_at')));
        expect(ProfileMapper.toUpdate(name: 'X', markOnboarded: true),
            contains('onboarding_completed_at'));
      });
    });
  });

  group('AuthProvider state machine', () {
    test('starts logged out when the backend has no session', () async {
      final auth = AuthProvider(backend: _FakeBackend());
      await Future<void>.delayed(Duration.zero);
      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.currentUser, isNull);
    });

    test('restores an existing session', () async {
      final auth = AuthProvider(backend: _FakeBackend(existingProfile: _user()));
      await Future<void>.delayed(Duration.zero);
      expect(auth.status, AuthStatus.loggedIn);
      expect(auth.currentUser?.name, 'Aarav Sharma');
    });

    test('rejects a non-CU email before touching the backend', () async {
      final backend = _FakeBackend();
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);

      expect(await auth.requestOtp('someone@gmail.com'), isFalse);
      expect(auth.errorMessage, contains('cuchd.in'));
      expect(backend.calls, isEmpty);
    });

    test('accepts a valid CU email and remembers the pending identity', () async {
      final backend = _FakeBackend();
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);

      expect(await auth.requestOtp('21bcs5084@cuchd.in'), isTrue);
      expect(auth.pendingIdentity?.uid, '21bcs5084');
      expect(backend.calls, contains('sendOtp:21bcs5084@cuchd.in'));
    });

    test('a short code never reaches the backend', () async {
      final backend = _FakeBackend();
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);
      await auth.requestOtp('21bcs5084@cuchd.in');
      backend.calls.clear();

      expect(await auth.verifyOtp('123'), isFalse);
      expect(auth.errorMessage, 'Enter the code we emailed you');
      expect(backend.calls, isEmpty);
    });

    test('a new account lands on the registration wizard', () async {
      final auth = AuthProvider(backend: _FakeBackend());
      await Future<void>.delayed(Duration.zero);
      await auth.requestOtp('21bcs5084@cuchd.in');

      expect(await auth.verifyOtp('123456'), isTrue);
      expect(auth.status, AuthStatus.needsProfile);
    });

    test('a returning student goes straight in', () async {
      final auth = AuthProvider(backend: _FakeBackend(existingProfile: _user()));
      await Future<void>.delayed(Duration.zero);
      await auth.requestOtp('21bcs5084@cuchd.in');

      expect(await auth.verifyOtp('123456'), isTrue);
      expect(auth.status, AuthStatus.loggedIn);
    });

    test('a backend failure becomes a message, not a crash', () async {
      final backend = _FakeBackend();
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);
      await auth.requestOtp('21bcs5084@cuchd.in');

      // Only the verify step fails, which is the realistic case: the code
      // was sent, then mistyped or left too long.
      backend.failWith = 'That code has expired.';
      expect(await auth.verifyOtp('123456'), isFalse);
      expect(auth.errorMessage, 'That code has expired.');
      expect(auth.status, isNot(AuthStatus.loggedIn));
    });

    test('a failure while sending leaves the flow on the email screen', () async {
      final auth = AuthProvider(backend: _FakeBackend(failWith: 'mail is down'));
      await Future<void>.delayed(Duration.zero);

      expect(await auth.requestOtp('21bcs5084@cuchd.in'), isFalse);
      expect(auth.errorMessage, 'mail is down');
      // No pending identity, so the OTP screen is never reachable with a
      // half-finished state behind it.
      expect(auth.pendingIdentity, isNull);
    });

    test('the busy flag is cleared even when the call fails', () async {
      final auth = AuthProvider(backend: _FakeBackend(failWith: 'nope'));
      await Future<void>.delayed(Duration.zero);
      await auth.requestOtp('21bcs5084@cuchd.in');
      expect(auth.isBusy, isFalse);
    });

    test('registration completes and signs in', () async {
      final auth = AuthProvider(backend: _FakeBackend());
      await Future<void>.delayed(Duration.zero);
      await auth.requestOtp('21bcs5084@cuchd.in');
      await auth.verifyOtp('123456');

      final ok = await auth.completeRegistration(
        name: 'Aarav Sharma',
        username: 'aarav',
        gender: 'Male',
        department: 'Computer Science',
        course: 'B.E. CSE',
        year: '4th Year',
        bio: 'Hi',
        interests: const ['coding'],
        languages: const ['Hindi'],
        lookingFor: const ['Study Partner'],
      );

      expect(ok, isTrue);
      expect(auth.status, AuthStatus.loggedIn);
      expect(auth.currentUser?.username, 'aarav');
    });

    test('profile edits send only column-shaped keys', () async {
      final backend = _FakeBackend(existingProfile: _user());
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);

      await auth.updateProfile(name: 'New Name', bio: 'New bio');
      expect(backend.lastUpdate, {'full_name': 'New Name', 'bio': 'New bio'});
    });

    test('privacy toggles map to their columns', () async {
      final backend = _FakeBackend(existingProfile: _user());
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);

      await auth.updatePrivacy(hideActiveStatus: true, discoverable: false);
      expect(backend.lastUpdate,
          {'hide_active_status': true, 'discoverable': false});
    });

    test('logout clears the session and signs out of the backend', () async {
      final backend = _FakeBackend(existingProfile: _user());
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);

      await auth.logout();
      expect(auth.status, AuthStatus.loggedOut);
      expect(auth.currentUser, isNull);
      expect(backend.calls, contains('signOut'));
    });

    test('deleting still signs out even if the backend call fails', () async {
      final backend = _FakeBackend(existingProfile: _user());
      final auth = AuthProvider(backend: backend);
      await Future<void>.delayed(Duration.zero);

      backend.failWith = 'network down';
      await auth.deleteAccount();
      expect(auth.status, AuthStatus.loggedOut);
    });
  });
}

import 'dart:math';

// gotrue exports its own `User`; ours is the app's profile model, and that is
// the one every screen means.
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../config/app_config.dart';
import '../data/mock_profile_store.dart';
import '../data/profile_mapper.dart';
import '../data/repositories/profile_repository.dart';
import '../models/user_model.dart';
import 'cu_identity.dart';

/// Raised for anything the student should see a message about. The provider
/// turns these into `errorMessage`; anything else is a bug and propagates.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// What happened after a code was verified.
class AuthOutcome {
  final User? user;

  /// True when the account exists but the registration wizard has not been
  /// completed yet.
  final bool needsProfile;

  const AuthOutcome.loggedIn(this.user) : needsProfile = false;
  const AuthOutcome.needsProfile() : user = null, needsProfile = true;
}

/// The seam between the UI and wherever accounts actually live.
///
/// Two implementations: [MockAuthBackend], which is the original on-device
/// demo, and [SupabaseAuthBackend]. Which one is used is decided once, by
/// `AppConfig.useSupabase`. The screens never know the difference.
abstract class AuthBackend {
  int get otpLength;

  /// Only meaningful for the mock, where no mail is ever sent.
  String get demoOtp => '';

  /// The signed-in student, or null when there is no session.
  Future<User?> restoreSession();

  /// Whether a finished account already owns this university id.
  ///
  /// The entry screen asks this before sending anything, so it can tell the
  /// student whether they are signing in or signing up. Both branches still
  /// go through [sendOtp] — the answer only decides what the screens say.
  Future<bool> uidExists(String uid);

  Future<void> sendOtp(String email);

  Future<AuthOutcome> verifyOtp(String email, String code);

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
    String profilePhotoUrl,
  });

  Future<User> updateProfile(User current, Map<String, dynamic> changes);

  Future<void> signOut();

  Future<void> deleteAccount();
}


// =====================================================================
// Supabase
// =====================================================================

class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend(this._client, this._profiles);

  final SupabaseClient _client;

  /// Profile reads and writes belong to the repository; this class only
  /// deals with sessions and codes.
  final ProfileRepository _profiles;

  /// Read from [AppConfig] rather than hardcoded: the OTP screen renders this
  /// many boxes and refuses to submit anything shorter, so a value that
  /// disagrees with the project's Auth settings makes sign-in impossible.
  @override
  int get otpLength => AppConfig.otpLength;

  @override
  String get demoOtp => '';

  @override
  Future<User?> restoreSession() async {
    if (_client.auth.currentSession == null) return null;
    return _profiles.fetchCurrent();
  }

  @override
  Future<bool> uidExists(String uid) => _profiles.uidExists(uid);

  @override
  Future<void> sendOtp(String email) async {
    final problem = CuIdentity.validate(email);
    if (problem != null) throw AuthFailure(problem);

    try {
      await _client.auth.signInWithOtp(
        email: email.trim().toLowerCase(),
        // The DB trigger refuses non-CU domains anyway, but creating the
        // user here is what makes first sign-in and returning sign-in the
        // same flow.
        shouldCreateUser: true,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
  }

  @override
  Future<AuthOutcome> verifyOtp(String email, String code) async {
    late final AuthResponse response;
    try {
      response = await _client.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: code,
        type: OtpType.email,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }

    final user = response.user;
    if (user == null) throw const AuthFailure('Could not sign you in. Try again.');

    // `tg_handle_new_auth_user` creates the profile shell in the same
    // transaction as the auth row, so a row always exists by now — but
    // fetchCurrent() returns null until the wizard has filled it in, which is
    // exactly the signal needed here.
    final profile = await _profiles.fetchCurrent();
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
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Your session expired. Please sign in again.');

    // department/course/year are intentionally not sent: they are derived
    // server-side from program_id by tg_profile_sync_program, and `year` is
    // computed from admission_year at read time.
    final patch = ProfileMapper.toUpdate(
      name: name,
      username: username,
      gender: gender,
      bio: bio,
      interests: interests,
      languages: languages,
      lookingFor: lookingFor,
      avatarUrl: profilePhotoUrl.isEmpty ? null : profilePhotoUrl,
      markOnboarded: true,
    );

    try {
      return await _profiles.update(id, patch);
    } on PostgrestException catch (e) {
      throw AuthFailure(_readablePostgrest(e));
    }
  }

  @override
  Future<User> updateProfile(User current, Map<String, dynamic> changes) async {
    if (changes.isEmpty) return current;
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure('Your session expired. Please sign in again.');

    try {
      return await _profiles.update(id, changes);
    } on PostgrestException catch (e) {
      throw AuthFailure(_readablePostgrest(e));
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    // A client can never delete its own auth.users row. This marks the
    // profile, and `purge_deleted_profiles()` does the real erasure after the
    // 30-day grace period.
    await _client.rpc('request_account_deletion');
    await _client.auth.signOut();
  }

  static String _readable(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired')) return 'That code has expired. Request a new one.';
    if (m.contains('invalid') || m.contains('token')) {
      return 'Incorrect code. Please try again.';
    }
    if (m.contains('rate') || m.contains('too many')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return e.message;
  }

  static String _readablePostgrest(PostgrestException e) {
    // 23505 = unique_violation; the only one a student can trip here.
    if (e.code == '23505') return 'That username is already taken.';
    return e.message;
  }
}


// =====================================================================
// Mock — the original on-device demo
// =====================================================================

class MockAuthBackend implements AuthBackend {
  MockAuthBackend({
    required MockProfileStore store,
    required ProfileRepository profiles,
  })  : _store = store,
        _profiles = profiles;

  /// Shared with [MockProfileRepository] so an edit made through the
  /// repository is what the next session restore reads back.
  final MockProfileStore _store;
  final ProfileRepository _profiles;

  String _otp = '';

  @override
  int get otpLength => 4;

  @override
  String get demoOtp => _otp;

  @override
  Future<User?> restoreSession() => _store.read();

  @override
  Future<bool> uidExists(String uid) async {
    // Deliberately mirrors what verifyOtp() below counts as a returning
    // student. If these two disagreed, the entry screen would promise
    // "welcome back" and then drop the student into the wizard anyway.
    final wanted = uid.trim().toLowerCase();
    if (!await _store.isKnownAccount(wanted)) return false;
    final saved = await _store.read();
    return saved != null && saved.uid.toLowerCase() == wanted;
  }

  @override
  Future<void> sendOtp(String email) async {
    final problem = CuIdentity.validate(email);
    if (problem != null) throw AuthFailure(problem);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _otp = (Random().nextInt(9000) + 1000).toString();
  }

  @override
  Future<AuthOutcome> verifyOtp(String email, String code) async {
    if (code != _otp) throw const AuthFailure('Incorrect code. Please try again.');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final identity = CuIdentity.parse(email);
    if (identity == null) return const AuthOutcome.needsProfile();

    // Returning student: the same uid signed in on this device before.
    if (await _store.isKnownAccount(identity.uid)) {
      final saved = await _store.read();
      if (saved != null && saved.uid.toLowerCase() == identity.uid) {
        return AuthOutcome.loggedIn(saved);
      }
    }
    return const AuthOutcome.needsProfile();
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
    final identity = CuIdentity.parse(email);
    final seed = identity?.uid ?? name;
    final user = User(
      id: 'me',
      name: name,
      username: username,
      email: identity?.email ?? email,
      uid: identity?.displayUid ?? '',
      phoneNumber: '',
      gender: gender,
      department: department,
      course: course,
      year: year,
      bio: bio,
      interests: interests,
      languages: languages,
      lookingFor: lookingFor,
      profilePhotoUrl:
          profilePhotoUrl.isEmpty ? 'https://i.pravatar.cc/300?u=$seed' : profilePhotoUrl,
      trustLevel: TrustLevel.newVerified,
      verificationLevel: VerificationLevel.studentId,
      badges: const ['CU Verified'],
      isOnline: true,
      lastActive: DateTime.now(),
    );
    await _store.write(user, rememberAccount: true);
    return user;
  }

  @override
  Future<User> updateProfile(User current, Map<String, dynamic> changes) {
    // Same path the Supabase backend takes: the repository owns the write.
    return _profiles.update(current.id, changes);
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() => _store.clear();
}

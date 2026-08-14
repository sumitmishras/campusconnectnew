import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/repositories.dart';
import '../data/profile_mapper.dart';
import '../models/user_model.dart';
import '../services/auth_backend.dart';
import '../services/cu_identity.dart';

enum AuthStatus { checking, loggedOut, needsProfile, loggedIn }

/// Authentication restricted to `@cuchd.in` addresses.
///
/// The provider owns the state machine and the error strings; where accounts
/// actually live is [AuthBackend]'s problem. With `--dart-define=SUPABASE_URL`
/// set this talks to Supabase Auth; without it, the original on-device demo
/// runs unchanged. Screens see the same API either way.
class AuthProvider with ChangeNotifier {
  AuthProvider({AuthBackend? backend, ProfileRepository? profiles})
      : _backend = backend ?? Repositories.authBackend,
        _profiles = profiles ?? Repositories.profiles {
    restoreSession();
  }

  final AuthBackend _backend;

  /// Used for the reads the auth flow does not cover: refreshing the profile
  /// after something elsewhere changed it, and presence.
  final ProfileRepository _profiles;

  User? _currentUser;
  CuIdentity? _pendingIdentity;
  AuthStatus _status = AuthStatus.checking;
  bool _isBusy = false;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  CuIdentity? get pendingIdentity => _pendingIdentity;
  AuthStatus get status => _status;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// How many boxes the OTP screen should render. Decided by
  /// `AppConfig.otpLength` — six against Supabase unless the project's Auth
  /// settings say otherwise, four for the mock flow.
  int get otpLength => _backend.otpLength;

  /// Empty against a real backend — there is nothing to reveal when the code
  /// went to an actual inbox.
  String get demoOtp => _backend.demoOtp;
  bool get showsDemoOtp => AppConfig.showsDemoOtp && _backend.demoOtp.isNotEmpty;

  Future<void> restoreSession() async {
    try {
      final user = await _backend.restoreSession();
      _currentUser = user;
      _status = user == null ? AuthStatus.loggedOut : AuthStatus.loggedIn;
      if (user != null) unawaited(setPresence(online: true));
    } catch (_) {
      _status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  /// Re-reads the profile from the source of truth.
  ///
  /// Needed because things other than [updateProfile] change the row —
  /// badges awarded, `trust_level` recomputed by its trigger after
  /// verification — and none of those come back through an update response.
  Future<void> refreshProfile() async {
    if (_status != AuthStatus.loggedIn) return;
    try {
      final fresh = await _profiles.fetchCurrent();
      if (fresh == null) return;
      _currentUser = fresh;
      notifyListeners();
    } catch (_) {
      // A failed refresh leaves the cached profile in place; the screen was
      // already usable before it was attempted.
    }
  }

  /// Stamps `user_presence`. Fire-and-forget by design — nothing in the UI
  /// should wait on a heartbeat, and a failed one is not worth a message.
  Future<void> setPresence({required bool online}) async {
    try {
      await _profiles.setPresence(online: online);
    } catch (_) {
      // Ignored on purpose.
    }
  }

  /// Step 0 — does a finished account already own this university id?
  ///
  /// Three outcomes, and the difference matters: `true` means greet a
  /// returning student, `false` means this is a sign-up, and `null` means the
  /// lookup itself did not answer.
  ///
  /// `null` is not folded into `false` on purpose. This lookup is **advisory**
  /// — both branches send a code either way, and the binding decision is still
  /// made by [verifyOtp], which reads the profile with a real session and
  /// returns `needsProfile`. So a failed lookup must not block sign-in; the
  /// screen just drops the personalised wording and carries on. Telling
  /// someone with an account that they need to register would be worse than
  /// saying nothing.
  ///
  /// This is also why the catch here is broader than [_guard]'s. Everywhere
  /// else a non-[AuthFailure] is a bug and should propagate; here it is
  /// usually a flaky network on the very first screen, and there is a correct
  /// thing to do with it.
  Future<bool?> uidExists(String input) async {
    _errorMessage = CuIdentity.validate(input);
    if (_errorMessage != null) {
      notifyListeners();
      return null;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _backend.uidExists(CuIdentity.parse(input)!.uid);
    } catch (_) {
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Step 1 — validate the CU email and send a code.
  /// Returns true when the caller should move on to the OTP screen.
  Future<bool> requestOtp(String email) async {
    _errorMessage = CuIdentity.validate(email);
    if (_errorMessage != null) {
      notifyListeners();
      return false;
    }

    return _guard(() async {
      await _backend.sendOtp(email);
      _pendingIdentity = CuIdentity.parse(email);
      return true;
    });
  }

  Future<void> resendOtp() async {
    final email = _pendingIdentity?.email;
    if (email == null) return;
    await _guard(() async {
      await _backend.sendOtp(email);
      return true;
    });
  }

  /// Step 2 — verify the code. Read [status] afterwards to decide between the
  /// registration wizard and the main app.
  Future<bool> verifyOtp(String code) async {
    // A floor, not an exact match. If `otpLength` ever disagrees with what the
    // project actually mails, the student can still submit and let the server
    // judge — rather than being told to "enter all N digits" for a code that
    // does not have N digits.
    final minimum = otpLength < AppConfig.minOtpLength
        ? otpLength
        : AppConfig.minOtpLength;
    if (code.length < minimum) {
      _errorMessage = 'Enter the code we emailed you';
      notifyListeners();
      return false;
    }
    final email = _pendingIdentity?.email;
    if (email == null) {
      _errorMessage = 'Start again — we lost track of your email.';
      notifyListeners();
      return false;
    }

    return _guard(() async {
      final outcome = await _backend.verifyOtp(email, code);
      if (outcome.needsProfile) {
        _status = AuthStatus.needsProfile;
      } else {
        _currentUser = outcome.user;
        _status = AuthStatus.loggedIn;
      }
      return true;
    });
  }

  /// Step 3 — the registration wizard hands the finished profile back here.
  Future<bool> completeRegistration({
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
  }) {
    return _guard(() async {
      _currentUser = await _backend.completeRegistration(
        email: _pendingIdentity?.email ?? _currentUser?.email ?? '',
        name: name,
        username: username,
        gender: gender,
        department: department,
        course: course,
        year: year,
        bio: bio,
        interests: interests,
        languages: languages,
        lookingFor: lookingFor,
        profilePhotoUrl: profilePhotoUrl,
      );
      _status = AuthStatus.loggedIn;
      return true;
    });
  }

  Future<bool> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? gender,
    String? campusStatus,
    List<String>? interests,
    List<String>? languages,
    List<String>? lookingFor,
    String? profilePhotoUrl,
  }) {
    final user = _currentUser;
    if (user == null) return Future.value(false);

    // department / course / year are derived from program_id server-side, so
    // they are not editable here even though the model carries them.
    return _guard(() async {
      _currentUser = await _backend.updateProfile(
        user,
        ProfileMapper.toUpdate(
          name: name,
          username: username,
          bio: bio,
          gender: gender,
          campusStatus: campusStatus,
          interests: interests,
          languages: languages,
          lookingFor: lookingFor,
          avatarUrl: profilePhotoUrl,
        ),
      );
      return true;
    });
  }

  Future<bool> updatePrivacy({
    bool? hideDepartment,
    bool? hideYear,
    bool? hideLookingFor,
    bool? hideActiveStatus,
    bool? discoverable,
    bool? allowDmFromAnyone,
  }) {
    final user = _currentUser;
    if (user == null) return Future.value(false);

    return _guard(() async {
      _currentUser = await _backend.updateProfile(
        user,
        ProfileMapper.toUpdate(
          hideDepartment: hideDepartment,
          hideYear: hideYear,
          hideLookingFor: hideLookingFor,
          hideActiveStatus: hideActiveStatus,
          discoverable: discoverable,
          allowDmFromAnyone: allowDmFromAnyone,
        ),
      );
      return true;
    });
  }

  Future<void> logout() async {
    await _backend.signOut();
    _currentUser = null;
    _pendingIdentity = null;
    _errorMessage = null;
    _status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    try {
      await _backend.deleteAccount();
    } catch (_) {
      // Deleting is best-effort from the client; signing out is not.
    }
    await logout();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Runs [action] with the busy flag set, turning [AuthFailure] into a
  /// message the UI can show and leaving anything else to surface as a crash —
  /// an unexpected exception is a bug, not something to swallow.
  Future<bool> _guard(Future<bool> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } on AuthFailure catch (e) {
      _errorMessage = e.message;
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}

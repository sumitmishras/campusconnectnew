import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

/// Where Mock Mode keeps the signed-in student between launches.
///
/// Both [MockAuthBackend] and [MockProfileRepository] read and write the
/// profile, and they must agree on it — a profile edit has to be visible to
/// the next session restore. Sharing one store instance is what guarantees
/// that; two copies of the same SharedPreferences logic would eventually
/// drift.
class MockProfileStore {
  static const _profileKey = 'cc_profile';
  static const _knownAccountsKey = 'cc_known_accounts';

  /// Deliberately not cached in memory. SharedPreferences is already an
  /// in-process map, so a second cache buys nothing and creates a way for the
  /// store to disagree with what was actually persisted — which showed up
  /// immediately as tests leaking a signed-in profile into the next one.
  Future<User?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileKey);
      if (raw == null) return null;
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A profile written by an incompatible older build should log the
      // student out, not crash the app on startup.
      return null;
    }
  }

  Future<void> write(User user, {bool rememberAccount = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(user.toJson()));

    if (rememberAccount && user.uid.isNotEmpty) {
      final known = prefs.getStringList(_knownAccountsKey) ?? <String>[];
      final uid = user.uid.toLowerCase();
      if (!known.contains(uid)) {
        known.add(uid);
        await prefs.setStringList(_knownAccountsKey, known);
      }
    }
  }

  Future<bool> isKnownAccount(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final known = prefs.getStringList(_knownAccountsKey) ?? <String>[];
    return known.contains(uid.toLowerCase());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileKey);
    await prefs.remove(_knownAccountsKey);
  }
}

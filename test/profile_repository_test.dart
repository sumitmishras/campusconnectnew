import 'package:campus_connect/core/data/mock_profile_store.dart';
import 'package:campus_connect/core/data/profile_mapper.dart';
import 'package:campus_connect/core/data/repositories/profile_repository.dart';
import 'package:campus_connect/core/data/repositories/repositories.dart';
import 'package:campus_connect/core/models/user_model.dart';
import 'package:campus_connect/core/providers/auth_provider.dart';
import 'package:campus_connect/core/services/auth_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

User _user({String id = 'me', String name = 'Aarav Sharma'}) => User(
      id: id,
      name: name,
      username: '21bcs5084',
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

/// Records what the provider asked the repository to do.
class _SpyRepository implements ProfileRepository {
  _SpyRepository({this.current});

  User? current;
  final List<String> calls = [];
  Map<String, dynamic>? lastPatch;

  @override
  Future<User?> fetchCurrent() async {
    calls.add('fetchCurrent');
    return current;
  }

  @override
  Future<User?> fetchById(String id) async {
    calls.add('fetchById:$id');
    return current?.id == id ? current : null;
  }

  @override
  Future<User> update(String id, Map<String, dynamic> patch) async {
    calls.add('update:$id');
    lastPatch = patch;
    current = ProfileMapper.applyPatch(current ?? _user(id: id), patch);
    return current!;
  }

  @override
  Future<void> setPresence({required bool online}) async {
    calls.add('setPresence:$online');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Repositories.reset();
  });

  tearDown(Repositories.reset);

  group('MockProfileRepository', () {
    late MockProfileStore store;
    late MockProfileRepository repo;
    final others = [_user(id: 's1', name: 'Bhavya Singh')];

    setUp(() {
      store = MockProfileStore();
      repo = MockProfileRepository(store: store, students: () => others);
    });

    test('fetchCurrent is null before anyone signs in', () async {
      expect(await repo.fetchCurrent(), isNull);
    });

    test('fetchCurrent returns whatever the store holds', () async {
      await store.write(_user());
      expect((await repo.fetchCurrent())?.name, 'Aarav Sharma');
    });

    test('fetchById finds a generated student', () async {
      expect((await repo.fetchById('s1'))?.name, 'Bhavya Singh');
    });

    test('fetchById prefers the signed-in student for their own id', () async {
      await store.write(_user(id: 's1', name: 'Me Not Them'));
      expect((await repo.fetchById('s1'))?.name, 'Me Not Them');
    });

    test('fetchById is null for someone who does not exist', () async {
      expect(await repo.fetchById('nobody'), isNull);
    });

    test('update applies the patch and persists it', () async {
      await store.write(_user());
      final updated = await repo.update('me', {'bio': 'New bio'});

      expect(updated.bio, 'New bio');
      // Persisted, not just returned — the next session must see it.
      expect((await store.read())?.bio, 'New bio');
    });

    test('update rejects a patch with nobody signed in', () async {
      expect(() => repo.update('me', {'bio': 'x'}), throwsStateError);
    });
  });

  group('MockProfileStore', () {
    test('survives a fresh instance reading the same prefs', () async {
      await MockProfileStore().write(_user(), rememberAccount: true);

      // A different instance, as happens after a restart.
      final store = MockProfileStore();
      expect((await store.read())?.uid, '21BCS5084');
      expect(await store.isKnownAccount('21bcs5084'), isTrue);
    });

    test('an account is only known once it has registered', () async {
      expect(await MockProfileStore().isKnownAccount('21bcs9999'), isFalse);
    });

    test('clear wipes both the profile and the known accounts', () async {
      final store = MockProfileStore();
      await store.write(_user(), rememberAccount: true);
      await store.clear();

      expect(await store.read(), isNull);
      expect(await store.isKnownAccount('21bcs5084'), isFalse);
    });

    test('corrupt stored json signs the student out instead of throwing', () async {
      SharedPreferences.setMockInitialValues({'cc_profile': 'not json'});
      expect(await MockProfileStore().read(), isNull);
    });
  });

  group('ProfileMapper.applyPatch', () {
    test('mirrors toUpdate, so a mock edit matches a real one', () async {
      final before = _user();
      final patch = ProfileMapper.toUpdate(
        name: 'Renamed',
        bio: 'Bio',
        interests: const ['coding'],
        languages: const ['Hindi'],
        lookingFor: const ['Study Partner'],
        hideYear: true,
      );
      final after = ProfileMapper.applyPatch(before, patch);

      expect(after.name, 'Renamed');
      expect(after.bio, 'Bio');
      expect(after.interests, ['coding']);
      expect(after.languages, ['Hindi']);
      expect(after.lookingFor, ['Study Partner']);
      expect(after.hideYear, isTrue);
    });

    test('leaves untouched fields alone', () {
      final after = ProfileMapper.applyPatch(_user(), {'bio': 'only this'});
      expect(after.name, 'Aarav Sharma');
      expect(after.department, 'Computer Science');
    });

    test('a photo change maps through avatar_url', () {
      final patch = ProfileMapper.toUpdate(avatarUrl: 'https://x.test/p.jpg');
      expect(ProfileMapper.applyPatch(_user(), patch).profilePhotoUrl,
          'https://x.test/p.jpg');
    });
  });

  group('embedded relations', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
          'id': 'abc',
          'full_name': 'Bhavya Singh',
          'username': '21bcs7777',
          'university_uid': '21bcs7777',
          'admission_year': 2021,
          'hide_active_status': false,
          ...extra,
        };

    test('badge labels are pulled out of the nested wrappers', () {
      final user = ProfileMapper.fromRow(row({
        'profile_badges': [
          {'badges': {'label': 'Campus Ambassador'}},
          {'badges': {'label': 'Early Adopter'}},
        ],
      }));
      expect(user.badges, ['Campus Ambassador', 'Early Adopter']);
    });

    test('no badges is an empty list, not a crash', () {
      expect(ProfileMapper.fromRow(row({'profile_badges': []})).badges, isEmpty);
      expect(ProfileMapper.fromRow(row({})).badges, isEmpty);
    });

    test('a malformed badge row is skipped rather than fatal', () {
      final user = ProfileMapper.fromRow(row({
        'profile_badges': [
          {'badges': null},
          {'badges': {'label': 'Helpful'}},
        ],
      }));
      expect(user.badges, ['Helpful']);
    });

    test('presence embedded as an object is read', () {
      final user = ProfileMapper.fromRow(row({
        'user_presence': {'is_online': true, 'last_active': '2026-08-02T10:00:00Z'},
      }));
      expect(user.isOnline, isTrue);
    });

    test('presence embedded as a single-element list is also read', () {
      // PostgREST picks the list shape when it cannot prove the relation is
      // one-to-one, so both have to work.
      final user = ProfileMapper.fromRow(row({
        'user_presence': [
          {'is_online': true, 'last_active': '2026-08-02T10:00:00Z'},
        ],
      }));
      expect(user.isOnline, isTrue);
    });

    test('the privacy switch still wins over embedded presence', () {
      final user = ProfileMapper.fromRow(row({
        'hide_active_status': true,
        'user_presence': {'is_online': true},
      }));
      expect(user.isOnline, isFalse);
    });
  });

  group('AuthProvider profile operations', () {
    test('refreshProfile picks up a change made elsewhere', () async {
      final repo = _SpyRepository(current: _user());
      final auth = AuthProvider(
        backend: _StubBackend(profile: _user()),
        profiles: repo,
      );
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser?.bio, '');

      // A badge award or a trust-level recompute, arriving out of band.
      repo.current = _user().copyWith(bio: 'changed server side');
      await auth.refreshProfile();

      expect(auth.currentUser?.bio, 'changed server side');
    });

    test('refreshProfile does nothing when signed out', () async {
      final repo = _SpyRepository();
      final auth = AuthProvider(backend: _StubBackend(), profiles: repo);
      await Future<void>.delayed(Duration.zero);
      repo.calls.clear();

      await auth.refreshProfile();
      expect(repo.calls, isEmpty);
    });

    test('a failing refresh keeps the profile that was already shown', () async {
      final auth = AuthProvider(
        backend: _StubBackend(profile: _user()),
        profiles: _ThrowingRepository(),
      );
      await Future<void>.delayed(Duration.zero);

      await auth.refreshProfile();
      expect(auth.currentUser?.name, 'Aarav Sharma');
    });

    test('restoring a session marks the student online', () async {
      final repo = _SpyRepository(current: _user());
      AuthProvider(backend: _StubBackend(profile: _user()), profiles: repo);
      await Future<void>.delayed(Duration.zero);

      expect(repo.calls, contains('setPresence:true'));
    });

    test('no presence heartbeat when there is no session', () async {
      final repo = _SpyRepository();
      AuthProvider(backend: _StubBackend(), profiles: repo);
      await Future<void>.delayed(Duration.zero);

      expect(repo.calls, isNot(contains('setPresence:true')));
    });

    test('a presence failure never surfaces to the caller', () async {
      final auth = AuthProvider(
        backend: _StubBackend(profile: _user()),
        profiles: _ThrowingRepository(),
      );
      await Future<void>.delayed(Duration.zero);

      await expectLater(auth.setPresence(online: false), completes);
    });
  });
}

class _StubBackend implements AuthBackend {
  _StubBackend({this.profile});
  final User? profile;

  @override
  int get otpLength => 6;
  @override
  String get demoOtp => '';
  @override
  Future<User?> restoreSession() async => profile;
  @override
  Future<void> sendOtp(String email) async {}
  @override
  Future<AuthOutcome> verifyOtp(String email, String code) async =>
      profile == null ? const AuthOutcome.needsProfile() : AuthOutcome.loggedIn(profile!);
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
  }) async =>
      _user(name: name);
  @override
  Future<User> updateProfile(User current, Map<String, dynamic> changes) async =>
      ProfileMapper.applyPatch(current, changes);
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

class _ThrowingRepository implements ProfileRepository {
  @override
  Future<User?> fetchCurrent() async => throw Exception('network down');
  @override
  Future<User?> fetchById(String id) async => throw Exception('network down');
  @override
  Future<User> update(String id, Map<String, dynamic> patch) async =>
      throw Exception('network down');
  @override
  Future<void> setPresence({required bool online}) async =>
      throw Exception('network down');
}

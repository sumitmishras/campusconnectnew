import '../../mock_data/mock_data_generator.dart';
import '../../models/user_model.dart';
import '../../services/auth_backend.dart';
import '../../services/supabase_service.dart';
import '../mock_profile_store.dart';
import '../reference_data.dart';
import 'bookmark_repository.dart';
import 'campus_repository.dart';
import 'chat_repository.dart';
import 'connection_repository.dart';
import 'discover_repository.dart';
import 'profile_repository.dart';
import 'reference_repository.dart';
import 'storage_repository.dart';

/// Composition root for the data layer.
///
/// One place decides, from `SupabaseService.isReady`, whether the app talks to
/// Postgres or to the in-memory fixtures — so no provider has to know, and
/// there is exactly one spot to look when the answer is surprising.
///
/// Built lazily rather than from `main()`, so widget tests that never call
/// `SupabaseService.initialize()` still get working mock repositories.
class Repositories {
  const Repositories._();

  static MockProfileStore? _mockStore;
  static ProfileRepository? _profiles;
  static DiscoverRepository? _discover;
  static ConnectionRepository? _connections;
  static AuthBackend? _authBackend;
  static StorageRepository? _storage;
  static ChatRepository? _chat;
  static CampusRepository? _campus;
  static ReferenceRepository? _reference;
  static BookmarkRepository? _bookmarks;

  /// Shared by [MockAuthBackend] and [MockProfileRepository] so a profile
  /// edit and a session restore cannot disagree.
  static MockProfileStore get mockStore => _mockStore ??= MockProfileStore();

  static ProfileRepository get profiles => _profiles ??= _buildProfiles();

  static DiscoverRepository get discover => _discover ??= _buildDiscover();

  static ConnectionRepository get connections =>
      _connections ??= _buildConnections();

  static AuthBackend get authBackend => _authBackend ??= _buildAuthBackend();

  static StorageRepository get storage => _storage ??= _buildStorage();

  static ChatRepository get chat => _chat ??= _buildChat();

  static CampusRepository get campus => _campus ??= _buildCampus();

  static ReferenceRepository get reference => _reference ??= _buildReference();

  static BookmarkRepository get bookmarks => _bookmarks ??= _buildBookmarks();

  /// Fills the picker option lists. Called from `main()` and again after
  /// sign-in, because `programs` and `tags` are only readable to a signed-in
  /// student.
  static Future<void> loadReferenceData() =>
      ReferenceData.load(() => reference.fetch());

  /// The generated campus, initialised on first use. Every mock repository
  /// reads through this one closure, so they all see the same students and
  /// `MockDataGenerator` stays a fixture rather than a dependency.
  static List<User> _fixtureStudents() {
    MockDataGenerator.initialize();
    return MockDataGenerator.students;
  }

  static ProfileRepository _buildProfiles() {
    if (SupabaseService.isReady) {
      return SupabaseProfileRepository(SupabaseService.client);
    }
    return MockProfileRepository(
      store: mockStore,
      students: _fixtureStudents,
    );
  }

  static DiscoverRepository _buildDiscover() {
    if (SupabaseService.isReady) {
      return SupabaseDiscoverRepository(SupabaseService.client);
    }
    return MockDiscoverRepository(students: _fixtureStudents);
  }

  static ConnectionRepository _buildConnections() {
    if (SupabaseService.isReady) {
      return SupabaseConnectionRepository(SupabaseService.client);
    }
    return MockConnectionRepository(students: _fixtureStudents);
  }

  static AuthBackend _buildAuthBackend() {
    if (SupabaseService.isReady) {
      return SupabaseAuthBackend(SupabaseService.client, profiles);
    }
    return MockAuthBackend(store: mockStore, profiles: profiles);
  }

  static StorageRepository _buildStorage() {
    if (SupabaseService.isReady) {
      return SupabaseStorageRepository(SupabaseService.client);
    }
    return const MockStorageRepository();
  }

  /// Chat has no offline implementation: threads, sequence numbers, read
  /// pointers and the block gate all live in Postgres. Without a client it
  /// reads as empty and says so, rather than answering with invented threads —
  /// a misconfigured build should look broken, not busy.
  static ChatRepository _buildChat() {
    if (SupabaseService.isReady) {
      return SupabaseChatRepository(SupabaseService.client, storage);
    }
    return const UnavailableChatRepository();
  }

  static BookmarkRepository _buildBookmarks() {
    if (SupabaseService.isReady) {
      return SupabaseBookmarkRepository(SupabaseService.client);
    }
    return MockBookmarkRepository();
  }

  static CampusRepository _buildCampus() {
    if (SupabaseService.isReady) {
      return SupabaseCampusRepository(SupabaseService.client, storage, bookmarks);
    }
    return MockCampusRepository(
      seed: MockDataGenerator.campusSnapshot,
      newId: MockDataGenerator.newId,
    );
  }

  static ReferenceRepository _buildReference() {
    if (SupabaseService.isReady) {
      return SupabaseReferenceRepository(SupabaseService.client);
    }
    return const MockReferenceRepository();
  }

  /// Test seam. Pass the fakes a test needs and leave the rest to build
  /// normally; call [reset] in tearDown so state does not leak between tests.
  static void overrideForTest({
    ProfileRepository? profiles,
    DiscoverRepository? discover,
    ConnectionRepository? connections,
    AuthBackend? authBackend,
    MockProfileStore? mockStore,
    StorageRepository? storage,
    ChatRepository? chat,
    CampusRepository? campus,
    ReferenceRepository? reference,
    BookmarkRepository? bookmarks,
  }) {
    if (mockStore != null) _mockStore = mockStore;
    if (profiles != null) _profiles = profiles;
    if (discover != null) _discover = discover;
    if (connections != null) _connections = connections;
    if (authBackend != null) _authBackend = authBackend;
    if (storage != null) _storage = storage;
    if (chat != null) _chat = chat;
    if (campus != null) _campus = campus;
    if (reference != null) _reference = reference;
    if (bookmarks != null) _bookmarks = bookmarks;
  }

  static void reset() {
    _mockStore = null;
    _profiles = null;
    _discover = null;
    _connections = null;
    _authBackend = null;
    _storage = null;
    _chat = null;
    _campus = null;
    _reference = null;
    _bookmarks = null;
    ReferenceData.reset();
  }
}

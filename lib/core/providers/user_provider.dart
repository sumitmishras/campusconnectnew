import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/bookmark_repository.dart';
import '../data/repositories/connection_repository.dart';
import '../data/repositories/discover_repository.dart';
import '../data/repositories/repositories.dart';
import '../models/connection_model.dart';
import '../models/discover_query.dart';
import '../models/report_reason.dart';
import '../models/user_model.dart';
import '../services/presence_service.dart';
import '../utils/debouncer.dart';

/// The one-tap filters above the Discover list. A presentation shortcut, not a
/// data concept — [DiscoverQuery] is what reaches the repository, and these
/// are resolved into it against the signed-in student.
enum DiscoverFilter { all, recentlyActive, sameDepartment, sameYear, online }

/// Discover and Connections.
///
/// Both live here because they are one screen's worth of state seen from two
/// angles: every student card shows a relationship, and every relationship
/// resolves to a student. Splitting them would mean two providers reading each
/// other, and a card whose button lags the tab it was changed from.
///
/// Nothing in here knows whether it is talking to Postgres or to fixtures —
/// [DiscoverRepository] and [ConnectionRepository] answer that, and
/// [Repositories] chose which one at startup.
class UserProvider with ChangeNotifier {
  UserProvider({
    DiscoverRepository? discover,
    ConnectionRepository? connections,
    BookmarkRepository? bookmarks,
    Duration searchDebounce = const Duration(milliseconds: 300),
  })  : _discover = discover ?? Repositories.discover,
        _connections = connections ?? Repositories.connections,
        _bookmarks = bookmarks ?? Repositories.bookmarks,
        _searchDebouncer = Debouncer(delay: searchDebounce);

  final DiscoverRepository _discover;
  final ConnectionRepository _connections;
  final BookmarkRepository _bookmarks;
  final Debouncer _searchDebouncer;

  // ------------------------------------------------------------------ state

  /// The signed-in student, fed in from `AuthProvider` by the proxy in
  /// `main.dart`. Nothing loads until this arrives — Discover is unreachable
  /// while signed out, and "same department" has no meaning without it.
  User? _me;
  bool _bootstrapped = false;

  final List<User> _students = [];
  final Map<String, User> _profileCache = {};

  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  /// Guards against an out-of-order response overwriting a newer one. Every
  /// load stamps this; a result whose stamp is stale is dropped. Without it a
  /// slow "all students" response can land after a fast filtered one and put
  /// the wrong list under the wrong filter.
  int _loadToken = 0;

  DiscoverFilter _quickFilter = DiscoverFilter.all;
  String _search = '';
  String _departmentFilter = DiscoverQuery.any;
  String _yearFilter = DiscoverQuery.any;
  String _genderFilter = DiscoverQuery.any;
  String _lookingForFilter = DiscoverQuery.any;
  List<String> _interestFilters = const [];

  /// True when a quick filter and an advanced facet ask for different values
  /// of the same field — "Same Department" plus an explicit, different
  /// department. The old in-memory list ANDed them and came back empty; this
  /// reaches the same answer without spending a round trip on it.
  bool _contradictoryFilters = false;

  final List<ConnectionEntry> _entries = [];
  final Map<String, ConnectionEntry> _entryByUserId = {};
  final Map<String, User> _blocked = {};
  final Set<String> _bookmarkedIds = {};
  final Set<String> _reportedIds = {};

  /// Requests dismissed with "Ignore". The row stays `pending` server-side —
  /// there is no `ignored` state in `public.connection_state`, and inventing
  /// one would be a schema change. Ignoring is therefore a local, reversible
  /// hide for this session, which is also what it means in most products:
  /// unlike declining, the sender is told nothing.
  final Set<String> _ignoredEntryIds = {};

  bool _isLoadingConnections = false;
  String? _connectionsError;
  String? _lastActionError;

  final Map<String, List<User>> _byPurpose = {};
  final Set<String> _purposeInFlight = {};
  bool _isLoadingPartners = false;

  StreamSubscription<void>? _connectionSub;
  StreamSubscription<Set<String>>? _presenceSub;

  /// Accepting a request writes one row and the trigger touches another; both
  /// come back over the socket within a few milliseconds of each other. This
  /// collapses them into one re-read.
  Timer? _connectionRefresh;

  // --------------------------------------------------------------- getters

  User? get currentUser => _me;

  /// First page of Discover is in flight.
  bool get isLoading => _isLoading;

  /// A further page is in flight; the list already has something in it.
  bool get isLoadingMore => _isLoadingMore;

  bool get hasMore => _hasMore;

  /// Set when the last Discover load failed. The list keeps whatever it had,
  /// so a failed "load more" never blanks the screen.
  String? get error => _error;

  bool get isLoadingConnections => _isLoadingConnections;
  String? get connectionsError => _connectionsError;

  /// Set when an action (connect, accept, block …) was rolled back. Screens
  /// read it once to show a message and it is cleared on the next action.
  String? get lastActionError => _lastActionError;

  bool get isLoadingPartners => _isLoadingPartners;

  List<User> get students => List.unmodifiable(_students);

  String get query => _search;
  DiscoverFilter get quickFilter => _quickFilter;
  String get departmentFilter => _departmentFilter;
  String get yearFilter => _yearFilter;
  String get genderFilter => _genderFilter;
  String get lookingForFilter => _lookingForFilter;
  List<String> get interestFilters => List.unmodifiable(_interestFilters);

  /// Advanced facets only — search and the quick filters have their own
  /// affordances on screen.
  int get activeFilterCount {
    var n = 0;
    if (_departmentFilter != DiscoverQuery.any) n++;
    if (_yearFilter != DiscoverQuery.any) n++;
    if (_genderFilter != DiscoverQuery.any) n++;
    if (_lookingForFilter != DiscoverQuery.any) n++;
    if (_interestFilters.isNotEmpty) n++;
    return n;
  }

  // ------------------------------------------------------------- lifecycle

  /// Called by `ChangeNotifierProxyProvider` whenever the signed-in profile
  /// changes.
  ///
  /// Runs during the provider subtree's build, so it must never notify
  /// synchronously — every path that needs to schedules a microtask instead.
  void syncCurrentUser(User? me) {
    if (me == null) {
      if (_bootstrapped) _resetForSignOut();
      _me = null;
      return;
    }

    final previous = _me;
    _me = me;
    _profileCache[me.id] = me;
    // Idempotent per student, and safe here: subscribing notifies nobody, and
    // this runs inside the provider subtree's build.
    _listen(me.id);

    if (!_bootstrapped) {
      _bootstrapped = true;
      // Set without notifying — this runs inside the provider subtree's
      // build. The first frame reads it as loading, which is correct, and the
      // microtask below does the notifying from then on.
      _isLoading = true;

      scheduleMicrotask(() async {
        // Connections and blocks first, deliberately. The Discover query
        // excludes blocked students, so running the two in parallel would
        // build the first page against an empty block list and show someone
        // the student had already blocked. It would also mean every card
        // rendering "Connect" for a frame before flipping to its real
        // relationship. One small query is worth both.
        await _loadConnections();
        await _reload();
        await _loadBookmarks();
      });
      return;
    }

    if (previous == null) return;

    // An edit to my own profile only matters to Discover when it changes what
    // "same department" or "same year" resolve to — the rest of the row is
    // not part of any query. Re-running otherwise would throw away the
    // student's scroll position for nothing.
    final referenceChanged =
        previous.id != me.id ||
        previous.department != me.department ||
        previous.year != me.year;

    if (referenceChanged && _quickFilterUsesReference) {
      scheduleMicrotask(_reload);
    }
  }

  bool get _quickFilterUsesReference =>
      _quickFilter == DiscoverFilter.sameDepartment ||
      _quickFilter == DiscoverFilter.sameYear;

  /// Whose sockets are currently wired up, so a rebuild does not re-subscribe
  /// on every frame.
  String? _listeningFor;

  /// The two things that used to only ever change on a pull-to-refresh.
  ///
  /// A connection request is a row written by someone else on another phone,
  /// and the online dot is a socket event — neither of them passes through any
  /// call this provider makes, so without these the Connections tab was
  /// accurate only at the moment it was last fetched by hand.
  void _listen(String me) {
    if (_listeningFor == me) return;
    _listeningFor = me;

    _connectionSub?.cancel();
    _connectionSub =
        _connections.changes(me).listen((_) => _scheduleConnectionRefresh());

    _presenceSub ??= PresenceService.instance.changes.listen((ids) {
      if (_applyPresence(ids)) notifyListeners();
    });
  }

  void _scheduleConnectionRefresh() {
    _connectionRefresh?.cancel();
    _connectionRefresh = Timer(const Duration(milliseconds: 350), () {
      // Quietly: the tab is already on screen with the previous list on it,
      // and flipping it to a spinner every time a row changes would be worse
      // than the stale row this is replacing.
      unawaited(_loadConnections(quiet: true));
    });
  }

  /// Patches every cached copy of a student with what the presence channel
  /// currently says, and reports whether anything moved.
  ///
  /// Called after each load as well as on every channel event, and that is the
  /// half that was missing: the channel only reports *changes*, so a student
  /// who was already online when the list was fetched produced no event, and
  /// their card kept the `user_presence` row's "active 23 minutes ago" until
  /// they happened to disconnect.
  bool _applyPresence(Set<String> onlineIds) {
    var changed = false;

    User patch(User user) {
      // The privacy switch wins over the socket, the same way it does in
      // `ChatProvider`.
      if (user.hideActiveStatus || user.id == _me?.id) return user;
      final online = onlineIds.contains(user.id);
      if (online == user.isOnline) return user;
      changed = true;
      return user.copyWith(
        isOnline: online,
        // Leaving the presence channel is the last-seen moment, observed as it
        // happens. Coming online needs no stamp — "Online now" is the label,
        // and inventing one is how a wrong time gets on screen.
        lastActive: online ? null : DateTime.now().toUtc(),
      );
    }

    for (var i = 0; i < _students.length; i++) {
      _students[i] = patch(_students[i]);
    }
    for (final id in _profileCache.keys.toList()) {
      _profileCache[id] = patch(_profileCache[id]!);
    }
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final other = patch(entry.other);
      if (!identical(other, entry.other)) {
        _entries[i] = entry.copyWith(other: other);
      }
    }
    for (final purpose in _byPurpose.keys.toList()) {
      _byPurpose[purpose] = [for (final u in _byPurpose[purpose]!) patch(u)];
    }

    // The entries were replaced wholesale above, so the id index points at
    // copies that no longer exist.
    if (changed) _reindexEntries();
    return changed;
  }

  void _resetForSignOut() {
    _bootstrapped = false;
    _listeningFor = null;
    _connectionRefresh?.cancel();
    _connectionSub?.cancel();
    _connectionSub = null;
    unawaited(_connections.close());
    _students.clear();
    _profileCache.clear();
    _entries.clear();
    _entryByUserId.clear();
    _blocked.clear();
    _bookmarkedIds.clear();
    _reportedIds.clear();
    _ignoredEntryIds.clear();
    _byPurpose.clear();
    _purposeInFlight.clear();
    _offset = 0;
    _hasMore = true;
    _error = null;
    _connectionsError = null;
    _lastActionError = null;
    _loadToken++;
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _connectionRefresh?.cancel();
    _connectionSub?.cancel();
    _presenceSub?.cancel();
    unawaited(_connections.close());
    // Anything still in flight is now stale by definition.
    _loadToken++;
    super.dispose();
  }

  // ------------------------------------------------------------- the query

  /// The advanced facets plus whatever the quick filter resolves to, and the
  /// students that must never appear.
  DiscoverQuery _buildQuery() {
    var department = _departmentFilter;
    var year = _yearFilter;
    var onlineOnly = false;
    var recentlyActive = false;
    _contradictoryFilters = false;

    switch (_quickFilter) {
      case DiscoverFilter.all:
        break;
      case DiscoverFilter.online:
        onlineOnly = true;
      case DiscoverFilter.recentlyActive:
        recentlyActive = true;
      case DiscoverFilter.sameDepartment:
        final mine = _me?.department;
        if (mine != null && mine.isNotEmpty) {
          if (department == DiscoverQuery.any) {
            department = mine;
          } else if (department != mine) {
            _contradictoryFilters = true;
          }
        }
      case DiscoverFilter.sameYear:
        final mine = _me?.year;
        if (mine != null && mine.isNotEmpty) {
          if (year == DiscoverQuery.any) {
            year = mine;
          } else if (year != mine) {
            _contradictoryFilters = true;
          }
        }
    }

    return DiscoverQuery(
      search: _search,
      department: department,
      year: year,
      gender: _genderFilter,
      lookingFor: _lookingForFilter,
      interests: _interestFilters,
      onlineOnly: onlineOnly,
      recentlyActive: recentlyActive,
      excludeIds: {
        if (_me != null) _me!.id,
        ..._blocked.keys,
      },
    );
  }

  // ---------------------------------------------------------------- search

  /// Debounced. The controller drives the text field, so the student sees
  /// their keystroke immediately; only the query waits.
  void searchStudents(String value) {
    final next = value.trim();
    _searchDebouncer.run(() {
      if (next == _search) return;
      _search = next;
      _reload();
    });
  }

  void setQuickFilter(DiscoverFilter filter) {
    if (_quickFilter == filter) return;
    _quickFilter = filter;
    _reload();
  }

  void applyAdvancedFilters({
    String? department,
    String? year,
    String? gender,
    String? lookingFor,
    List<String>? interests,
  }) {
    final before = _buildQuery();

    _departmentFilter = department ?? _departmentFilter;
    _yearFilter = year ?? _yearFilter;
    _genderFilter = gender ?? _genderFilter;
    _lookingForFilter = lookingFor ?? _lookingForFilter;
    _interestFilters = interests ?? _interestFilters;

    // Re-applying the sheet without changing anything is common — the student
    // opens it, looks, and taps Apply. Value equality on DiscoverQuery is
    // what makes that free.
    if (_buildQuery() == before) {
      notifyListeners();
      return;
    }
    _reload();
  }

  /// Drops the facets and the quick filter. The search box is left alone —
  /// this is the "Clear" beside "N filters applied", and it should not wipe
  /// text the student is still typing against.
  void clearFilters() {
    _departmentFilter = DiscoverQuery.any;
    _yearFilter = DiscoverQuery.any;
    _genderFilter = DiscoverQuery.any;
    _lookingForFilter = DiscoverQuery.any;
    _interestFilters = const [];
    _quickFilter = DiscoverFilter.all;
    _reload();
  }

  /// Everything, search included. Backs the "Clear filters" action on the
  /// empty state, where the search term is usually the thing that emptied it.
  ///
  /// The debouncer is cancelled first: a keystroke still in flight would
  /// otherwise land 300 ms later and re-apply the term that was just cleared.
  void clearSearchAndFilters() {
    _searchDebouncer.cancel();
    _search = '';
    clearFilters();
  }

  // ----------------------------------------------------------------- pages

  /// Called when the app returns to the foreground.
  ///
  /// Realtime re-joins after a dropped socket, it does not replay — so every
  /// request that arrived while the phone was in someone's pocket has to be
  /// fetched. Quiet, because the tab is already on screen.
  Future<void> resync() => _loadConnections(quiet: true);

  /// Pull to refresh, and the retry action on the error state.
  Future<void> refresh() async {
    _searchDebouncer.cancel();
    await Future.wait([_reload(), _loadConnections()]);
  }

  /// Retry after a failed load, without disturbing the filters.
  Future<void> retry() => refresh();

  Future<void> _reload() async {
    final token = ++_loadToken;
    final query = _buildQuery();

    _isLoading = true;
    _isLoadingMore = false;
    _error = null;
    notifyListeners();

    if (_contradictoryFilters) {
      _students.clear();
      _offset = 0;
      _hasMore = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final page = await _discover.fetchStudents(query: query, offset: 0);
      if (token != _loadToken) return;

      _students
        ..clear()
        ..addAll(page.items);
      _cacheProfiles(page.items);
      _offset = page.nextOffset;
      _hasMore = page.hasMore;
      _error = null;
      // The rows carry `user_presence`, which decays; the channel is live.
      _applyPresence(PresenceService.instance.onlineIds);
    } catch (e) {
      if (token != _loadToken) return;
      _students.clear();
      _offset = 0;
      _hasMore = false;
      _error = _readable(e, 'We could not load students right now.');
    } finally {
      if (token == _loadToken) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Next page. Safe to call on every scroll frame — it is a no-op unless
  /// there is more to fetch and nothing already in flight.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    final token = _loadToken;
    final query = _buildQuery();

    _isLoadingMore = true;
    notifyListeners();

    try {
      final page =
          await _discover.fetchStudents(query: query, offset: _offset);
      if (token != _loadToken) return;

      // A student can arrive twice if a row shifted between pages — someone
      // signed up, or a profile stopped being discoverable. De-duplicating on
      // arrival is cheaper than a stable-cursor scheme and invisible either
      // way.
      final known = _students.map((s) => s.id).toSet();
      final fresh = page.items.where((s) => !known.contains(s.id)).toList();

      _students.addAll(fresh);
      _cacheProfiles(fresh);
      _offset = page.nextOffset;
      _hasMore = page.hasMore;
      _error = null;
      _applyPresence(PresenceService.instance.onlineIds);
    } catch (e) {
      if (token != _loadToken) return;
      // The list keeps what it had. Only the footer changes.
      _error = _readable(e, 'We could not load more students.');
      _hasMore = false;
    } finally {
      if (token == _loadToken) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  void _cacheProfiles(Iterable<User> users) {
    for (final u in users) {
      _profileCache[u.id] = u;
    }
  }

  // ----------------------------------------------------- partner shortlists

  /// Students who listed any of [purposes] in "looking for".
  ///
  /// Returns what is cached and kicks off a fetch the first time, notifying
  /// when it lands. Callers render the empty list for one frame, which is what
  /// the surrounding `isLoadingPartners` spinner covers.
  List<User> studentsLookingFor(List<String> purposes) {
    final key = purposes.join('|');
    final cached = _byPurpose[key];
    if (cached != null) {
      return cached.where((u) => !_blocked.containsKey(u.id)).toList();
    }
    if (_bootstrapped) scheduleMicrotask(() => _loadPurpose(key, purposes));
    return const [];
  }

  Future<void> _loadPurpose(String key, List<String> purposes) async {
    if (_byPurpose.containsKey(key) || _purposeInFlight.contains(key)) return;
    _purposeInFlight.add(key);
    _isLoadingPartners = true;
    notifyListeners();

    try {
      final users = await _discover.fetchByPurpose(
        purposes,
        excludeIds: {if (_me != null) _me!.id, ..._blocked.keys},
      );
      _byPurpose[key] = users;
      _cacheProfiles(users);
    } catch (_) {
      // An empty shortlist reads as "nobody available", which is the same
      // thing from the student's side and is already handled by the screen's
      // empty state.
      _byPurpose[key] = const [];
    } finally {
      _purposeInFlight.remove(key);
      _isLoadingPartners = _purposeInFlight.isNotEmpty;
      notifyListeners();
    }
  }

  // ----------------------------------------------------------- connections

  /// [quiet] skips the spinner and keeps the previous error, for the reloads
  /// driven by the socket rather than by the student.
  Future<void> _loadConnections({bool quiet = false}) async {
    final me = _me;
    if (me == null) return;

    if (!quiet) {
      _isLoadingConnections = true;
      _connectionsError = null;
      notifyListeners();
    }

    try {
      final results = await Future.wait([
        _connections.fetchEntries(me.id),
        _connections.fetchBlocked(me.id),
      ]);

      final entries = results[0] as List<ConnectionEntry>;
      final blocked = results[1] as List<User>;

      _replaceEntries(entries);

      _blocked
        ..clear()
        ..addEntries(blocked.map((u) => MapEntry(u.id, u)));
      _cacheProfiles(blocked);

      // `user_presence` is a table and lags; the channel is the live answer.
      _applyPresence(PresenceService.instance.onlineIds);
      _connectionsError = null;
    } catch (e) {
      _connectionsError =
          _readable(e, 'We could not load your connections right now.');
    } finally {
      _isLoadingConnections = false;
      notifyListeners();
    }
  }

  void _replaceEntries(List<ConnectionEntry> entries) {
    _entries
      ..clear()
      ..addAll(entries);
    _reindexEntries();
    _cacheProfiles(entries.map((e) => e.other));
  }

  void _reindexEntries() {
    final me = _me;
    _entryByUserId.clear();
    if (me == null) return;
    for (final entry in _entries) {
      _entryByUserId[entry.connection.otherId(me.id)] = entry;
    }
  }

  /// How the signed-in student relates to [userId]. The single source of
  /// truth every screen switches on.
  ConnectionStatus relationshipWith(String userId) {
    if (_blocked.containsKey(userId)) return ConnectionStatus.blocked;
    final me = _me;
    if (me == null) return ConnectionStatus.none;
    final entry = _entryByUserId[userId];
    if (entry == null) return ConnectionStatus.none;
    return entry.statusFor(me.id);
  }

  ConnectionEntry? entryFor(String userId) => _entryByUserId[userId];

  String requestPurpose(String userId) =>
      _entryByUserId[userId]?.purpose ?? 'Friendship';

  /// Requests waiting on me, ignored ones left out.
  List<User> get receivedRequests => _entries
      .where((e) =>
          e.state == ConnectionState.pending &&
          !_ignoredEntryIds.contains(e.id) &&
          _me != null &&
          e.connection.addresseeId == _me!.id)
      .map((e) => e.other)
      .toList();

  /// Requests I sent that are still waiting.
  List<User> get sentRequests => _entries
      .where((e) =>
          e.state == ConnectionState.pending &&
          _me != null &&
          e.connection.requesterId == _me!.id)
      .map((e) => e.other)
      .toList();

  List<User> get connections => _entries
      .where((e) => e.state == ConnectionState.accepted)
      .map((e) => e.other)
      .toList();

  // --------------------------------------------------------------- actions

  /// Sends a request, showing it as sent straight away and taking it back if
  /// the write fails.
  Future<bool> sendConnectionRequest(User other, String purpose) async {
    final me = _me;
    if (me == null) return false;

    final optimistic = ConnectionEntry(
      connection: Connection(
        // Replaced by the row the backend returns. Distinctive so a leaked
        // placeholder is obvious rather than mysterious.
        id: 'pending-${other.id}',
        requesterId: me.id,
        addresseeId: other.id,
        state: ConnectionState.pending,
        purpose: purpose,
        createdAt: DateTime.now(),
      ),
      other: other,
    );

    return _mutate(
      apply: () => _upsertEntry(optimistic),
      revert: () => _removeEntryFor(other.id),
      commit: () async {
        final saved = await _connections.sendRequest(
          me: me.id,
          other: other,
          purpose: purpose,
        );
        _upsertEntry(saved);
      },
      fallbackMessage: 'That request could not be sent.',
    );
  }

  Future<bool> acceptRequest(User other) =>
      _transition(other, ConnectionState.accepted,
          fallback: 'That request could not be accepted.');

  Future<bool> declineRequest(User other) =>
      _transition(other, ConnectionState.declined,
          fallback: 'That request could not be declined.');

  /// Withdraws a request I sent.
  Future<bool> cancelRequest(User other) =>
      _transition(other, ConnectionState.withdrawn,
          fallback: 'That request could not be withdrawn.');

  /// Disconnects. `cancelled` is the only legal way out of `accepted` — see
  /// `tg_connection_transition`.
  Future<bool> removeConnection(User other) =>
      _transition(other, ConnectionState.cancelled,
          fallback: 'That connection could not be removed.');

  /// Hides an incoming request without answering it. Local and reversible;
  /// see [_ignoredEntryIds] for why it is not written anywhere.
  void ignoreRequest(User other) {
    final entry = _entryByUserId[other.id];
    if (entry == null) return;
    if (!_ignoredEntryIds.add(entry.id)) return;
    notifyListeners();
  }

  bool isIgnored(String userId) {
    final entry = _entryByUserId[userId];
    return entry != null && _ignoredEntryIds.contains(entry.id);
  }

  /// Puts the request back in the inbox.
  void unignoreRequest(User other) {
    final entry = _entryByUserId[other.id];
    if (entry == null) return;
    if (!_ignoredEntryIds.remove(entry.id)) return;
    notifyListeners();
  }

  Future<bool> _transition(
    User other,
    ConnectionState state, {
    required String fallback,
  }) async {
    final me = _me;
    final entry = _entryByUserId[other.id];
    if (me == null || entry == null) return false;

    final previous = entry;
    final becomesInvisible = state != ConnectionState.accepted;

    return _mutate(
      apply: () {
        if (becomesInvisible) {
          _removeEntryFor(other.id);
        } else {
          _upsertEntry(entry.copyWith(
            connection: entry.connection.copyWith(
              state: state,
              respondedAt: DateTime.now(),
            ),
          ));
        }
      },
      revert: () => _upsertEntry(previous),
      commit: () async {
        final saved = await _connections.updateState(
          me: me.id,
          connection: previous.connection,
          state: state,
        );
        if (saved.state.isLive) {
          _upsertEntry(previous.copyWith(connection: saved));
        } else {
          _removeEntryFor(other.id);
        }
      },
      fallbackMessage: fallback,
    );
  }

  Future<bool> blockUser(User other, {String? reason}) async {
    final me = _me;
    if (me == null) return false;

    final previousEntry = _entryByUserId[other.id];
    final listIndex = _students.indexWhere((s) => s.id == other.id);
    final wasBookmarked = _bookmarkedIds.contains(other.id);

    return _mutate(
      apply: () {
        _blocked[other.id] = other;
        _removeEntryFor(other.id);
        _bookmarkedIds.remove(other.id);
        if (listIndex != -1) _students.removeAt(listIndex);
        _dropFromShortlists(other.id);
      },
      revert: () {
        _blocked.remove(other.id);
        if (previousEntry != null) _upsertEntry(previousEntry);
        if (wasBookmarked) _bookmarkedIds.add(other.id);
        if (listIndex != -1 && listIndex <= _students.length) {
          _students.insert(listIndex, other);
        }
        _byPurpose.clear();
      },
      commit: () => _connections.block(me: me.id, other: other, reason: reason),
      fallbackMessage: 'That student could not be blocked.',
    );
  }

  Future<bool> unblockUser(User other) async {
    final me = _me;
    if (me == null) return false;

    return _mutate(
      apply: () {
        _blocked.remove(other.id);
        _byPurpose.clear();
      },
      revert: () => _blocked[other.id] = other,
      commit: () => _connections.unblock(me: me.id, otherId: other.id),
      fallbackMessage: 'That student could not be unblocked.',
    );
  }

  Future<bool> reportUser(User other, ReportReason reason,
      {String? details}) async {
    final me = _me;
    if (me == null) return false;

    return _mutate(
      apply: () => _reportedIds.add(other.id),
      revert: () => _reportedIds.remove(other.id),
      commit: () => _connections.report(
        me: me.id,
        targetId: other.id,
        reason: reason,
        details: details,
      ),
      fallbackMessage: 'That report could not be submitted.',
    );
  }

  bool isReported(String userId) => _reportedIds.contains(userId);

  /// Applies the change, notifies immediately, and puts it back if the write
  /// fails. The student sees the result of their tap at once; a failure is a
  /// visible undo plus a message, not a spinner they had to wait through.
  Future<bool> _mutate({
    required VoidCallback apply,
    required VoidCallback revert,
    required Future<void> Function() commit,
    required String fallbackMessage,
  }) async {
    _lastActionError = null;
    apply();
    notifyListeners();

    try {
      await commit();
      notifyListeners();
      return true;
    } catch (e) {
      revert();
      _lastActionError = _readable(e, fallbackMessage);
      notifyListeners();
      return false;
    }
  }

  void _upsertEntry(ConnectionEntry entry) {
    final me = _me;
    if (me == null) return;
    final otherId = entry.connection.otherId(me.id);
    _entries.removeWhere((e) => e.connection.otherId(me.id) == otherId);
    _entries.insert(0, entry);
    _profileCache[entry.other.id] = entry.other;
    _reindexEntries();
  }

  void _removeEntryFor(String userId) {
    final me = _me;
    if (me == null) return;
    _entries.removeWhere((e) => e.connection.otherId(me.id) == userId);
    _reindexEntries();
  }

  void _dropFromShortlists(String userId) {
    for (final key in _byPurpose.keys.toList()) {
      _byPurpose[key] =
          _byPurpose[key]!.where((u) => u.id != userId).toList();
    }
  }

  // -------------------------------------------------------------- blocking

  bool isBlocked(String userId) => _blocked.containsKey(userId);

  List<User> get blockedStudents => List.unmodifiable(_blocked.values);

  // ------------------------------------------------------------- bookmarks

  bool isBookmarked(String userId) => _bookmarkedIds.contains(userId);

  /// Only students whose profile has been seen this session can be rendered.
  /// A bookmark on someone who has since left the campus resolves to nothing,
  /// which is the same outcome as RLS hiding them.
  List<User> get bookmarkedStudents =>
      _bookmarkedIds.map((id) => _profileCache[id]).nonNulls.toList();

  /// Returns the new state so the caller can show the right message.
  ///
  /// Optimistic, like every other action here: the icon flips at once and the
  /// row in `public.bookmarks` follows.
  bool toggleBookmark(String userId) {
    final added = !_bookmarkedIds.contains(userId);
    if (added) {
      _bookmarkedIds.add(userId);
    } else {
      _bookmarkedIds.remove(userId);
    }
    notifyListeners();

    unawaited(_bookmarks
        .set(
      targetType: BookmarkTarget.profile,
      targetId: userId,
      saved: added,
    )
        .catchError((_) {
      // Put it back: a bookmark that did not save should not look saved.
      if (added) {
        _bookmarkedIds.remove(userId);
      } else {
        _bookmarkedIds.add(userId);
      }
      notifyListeners();
    }));

    return added;
  }

  Future<void> _loadBookmarks() async {
    try {
      final ids = await _bookmarks.fetchIds(BookmarkTarget.profile);
      _bookmarkedIds
        ..clear()
        ..addAll(ids);
      // The profiles themselves are filled in as Discover pages them in; the
      // Bookmarks screen renders whatever is resolvable.
      notifyListeners();
    } catch (_) {
      // An unreachable bookmark list is an empty one.
    }
  }

  // ---------------------------------------------------------------- errors

  /// Repository failures already carry a student-facing message; anything else
  /// is a bug and gets a neutral one rather than a stack trace in a snackbar.
  static String _readable(Object error, String fallback) {
    if (error is ConnectionFailure) return error.message;
    return fallback;
  }
}

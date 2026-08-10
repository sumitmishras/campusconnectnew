import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../models/connection_model.dart';
import '../../models/report_reason.dart';
import '../../models/user_model.dart';
import '../../services/realtime_status.dart';
import '../connection_mapper.dart';

/// Raised for anything the student should see a message about. Anything else
/// is a bug and propagates — same contract as `AuthFailure`.
class ConnectionFailure implements Exception {
  final String message;
  const ConnectionFailure(this.message);
  @override
  String toString() => message;
}

/// Everything the app does with `public.connections`, `public.blocks` and
/// `public.reports`.
///
/// Identity is passed in rather than read from a session inside the
/// repository: Mock Mode has no session, and the Supabase implementation is
/// re-checked by RLS anyway (`connections_send` requires
/// `requester_id = auth.uid()`), so a mismatched id fails loudly at the
/// database instead of silently writing the wrong row.
abstract class ConnectionRepository {
  /// Every live relationship involving [me] — pending both ways, and
  /// accepted — each paired with the other student's profile.
  ///
  /// Terminal rows (declined / withdrawn / cancelled) are not returned. They
  /// exist for history and rate limiting; to the UI they are simply "no
  /// connection", and a fresh request is allowed.
  Future<List<ConnectionEntry>> fetchEntries(String me);

  /// Students [me] has blocked. Being blocked *by* someone is not knowable
  /// from the client, by design.
  Future<List<User>> fetchBlocked(String me);

  Future<ConnectionEntry> sendRequest({
    required String me,
    required User other,
    required String purpose,
    String? message,
  });

  /// Moves an existing request along. The legal transitions are enforced by
  /// `tg_connection_transition`; this mirrors them so Mock Mode fails the
  /// same way rather than accepting something the database would reject.
  Future<Connection> updateState({
    required String me,
    required Connection connection,
    required ConnectionState state,
  });

  /// Blocking also tears down any live connection, matching
  /// `tg_block_severs_connection`.
  Future<void> block({
    required String me,
    required User other,
    String? reason,
  });

  Future<void> unblock({required String me, required String otherId});

  Future<void> report({
    required String me,
    required String targetId,
    required ReportReason reason,
    String? details,
  });

  /// Fires whenever a `connections` row involving [me] appears or changes —
  /// a request arriving, and the answer to one coming back.
  ///
  /// Carries no payload on purpose. The replicated row has no profile joined
  /// to it and a request is unrenderable without one, so the caller re-reads
  /// the list; it is one small query and it cannot drift from the server the
  /// way a patched-in row can.
  Stream<void> changes(String me);

  /// Drops the subscription. The stream stays open, so the next [changes]
  /// call re-joins.
  Future<void> close();
}

// =====================================================================
// Supabase
// =====================================================================

class SupabaseConnectionRepository implements ConnectionRepository {
  SupabaseConnectionRepository(this._client);

  final SupabaseClient _client;

  final _changes = StreamController<void>.broadcast();

  RealtimeChannel? _channel;

  /// Whose rows the channel is currently filtered to, so a rebuild does not
  /// re-join it and a second account on the same phone does.
  String? _watching;

  @override
  Stream<void> changes(String me) {
    _subscribe(me);
    return _changes.stream;
  }

  void _subscribe(String me) {
    if (me.isEmpty || _watching == me) return;
    unawaited(close());
    _watching = me;

    // Two filtered subscriptions rather than one unfiltered one. Realtime
    // takes a single comparison per subscription, and a request touches this
    // student from either end — as the addressee when it arrives, as the
    // requester when it is answered. Subscribing unfiltered would work (RLS
    // would drop the rest) but every request sent anywhere on campus would
    // cross the socket first.
    _channel = _client.channel('cc-connections')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'connections',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'addressee_id',
          value: me,
        ),
        callback: (_) => _emit(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'connections',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'requester_id',
          value: me,
        ),
        callback: (_) => _emit(),
      )
      // Re-joining after the app was backgrounded means every request that
      // arrived in the meantime was missed, so the list is re-read.
      ..subscribe(realtimeStatus('cc-connections', onRejoin: _emit));
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    _watching = null;
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } catch (_) {
      // Tearing down a socket that is already gone is not a failure.
    }
  }

  @override
  Future<List<ConnectionEntry>> fetchEntries(String me) async {
    final rows = await _client
        .from('connections')
        .select(ConnectionMapper.selectWithProfiles)
        .or('requester_id.eq.$me,addressee_id.eq.$me')
        .inFilter('state', [
          ConnectionState.pending.wire,
          ConnectionState.accepted.wire,
        ])
        .order('created_at', ascending: false);

    // entryFromRow returns null when RLS hid the counterpart profile; those
    // rows have nothing renderable, so they are dropped rather than shown as
    // a blank card.
    return rows
        .map((row) => ConnectionMapper.entryFromRow(row, me))
        .nonNulls
        .toList();
  }

  @override
  Future<List<User>> fetchBlocked(String me) async {
    final rows = await _client
        .from('blocks')
        .select(ConnectionMapper.blockedSelect)
        .eq('blocker_id', me)
        .order('created_at', ascending: false);

    return rows.map(ConnectionMapper.blockedFromRow).nonNulls.toList();
  }

  @override
  Future<ConnectionEntry> sendRequest({
    required String me,
    required User other,
    required String purpose,
    String? message,
  }) async {
    try {
      final row = await _client
          .from('connections')
          .insert(ConnectionMapper.toInsert(
            requesterId: me,
            addresseeId: other.id,
            purpose: purpose,
            message: message,
          ))
          .select(ConnectionMapper.columns)
          .single();

      return ConnectionEntry(
        connection: ConnectionMapper.fromRow(row),
        other: other,
      );
    } on PostgrestException catch (e) {
      throw ConnectionFailure(_readableInsert(e));
    }
  }

  @override
  Future<Connection> updateState({
    required String me,
    required Connection connection,
    required ConnectionState state,
  }) async {
    try {
      final row = await _client
          .from('connections')
          .update(ConnectionMapper.toStateUpdate(state))
          .eq('id', connection.id)
          .select(ConnectionMapper.columns)
          .single();

      return ConnectionMapper.fromRow(row);
    } on PostgrestException catch (e) {
      throw ConnectionFailure(_readableTransition(e));
    }
  }

  @override
  Future<void> block({
    required String me,
    required User other,
    String? reason,
  }) async {
    try {
      await _client.from('blocks').insert({
        'blocker_id': me,
        'blocked_id': other.id,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
    } on PostgrestException catch (e) {
      // Already blocked is not an error worth showing — the outcome the
      // student asked for is already true.
      if (e.code == '23505') return;
      throw ConnectionFailure(_readable(e));
    }
  }

  @override
  Future<void> unblock({required String me, required String otherId}) async {
    try {
      await _client
          .from('blocks')
          .delete()
          .eq('blocker_id', me)
          .eq('blocked_id', otherId);
    } on PostgrestException catch (e) {
      throw ConnectionFailure(_readable(e));
    }
  }

  @override
  Future<void> report({
    required String me,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    try {
      await _client.from('reports').insert({
        'reporter_id': me,
        'target_type': 'profile',
        'target_id': targetId,
        'reason': reason.wire,
        if (details != null && details.trim().isNotEmpty)
          'details': details.trim(),
      });
    } on PostgrestException catch (e) {
      // The partial unique index stops one person filing the same open report
      // twice. From the student's side that already succeeded.
      if (e.code == '23505') return;
      throw ConnectionFailure(_readable(e));
    }
  }

  static String _readableInsert(PostgrestException e) {
    if (e.code == '23505') return 'You already have a request with this student.';
    // A failed WITH CHECK — rate limit, block, or another campus — comes back
    // as 42501 with no detail the student could act on beyond this.
    if (e.code == '42501') {
      return 'That request could not be sent. You may have reached the daily '
          'limit, or this student is no longer available.';
    }
    return _readable(e);
  }

  static String _readableTransition(PostgrestException e) {
    // Raised by tg_connection_transition.
    if (e.message.contains('already been answered')) {
      return 'This request has already been answered.';
    }
    if (e.message.contains('Only the recipient')) {
      return 'Only the recipient can accept or decline a request.';
    }
    if (e.message.contains('Only the sender')) {
      return 'Only the sender can withdraw a request.';
    }
    return _readable(e);
  }

  static String _readable(PostgrestException e) =>
      e.message.isEmpty ? 'Something went wrong. Please try again.' : e.message;
}

// =====================================================================
// Mock
// =====================================================================

/// In-memory connections over the generated students, so the app runs with no
/// credentials.
///
/// It enforces the same state machine as `tg_connection_transition`. That is
/// the point of a mock that is worth having: if a transition is illegal
/// against Postgres it has to be illegal here too, or Mock Mode teaches the
/// UI habits the real backend will reject.
class MockConnectionRepository implements ConnectionRepository {
  MockConnectionRepository({
    required List<User> Function() students,
    this.latency = const Duration(milliseconds: 250),
    this.seedDemoData = true,
  }) : _students = students;

  final List<User> Function() _students;
  final Duration latency;

  /// The demo starts with a populated Connections tab. Tests turn this off so
  /// they can assert on an empty graph rather than around the fixture.
  final bool seedDemoData;

  final List<Connection> _connections = [];
  final Set<String> _blockedIds = {};
  final Set<String> _reportedIds = {};

  bool _seeded = false;

  /// Nothing else on the device writes to the fixtures, so there is nothing
  /// for this to report. It stays open so the provider's subscription and
  /// teardown are the same code in both modes.
  @override
  Stream<void> changes(String me) => const Stream.empty();

  @override
  Future<void> close() async {}

  /// Pre-seeded relationships so the Connections tab is never empty in the
  /// demo. The layout matches what the provider used to hard-code, so the
  /// tabs show the same counts they always did:
  ///   students 0..2   pending, they asked me
  ///   students 3..17  connected  (6..17 are the ones that already have chats)
  ///   students 18..19 pending, I asked them
  void _seed(String me) {
    if (_seeded) return;
    _seeded = true;
    if (!seedDemoData) return;

    final all = _students();
    if (all.isEmpty) return;

    const purposes = ['Study Partner', 'Project Partner', 'Friendship'];
    final now = DateTime.now();

    void add(int index, ConnectionState state, String purpose,
        {required bool theyAsked}) {
      if (index >= all.length) return;
      final other = all[index];
      _connections.add(Connection(
        id: 'mock-connection-$index',
        requesterId: theyAsked ? other.id : me,
        addresseeId: theyAsked ? me : other.id,
        state: state,
        purpose: purpose,
        createdAt: now.subtract(Duration(hours: index + 1)),
        respondedAt: state == ConnectionState.accepted
            ? now.subtract(Duration(minutes: index + 1))
            : null,
      ));
    }

    for (var i = 0; i < 3; i++) {
      add(i, ConnectionState.pending, purposes[i], theyAsked: true);
    }
    for (var i = 3; i < 18; i++) {
      add(i, ConnectionState.accepted, 'Friendship', theyAsked: i.isEven);
    }
    for (var i = 18; i < 20; i++) {
      add(i, ConnectionState.pending, 'Networking', theyAsked: false);
    }
  }

  User? _studentById(String id) {
    for (final s in _students()) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<List<ConnectionEntry>> fetchEntries(String me) async {
    await _wait();
    _seed(me);

    final entries = <ConnectionEntry>[];
    for (final c in _connections) {
      if (!c.state.isLive || !c.involves(me)) continue;
      final other = _studentById(c.otherId(me));
      if (other == null) continue;
      if (_blockedIds.contains(other.id)) continue;
      entries.add(ConnectionEntry(connection: c, other: other));
    }

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  @override
  Future<List<User>> fetchBlocked(String me) async {
    await _wait();
    return _blockedIds.map(_studentById).nonNulls.toList();
  }

  @override
  Future<ConnectionEntry> sendRequest({
    required String me,
    required User other,
    required String purpose,
    String? message,
  }) async {
    await _wait();
    _seed(me);

    if (other.id == me) {
      throw const ConnectionFailure('You cannot connect with yourself.');
    }
    if (_blockedIds.contains(other.id)) {
      throw const ConnectionFailure('This student is not available.');
    }
    // Mirrors connections_active_pair_uniq: one live row per pair.
    final live = _liveBetween(me, other.id);
    if (live != null) {
      throw const ConnectionFailure(
          'You already have a request with this student.');
    }

    final connection = Connection(
      id: 'mock-connection-${DateTime.now().microsecondsSinceEpoch}',
      requesterId: me,
      addresseeId: other.id,
      state: ConnectionState.pending,
      purpose: purpose,
      message: message,
      createdAt: DateTime.now(),
    );
    _connections.add(connection);

    return ConnectionEntry(connection: connection, other: other);
  }

  @override
  Future<Connection> updateState({
    required String me,
    required Connection connection,
    required ConnectionState state,
  }) async {
    await _wait();

    final index = _connections.indexWhere((c) => c.id == connection.id);
    if (index == -1) {
      throw const ConnectionFailure('That request no longer exists.');
    }

    final current = _connections[index];
    _assertTransition(me, current, state);

    final updated = current.copyWith(state: state, respondedAt: DateTime.now());
    _connections[index] = updated;
    return updated;
  }

  /// The rules from `tg_connection_transition`, verbatim.
  void _assertTransition(String me, Connection current, ConnectionState next) {
    if (current.state == next) return;

    switch (current.state) {
      case ConnectionState.pending:
        if ((next == ConnectionState.accepted ||
                next == ConnectionState.declined) &&
            me != current.addresseeId) {
          throw const ConnectionFailure(
              'Only the recipient can accept or decline a request.');
        }
        if (next == ConnectionState.withdrawn && me != current.requesterId) {
          throw const ConnectionFailure(
              'Only the sender can withdraw a request.');
        }
      case ConnectionState.accepted:
        if (next != ConnectionState.cancelled) {
          throw const ConnectionFailure(
              'An accepted connection can only be cancelled.');
        }
      case ConnectionState.declined:
      case ConnectionState.cancelled:
      case ConnectionState.withdrawn:
        throw const ConnectionFailure('This request has already been answered.');
    }
  }

  @override
  Future<void> block({
    required String me,
    required User other,
    String? reason,
  }) async {
    await _wait();
    _blockedIds.add(other.id);

    // tg_block_severs_connection
    final live = _liveBetween(me, other.id);
    if (live != null) {
      final index = _connections.indexWhere((c) => c.id == live.id);
      _connections[index] = live.copyWith(
        state: ConnectionState.cancelled,
        respondedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> unblock({required String me, required String otherId}) async {
    await _wait();
    _blockedIds.remove(otherId);
  }

  @override
  Future<void> report({
    required String me,
    required String targetId,
    required ReportReason reason,
    String? details,
  }) async {
    await _wait();
    _reportedIds.add(targetId);
  }

  Connection? _liveBetween(String a, String b) {
    for (final c in _connections) {
      if (!c.state.isLive) continue;
      if ((c.requesterId == a && c.addresseeId == b) ||
          (c.requesterId == b && c.addresseeId == a)) {
        return c;
      }
    }
    return null;
  }
}

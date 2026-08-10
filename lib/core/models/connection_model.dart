import 'user_model.dart';

/// Mirrors `public.connection_state` in
/// `supabase/migrations/0001_extensions_and_types.sql`.
///
/// Serialised by name for the same reason the profile enums are: Postgres
/// enums are text on the wire, and ordinals would silently reinterpret every
/// stored row if a value were ever inserted mid-enum.
enum ConnectionState { pending, accepted, declined, cancelled, withdrawn }

extension ConnectionStateWire on ConnectionState {
  static const _names = {
    ConnectionState.pending: 'pending',
    ConnectionState.accepted: 'accepted',
    ConnectionState.declined: 'declined',
    ConnectionState.cancelled: 'cancelled',
    ConnectionState.withdrawn: 'withdrawn',
  };

  String get wire => _names[this]!;

  /// Still worth showing. `declined`, `withdrawn` and `cancelled` are terminal
  /// — the transition trigger in 0008 rejects any further change, so to the UI
  /// they are simply "no connection".
  bool get isLive =>
      this == ConnectionState.pending || this == ConnectionState.accepted;

  static ConnectionState parse(
    Object? value, {
    ConnectionState fallback = ConnectionState.pending,
  }) {
    if (value is ConnectionState) return value;
    if (value is String) {
      for (final entry in _names.entries) {
        if (entry.value == value) return entry.key;
      }
    }
    return fallback;
  }
}

/// How the signed-in student relates to another student, from *their* point of
/// view. This is what every screen switches on — it folds the row's direction
/// and the block list into one value so no widget has to work out "am I the
/// requester or the addressee" for itself.
enum ConnectionStatus {
  /// No live row between the two students. A previously declined or withdrawn
  /// request also lands here: it is history, and a fresh request is allowed.
  none,

  /// I sent it and it is still waiting on them.
  outgoing,

  /// They sent it and it is waiting on me.
  incoming,

  connected,

  /// I blocked them. Being blocked *by* someone is deliberately
  /// indistinguishable from [none] — the row is unreadable by design
  /// (`blocks_own` in 0008), which is what stops it becoming a harassment
  /// signal.
  blocked,
}

extension ConnectionStatusX on ConnectionStatus {
  bool get isConnected => this == ConnectionStatus.connected;
}

/// One row of `public.connections`.
class Connection {
  final String id;
  final String requesterId;
  final String addresseeId;
  final ConnectionState state;

  /// "Study Partner", "Project Partner" … shown on the request card.
  final String purpose;

  /// Optional note the requester attached (`connections.message`).
  final String? message;

  final DateTime createdAt;
  final DateTime? respondedAt;

  const Connection({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.state,
    this.purpose = 'Friendship',
    this.message,
    required this.createdAt,
    this.respondedAt,
  });

  bool involves(String userId) =>
      requesterId == userId || addresseeId == userId;

  /// The student on the other side of [me].
  String otherId(String me) => requesterId == me ? addresseeId : requesterId;

  /// How this row looks to [me].
  ConnectionStatus statusFor(String me) {
    switch (state) {
      case ConnectionState.accepted:
        return ConnectionStatus.connected;
      case ConnectionState.pending:
        return requesterId == me
            ? ConnectionStatus.outgoing
            : ConnectionStatus.incoming;
      case ConnectionState.declined:
      case ConnectionState.cancelled:
      case ConnectionState.withdrawn:
        return ConnectionStatus.none;
    }
  }

  Connection copyWith({
    ConnectionState? state,
    String? purpose,
    String? message,
    DateTime? respondedAt,
  }) {
    return Connection(
      id: id,
      requesterId: requesterId,
      addresseeId: addresseeId,
      state: state ?? this.state,
      purpose: purpose ?? this.purpose,
      message: message ?? this.message,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}

/// A connection row together with the other student's profile.
///
/// The two travel as a pair because every screen that shows a connection also
/// shows a name and an avatar; fetching them separately would be an N+1 on the
/// Connections tab.
class ConnectionEntry {
  final Connection connection;
  final User other;

  const ConnectionEntry({required this.connection, required this.other});

  String get id => connection.id;
  ConnectionState get state => connection.state;
  String get purpose => connection.purpose;
  DateTime get createdAt => connection.createdAt;

  ConnectionStatus statusFor(String me) => connection.statusFor(me);

  ConnectionEntry copyWith({Connection? connection, User? other}) =>
      ConnectionEntry(
        connection: connection ?? this.connection,
        other: other ?? this.other,
      );
}

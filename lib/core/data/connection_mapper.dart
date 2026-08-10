import '../models/connection_model.dart';
import '../models/user_model.dart';
import 'profile_mapper.dart';

/// Translates `public.connections` and `public.blocks` rows into the models
/// the Connections tab speaks.
///
/// Same reasoning as [ProfileMapper]: the column names follow Postgres
/// convention, the models follow Dart's, and doing the renaming once keeps
/// that difference out of every screen.
class ConnectionMapper {
  const ConnectionMapper._();

  /// Listed explicitly rather than `*` so adding a column to `connections`
  /// cannot silently change what the Connections tab downloads.
  static const columns =
      'id, requester_id, addressee_id, state, purpose, message, '
      'created_at, responded_at';

  /// The counterpart profile, embedded. Badges are left out on purpose — the
  /// request and connection cards do not render them, and the extra join
  /// would be paid on every row.
  ///
  /// The `!connections_requester_id_fkey` hints are required, not decorative:
  /// `connections` has two foreign keys to `profiles`, and PostgREST refuses
  /// to guess between them.
  static String get selectWithProfiles => '''
    $columns,
    requester:profiles!connections_requester_id_fkey($_embeddedProfile),
    addressee:profiles!connections_addressee_id_fkey($_embeddedProfile)
  ''';

  static String get _embeddedProfile => '''
    ${ProfileMapper.columns},
    user_presence(is_online, last_active)
  ''';

  /// `blocks` joined to the blocked student, for the Privacy Settings list.
  static String get blockedSelect => '''
    blocked_id, created_at,
    blocked:profiles!blocks_blocked_id_fkey($_embeddedProfile)
  ''';

  static Connection fromRow(Map<String, dynamic> row) {
    return Connection(
      id: row['id'] as String,
      requesterId: row['requester_id'] as String,
      addresseeId: row['addressee_id'] as String,
      state: ConnectionStateWire.parse(row['state']),
      // `purpose` is nullable in the schema; the cards always want something.
      purpose: (row['purpose'] as String?)?.trim().isNotEmpty == true
          ? row['purpose'] as String
          : 'Friendship',
      message: row['message'] as String?,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      respondedAt: _parseDate(row['responded_at']),
    );
  }

  /// Pairs the row with whichever embedded profile is *not* [me].
  ///
  /// Returns null when the counterpart profile is missing, which happens when
  /// RLS hides them — deleted, deactivated, or a block went up between the
  /// connection being made and this read. Dropping the entry is right: there
  /// is no name or avatar to render, and inventing a placeholder would put a
  /// ghost row in the Connections tab.
  static ConnectionEntry? entryFromRow(Map<String, dynamic> row, String me) {
    final connection = fromRow(row);
    final raw = connection.requesterId == me
        ? row['addressee']
        : row['requester'];

    final profile = _asRow(raw);
    if (profile == null) return null;

    return ConnectionEntry(
      connection: connection,
      other: ProfileMapper.fromRow(profile),
    );
  }

  static User? blockedFromRow(Map<String, dynamic> row) {
    final profile = _asRow(row['blocked']);
    return profile == null ? null : ProfileMapper.fromRow(profile);
  }

  static Map<String, dynamic> toInsert({
    required String requesterId,
    required String addresseeId,
    required String purpose,
    String? message,
  }) {
    return <String, dynamic>{
      'requester_id': requesterId,
      'addressee_id': addresseeId,
      // The insert policy in 0008 requires this explicitly; relying on the
      // column default would still pass, but being explicit documents that
      // the policy is checking it.
      'state': ConnectionState.pending.wire,
      'purpose': purpose,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    };
  }

  /// The transition trigger stamps `responded_at` itself, so this only
  /// carries the new state.
  static Map<String, dynamic> toStateUpdate(ConnectionState state) =>
      <String, dynamic>{'state': state.wire};

  /// PostgREST returns a to-one embed as an object, but falls back to a list
  /// when it cannot prove the relationship is unique. Accept both rather than
  /// depending on which side it picks — the same defensiveness
  /// [ProfileMapper] applies to `user_presence`.
  static Map<String, dynamic>? _asRow(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

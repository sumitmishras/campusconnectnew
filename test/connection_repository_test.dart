import 'package:campus_connect/core/data/connection_mapper.dart';
import 'package:campus_connect/core/data/repositories/connection_repository.dart';
import 'package:campus_connect/core/models/connection_model.dart';
import 'package:campus_connect/core/models/report_reason.dart';
import 'package:campus_connect/core/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'me';

User _student(String id, {String name = 'Bhavya Singh'}) => User(
      id: id,
      name: name,
      username: id,
      email: '$id@cuchd.in',
      uid: '21BCS0000',
      phoneNumber: '',
      department: 'Computer Science',
      course: 'B.E. CSE',
      year: '3rd Year',
      bio: '',
      interests: const [],
      languages: const [],
      lookingFor: const [],
      profilePhotoUrl: '',
      lastActive: DateTime(2026, 1, 1),
    );

void main() {
  late List<User> fixture;
  late MockConnectionRepository repo;

  setUp(() {
    fixture = [_student('a'), _student('b'), _student('c')];
    repo = MockConnectionRepository(
      students: () => fixture,
      latency: Duration.zero,
      seedDemoData: false,
    );
  });

  Future<ConnectionEntry> send(String id, {String purpose = 'Friendship'}) =>
      repo.sendRequest(
        me: _me,
        other: fixture.firstWhere((u) => u.id == id),
        purpose: purpose,
      );

  group('sending', () {
    test('a request starts pending and outgoing', () async {
      final entry = await send('a', purpose: 'Study Partner');

      expect(entry.state, ConnectionState.pending);
      expect(entry.connection.requesterId, _me);
      expect(entry.connection.addresseeId, 'a');
      expect(entry.purpose, 'Study Partner');
      expect(entry.statusFor(_me), ConnectionStatus.outgoing);
    });

    test('it comes back from fetchEntries', () async {
      await send('a');
      final entries = await repo.fetchEntries(_me);
      expect(entries.map((e) => e.other.id), ['a']);
    });

    test('a second live request to the same student is refused', () async {
      await send('a');
      expect(
        () => send('a'),
        throwsA(isA<ConnectionFailure>()),
      );
    });

    test('connecting with yourself is refused', () async {
      expect(
        () => repo.sendRequest(
            me: _me, other: _student(_me), purpose: 'Friendship'),
        throwsA(isA<ConnectionFailure>()),
      );
    });
  });

  group('the state machine', () {
    // These mirror tg_connection_transition. If a move is illegal against
    // Postgres it has to be illegal here, or Mock Mode teaches the UI habits
    // the real backend will reject.

    test('the addressee can accept', () async {
      final entry = await send('a');
      final updated = await repo.updateState(
        me: 'a',
        connection: entry.connection,
        state: ConnectionState.accepted,
      );
      expect(updated.state, ConnectionState.accepted);
      expect(updated.statusFor(_me), ConnectionStatus.connected);
      expect(updated.statusFor('a'), ConnectionStatus.connected);
    });

    test('the requester cannot accept their own request', () async {
      final entry = await send('a');
      expect(
        () => repo.updateState(
          me: _me,
          connection: entry.connection,
          state: ConnectionState.accepted,
        ),
        throwsA(isA<ConnectionFailure>()),
      );
    });

    test('only the sender can withdraw', () async {
      final entry = await send('a');
      expect(
        () => repo.updateState(
          me: 'a',
          connection: entry.connection,
          state: ConnectionState.withdrawn,
        ),
        throwsA(isA<ConnectionFailure>()),
      );

      final updated = await repo.updateState(
        me: _me,
        connection: entry.connection,
        state: ConnectionState.withdrawn,
      );
      expect(updated.state, ConnectionState.withdrawn);
    });

    test('an accepted connection can only be cancelled', () async {
      final entry = await send('a');
      final accepted = await repo.updateState(
        me: 'a',
        connection: entry.connection,
        state: ConnectionState.accepted,
      );

      expect(
        () => repo.updateState(
          me: _me,
          connection: accepted,
          state: ConnectionState.declined,
        ),
        throwsA(isA<ConnectionFailure>()),
      );

      final cancelled = await repo.updateState(
        me: _me,
        connection: accepted,
        state: ConnectionState.cancelled,
      );
      expect(cancelled.state, ConnectionState.cancelled);
    });

    test('declined, withdrawn and cancelled are terminal', () async {
      final entry = await send('a');
      final declined = await repo.updateState(
        me: 'a',
        connection: entry.connection,
        state: ConnectionState.declined,
      );

      expect(
        () => repo.updateState(
          me: 'a',
          connection: declined,
          state: ConnectionState.accepted,
        ),
        throwsA(isA<ConnectionFailure>()),
      );
    });

    test('a terminal row disappears from fetchEntries', () async {
      final entry = await send('a');
      await repo.updateState(
        me: 'a',
        connection: entry.connection,
        state: ConnectionState.declined,
      );

      expect(await repo.fetchEntries(_me), isEmpty);
    });

    test('a declined request does not block a fresh one later', () async {
      final entry = await send('a');
      await repo.updateState(
        me: 'a',
        connection: entry.connection,
        state: ConnectionState.declined,
      );

      final again = await send('a');
      expect(again.state, ConnectionState.pending);
    });
  });

  group('blocking', () {
    test('blocking severs a live connection', () async {
      final entry = await send('a');
      await repo.updateState(
        me: 'a',
        connection: entry.connection,
        state: ConnectionState.accepted,
      );

      await repo.block(me: _me, other: fixture.first);

      expect(await repo.fetchEntries(_me), isEmpty);
      expect((await repo.fetchBlocked(_me)).map((u) => u.id), ['a']);
    });

    test('blocking someone with a pending request also clears it', () async {
      await send('a');
      await repo.block(me: _me, other: fixture.first);
      expect(await repo.fetchEntries(_me), isEmpty);
    });

    test('unblocking removes them from the list', () async {
      await repo.block(me: _me, other: fixture.first);
      await repo.unblock(me: _me, otherId: 'a');
      expect(await repo.fetchBlocked(_me), isEmpty);
    });

    test('a request to a blocked student is refused', () async {
      await repo.block(me: _me, other: fixture.first);
      expect(() => send('a'), throwsA(isA<ConnectionFailure>()));
    });
  });

  group('reporting', () {
    test('a report is accepted for every reason the schema allows', () async {
      for (final reason in ReportReason.values) {
        await repo.report(me: _me, targetId: 'a', reason: reason);
      }
    });
  });

  group('demo seed', () {
    test('produces the counts the Connections tab starts with', () async {
      final students = List.generate(25, (i) => _student('s$i'));
      final seeded = MockConnectionRepository(
        students: () => students,
        latency: Duration.zero,
      );

      final entries = await seeded.fetchEntries(_me);
      final incoming = entries
          .where((e) => e.statusFor(_me) == ConnectionStatus.incoming)
          .length;
      final outgoing = entries
          .where((e) => e.statusFor(_me) == ConnectionStatus.outgoing)
          .length;
      final connected = entries
          .where((e) => e.statusFor(_me) == ConnectionStatus.connected)
          .length;

      expect(incoming, 3);
      expect(outgoing, 2);
      expect(connected, 15);
    });
  });

  group('wire encoding', () {
    test('states use the labels from public.connection_state', () {
      expect(ConnectionState.pending.wire, 'pending');
      expect(ConnectionState.accepted.wire, 'accepted');
      expect(ConnectionState.declined.wire, 'declined');
      expect(ConnectionState.cancelled.wire, 'cancelled');
      expect(ConnectionState.withdrawn.wire, 'withdrawn');
    });

    test('states round-trip', () {
      for (final state in ConnectionState.values) {
        expect(ConnectionStateWire.parse(state.wire), state);
      }
    });

    test('an unknown state falls back rather than throwing', () {
      expect(ConnectionStateWire.parse('who_knows'), ConnectionState.pending);
      expect(ConnectionStateWire.parse(null), ConnectionState.pending);
    });

    test('report reasons use the values the CHECK constraint allows', () {
      // Exactly the list in 0006_notifications_and_moderation.sql.
      const allowed = {
        'spam',
        'harassment',
        'hate_speech',
        'nudity',
        'impersonation',
        'scam',
        'self_harm',
        'other',
      };
      for (final reason in ReportReason.values) {
        expect(allowed, contains(reason.wire), reason: reason.name);
      }
    });

    test('the profile report sheet still offers its five labels', () {
      expect(kProfileReportReasons.map((r) => r.label), [
        'Fake or impersonating profile',
        'Harassment or bullying',
        'Inappropriate content',
        'Spam or scam',
        'Something else',
      ]);
    });
  });

  group('ConnectionMapper', () {
    Map<String, dynamic> profileRow(String id, String name) => {
          'id': id,
          'full_name': name,
          'username': id,
          'university_uid': '21bcs0000',
          'admission_year': 2021,
          'hide_active_status': false,
        };

    Map<String, dynamic> row({
      String requester = _me,
      String addressee = 'a',
      String state = 'pending',
    }) =>
        {
          'id': 'row-1',
          'requester_id': requester,
          'addressee_id': addressee,
          'state': state,
          'purpose': 'Study Partner',
          'message': null,
          'created_at': '2026-08-01T10:00:00Z',
          'responded_at': null,
          'requester': profileRow(requester, 'Me Myself'),
          'addressee': profileRow(addressee, 'Bhavya Singh'),
        };

    test('maps the columns onto the model', () {
      final connection = ConnectionMapper.fromRow(row());
      expect(connection.id, 'row-1');
      expect(connection.state, ConnectionState.pending);
      expect(connection.purpose, 'Study Partner');
      expect(connection.requesterId, _me);
    });

    test('picks whichever embedded profile is not me', () {
      final outgoing = ConnectionMapper.entryFromRow(row(), _me);
      expect(outgoing!.other.id, 'a');

      final incoming = ConnectionMapper.entryFromRow(
          row(requester: 'a', addressee: _me), _me);
      expect(incoming!.other.id, 'a');
    });

    test('a row whose counterpart RLS hid is dropped, not rendered blank', () {
      final hidden = row()..remove('addressee');
      expect(ConnectionMapper.entryFromRow(hidden, _me), isNull);
    });

    test('a null purpose still gives the card something to show', () {
      final entry =
          ConnectionMapper.fromRow(row()..['purpose'] = null);
      expect(entry.purpose, 'Friendship');
    });

    test('the insert carries an explicit pending state', () {
      final insert = ConnectionMapper.toInsert(
        requesterId: _me,
        addresseeId: 'a',
        purpose: 'Networking',
      );
      expect(insert['state'], 'pending');
      expect(insert['requester_id'], _me);
      expect(insert.containsKey('message'), isFalse);
    });

    test('the state update sends only the state — the trigger stamps the rest',
        () {
      expect(ConnectionMapper.toStateUpdate(ConnectionState.accepted),
          {'state': 'accepted'});
    });
  });
}

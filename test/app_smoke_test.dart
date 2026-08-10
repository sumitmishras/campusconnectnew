import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_connect/main.dart';
import 'package:campus_connect/core/data/repositories/repositories.dart';
import 'package:campus_connect/features/campus_hub/screens/clubs_screen.dart';
import 'package:campus_connect/features/campus_hub/screens/events_screen.dart';
import 'package:campus_connect/features/campus_hub/screens/notifications_screen.dart';
import 'package:campus_connect/features/campus_hub/screens/polls_screen.dart';
import 'package:campus_connect/features/chat/screens/chat_detail_screen.dart';
import 'package:campus_connect/features/navigation/main_navigation.dart';
import 'package:campus_connect/features/profile/screens/edit_profile_screen.dart';
import 'package:campus_connect/features/profile/screens/settings_screen.dart';
import 'package:campus_connect/features/profile/screens/student_profile_screen.dart';

import 'support/fake_chat_repository.dart';

const _savedProfile =
    '{"id":"me","name":"Sumit Mishra","username":"21bcs5084",'
    '"email":"21bcs5084@cuchd.in","uid":"21BCS5084","phoneNumber":"",'
    '"gender":"Male","department":"Computer Science","course":"B.E. CSE",'
    '"year":"4th Year","bio":"Hello","interests":["Coding"],'
    '"languages":["Hindi"],"lookingFor":["Study Partner"],'
    '"profilePhotoUrl":"","trustLevel":1,"verificationLevel":3,'
    '"badges":[],"achievements":[],"campusStatus":null,'
    '"hideDepartment":false,"hideYear":false,'
    '"hideLookingFor":false,"hideActiveStatus":false}';

/// Boots the app straight into the signed-in state.
Future<void> _pumpSignedIn(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'cc_known_accounts': ['21bcs5084'],
    'cc_profile': _savedProfile,
  });
  // Chat talks to Postgres or to nothing, so the Chats tab is driven from a
  // test double here.
  Repositories.overrideForTest(
    chat: FakeChatRepository(seed: fakeChatSeed(), members: fakeMembers()),
  );
  await tester.pumpWidget(const CampusConnectApp());
  await tester.pumpAndSettle();
  expect(find.byType(MainNavigation), findsOneWidget);
}

/// The screens use a custom chevron instead of the Material back button,
/// so `tester.pageBack()` does not apply.
Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.chevronLeft).first);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  // Repositories caches its instances, and the mock connection repository is
  // now the source of truth for who is connected to whom. Without this, a
  // request sent in one test is still there in the next one and the tab
  // counts drift.
  setUp(Repositories.reset);
  tearDown(Repositories.reset);

  testWidgets('Discover: search, quick filters and advanced filters work',
      (tester) async {
    await _pumpSignedIn(tester);

    // The list is populated.
    expect(find.textContaining('students match'), findsOneWidget);

    // A quick filter narrows the list.
    await tester.tap(find.text('Same Department'));
    await tester.pumpAndSettle();
    expect(find.textContaining('students match'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    // Search with a term that cannot match anything.
    await tester.enterText(find.byType(TextField).first, 'zzzzzzz');
    await tester.pumpAndSettle();
    expect(find.text('No students found'), findsOneWidget);

    // The empty-state action clears everything.
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('students match'), findsOneWidget);

    // Advanced filters sheet opens and applies.
    await tester.tap(find.byIcon(LucideIcons.slidersHorizontal));
    await tester.pumpAndSettle();
    expect(find.text('Advanced Filters'), findsOneWidget);
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
  });

  testWidgets('Discover: a student card opens the profile and connects',
      (tester) async {
    await _pumpSignedIn(tester);

    // The first students already have a pending request or connection, so
    // scroll down until we reach one with a plain "Connect" button.
    //
    // pumpAndSettle, not pump: the list is paginated now, so reaching the
    // bottom kicks off a fetch that has to land before the next page of
    // cards exists to scroll onto.
    final connectButton = find.widgetWithText(ElevatedButton, 'Connect');
    var attempts = 0;
    while (connectButton.evaluate().isEmpty && attempts < 30) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      attempts++;
    }
    expect(connectButton, findsWidgets);

    await _tapVisible(tester, connectButton.first);
    expect(find.byType(StudentProfileScreen), findsOneWidget);

    // Connect opens the purpose sheet, picking one sends the request.
    final profileConnect = find.descendant(
      of: find.byType(StudentProfileScreen),
      matching: find.widgetWithText(ElevatedButton, 'Connect'),
    );
    await tester.ensureVisible(profileConnect);
    await tester.pumpAndSettle();
    // ensureVisible parks it right under the transparent app bar, so nudge
    // the sheet back down before tapping.
    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, 140));
    await tester.pumpAndSettle();
    await tester.tap(profileConnect);
    await tester.pumpAndSettle();
    expect(find.text('Send Connection Request'), findsOneWidget);

    await tester.tap(find.text('Study Partner'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ElevatedButton, 'Requested'), findsOneWidget);
  });

  testWidgets('Hub: cards navigate and join buttons toggle', (tester) async {
    await _pumpSignedIn(tester);

    await tester.tap(find.byIcon(LucideIcons.layoutGrid));
    await tester.pumpAndSettle();
    expect(find.text('Campus Hub'), findsOneWidget);

    // Notifications.
    await tester.tap(find.byIcon(LucideIcons.bell));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    await _back(tester);

    // Events.
    await _tapVisible(tester, find.text('Events'));
    expect(find.byType(EventsScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Join Event').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Going'), findsWidgets);

    // Category filter.
    await tester.tap(find.text('Sports'));
    await tester.pumpAndSettle();
    await _back(tester);

    // Clubs.
    await _tapVisible(tester, find.text('Clubs'));
    expect(find.byType(ClubsScreen), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Join Club').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Joined'), findsWidgets);
    await _back(tester);

    // Polls — voting locks in a percentage.
    await _tapVisible(tester, find.text('Polls'));
    expect(find.byType(PollsScreen), findsOneWidget);
    expect(find.textContaining('Tap an option to vote'), findsWidgets);
    await tester.tap(find.text('Block 1 Mess'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You voted'), findsWidgets);
  });

  testWidgets('Connections: accept, decline and withdraw all work',
      (tester) async {
    await _pumpSignedIn(tester);

    await tester.tap(find.byIcon(LucideIcons.users));
    await tester.pumpAndSettle();
    expect(find.textContaining('Received (3)'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Accept').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Received (2)'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Received (1)'), findsOneWidget);

    // Sent tab — withdraw a request.
    await tester.tap(find.textContaining('Sent ('));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sent (1)'), findsOneWidget);
  });

  testWidgets('Chats: open a thread and send a message', (tester) async {
    await _pumpSignedIn(tester);

    await tester.tap(find.byIcon(LucideIcons.messageCircle).first);
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsWidgets);

    // Group threads sit above direct ones, so narrow the list first.
    await tester.tap(find.textContaining('Direct ('));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(ChatDetailScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Hey, all good?');
    await tester.tap(find.byIcon(LucideIcons.send));
    await tester.pump();
    expect(find.text('Hey, all good?'), findsOneWidget);

    // The other student replies after a short delay.
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('Profile: settings and edit profile open, saving works',
      (tester) async {
    await _pumpSignedIn(tester);

    await tester.tap(find.byIcon(LucideIcons.user).last);
    await tester.pumpAndSettle();
    expect(find.text('Sumit Mishra'), findsWidgets);
    expect(find.textContaining('21BCS5084'), findsOneWidget);

    // Settings screen.
    await tester.tap(find.byIcon(LucideIcons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _back(tester);

    // Edit profile and save a new name.
    await _tapVisible(tester, find.text('Edit Profile'));
    expect(find.byType(EditProfileScreen), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Sumit Mishra'), 'Sumit M');
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Sumit M'), findsWidgets);
  });
}

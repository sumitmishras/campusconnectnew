import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_connect/main.dart';
import 'package:campus_connect/core/data/repositories/repositories.dart';
import 'package:campus_connect/features/campus_hub/screens/communities_screen.dart';
import 'package:campus_connect/features/chat/screens/group_chat_screen.dart';
import 'package:campus_connect/features/navigation/main_navigation.dart';

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

Future<void> _pumpSignedIn(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'cc_known_accounts': ['21bcs5084'],
    'cc_profile': _savedProfile,
  });
  // Chat is a server feature with no offline implementation, so the Chats tab
  // is driven from a test double rather than from fixtures in the app.
  Repositories.overrideForTest(
    chat: FakeChatRepository(seed: fakeChatSeed(), members: fakeMembers()),
  );
  await tester.pumpWidget(const CampusConnectApp());
  await tester.pumpAndSettle();
  expect(find.byType(MainNavigation), findsOneWidget);
}

Future<void> _openChatsTab(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.messageCircle).first);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(Repositories.reset);
  tearDown(Repositories.reset);

  testWidgets('joined groups show up in Chats under a Groups section',
      (tester) async {
    await _pumpSignedIn(tester);
    await _openChatsTab(tester);

    expect(find.text('GROUPS'), findsOneWidget);
    expect(find.text('DIRECT MESSAGES'), findsOneWidget);
    // Seeded memberships: two communities, one club, one study group.
    expect(find.textContaining('Groups (4)'), findsOneWidget);
    expect(find.text('Computer Science Hub'), findsOneWidget);
  });

  testWidgets('the Groups filter shows only group threads', (tester) async {
    await _pumpSignedIn(tester);
    await _openChatsTab(tester);

    await tester.tap(find.textContaining('Groups ('));
    await tester.pumpAndSettle();

    expect(find.text('GROUPS'), findsOneWidget);
    expect(find.text('DIRECT MESSAGES'), findsNothing);
  });

  testWidgets('a group thread opens and accepts a message', (tester) async {
    await _pumpSignedIn(tester);
    await _openChatsTab(tester);

    await tester.tap(find.text('Computer Science Hub'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupChatScreen), findsOneWidget);
    // Seeded conversation from other members is visible.
    expect(find.textContaining('members'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, 'Hi everyone!');
    await tester.tap(find.byIcon(LucideIcons.send));
    await tester.pumpAndSettle();
    expect(find.text('Hi everyone!'), findsOneWidget);
  });

  testWidgets('group info sheet lists members', (tester) async {
    await _pumpSignedIn(tester);
    await _openChatsTab(tester);

    await tester.tap(find.text('Computer Science Hub'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.info));
    await tester.pumpAndSettle();

    expect(find.text('Members'), findsOneWidget);
    expect(find.textContaining('Community •'), findsOneWidget);
  });

  testWidgets('joining a community adds its chat, leaving removes it',
      (tester) async {
    await _pumpSignedIn(tester);

    // Hub -> Communities
    await tester.tap(find.byIcon(LucideIcons.layoutGrid));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Communities'));
    expect(find.byType(CommunitiesScreen), findsOneWidget);

    // Join the first community that is not joined yet.
    final joinButton = find.widgetWithText(ElevatedButton, 'Join').first;
    await _tapVisible(tester, joinButton);
    expect(find.widgetWithText(OutlinedButton, 'Joined'), findsWidgets);

    // Its chat is now reachable straight from the card.
    await _tapVisible(
        tester, find.byIcon(LucideIcons.messageCircle).first);
    expect(find.byType(GroupChatScreen), findsOneWidget);

    // Leave from the group menu — the thread disappears.
    await tester.tap(find.byIcon(LucideIcons.moreVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Leave'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupChatScreen), findsNothing);
    expect(find.byType(CommunitiesScreen), findsOneWidget);
  });
}

import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_connect/main.dart';
import 'package:campus_connect/core/data/repositories/repositories.dart';
import 'package:campus_connect/core/models/chat_model.dart';
import 'package:campus_connect/core/services/attachment_service.dart';
import 'package:campus_connect/features/chat/screens/chat_detail_screen.dart';
import 'package:campus_connect/features/navigation/main_navigation.dart';

import 'support/fake_chat_repository.dart';
import 'support/fake_file_picker.dart';

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

late FakeChatRepository chatRepo;

Future<void> _openDirectChat(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'cc_known_accounts': ['21bcs5084'],
    'cc_profile': _savedProfile,
  });
  chatRepo = FakeChatRepository(seed: fakeChatSeed(), members: fakeMembers());
  Repositories.overrideForTest(chat: chatRepo);

  await tester.pumpWidget(const CampusConnectApp());
  await tester.pumpAndSettle();
  expect(find.byType(MainNavigation), findsOneWidget);

  await tester.tap(find.byIcon(LucideIcons.messageCircle).first);
  await tester.pumpAndSettle();

  // The filter chips scroll horizontally on narrow screens.
  final directChip = find.textContaining('Direct (');
  await tester.ensureVisible(directChip);
  await tester.pumpAndSettle();
  await tester.tap(directChip);
  await tester.pumpAndSettle();

  await tester.tap(find.byType(ListTile).first);
  await tester.pumpAndSettle();
  expect(find.byType(ChatDetailScreen), findsOneWidget);
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.paperclip));
  await tester.pumpAndSettle();
  expect(find.text('Share a file'), findsOneWidget);
}

void main() {
  group('attachment rules', () {
    test('the limit is 5 MB', () {
      expect(AttachmentService.maxBytes, 5 * 1024 * 1024);
      expect(AttachmentService.maxLabel, '5 MB');
    });

    test('a photo and a document under the limit are accepted', () {
      const photo = Attachment(
        type: AttachmentType.photo,
        name: 'notes.jpg',
        sizeBytes: 2 * 1024 * 1024,
      );
      const doc = Attachment(
        type: AttachmentType.document,
        name: 'unit3.pdf',
        sizeBytes: 900 * 1024,
      );
      expect(AttachmentService.rejectionReason(photo), isNull);
      expect(AttachmentService.rejectionReason(doc), isNull);
    });

    test('anything over 5 MB is rejected with the size in the message', () {
      const big = Attachment(
        type: AttachmentType.photo,
        name: 'huge.jpg',
        sizeBytes: 6 * 1024 * 1024,
      );
      final reason = AttachmentService.rejectionReason(big);
      expect(reason, isNotNull);
      expect(reason, contains('6.0 MB'));
      expect(reason, contains('5 MB'));
    });

    test('unsupported file types are rejected', () {
      const video = Attachment(
        type: AttachmentType.document,
        name: 'clip.mp4',
        sizeBytes: 1024,
      );
      const audio = Attachment(
        type: AttachmentType.photo,
        name: 'song.mp3',
        sizeBytes: 1024,
      );
      expect(AttachmentService.rejectionReason(video), isNotNull);
      expect(AttachmentService.rejectionReason(audio), isNotNull);
    });

    test('an empty file is rejected', () {
      const empty = Attachment(
        type: AttachmentType.document,
        name: 'notes.pdf',
        sizeBytes: 0,
      );
      expect(AttachmentService.rejectionReason(empty), contains('empty'));
    });

    test('sizes are shown in KB or MB', () {
      const kb = Attachment(
          type: AttachmentType.document, name: 'a.pdf', sizeBytes: 480 * 1024);
      const mb = Attachment(
          type: AttachmentType.photo,
          name: 'b.jpg',
          sizeBytes: (2.5 * 1024 * 1024) ~/ 1);
      expect(kb.readableSize, '480 KB');
      expect(mb.readableSize, '2.5 MB');
    });
  });

  group('chat attachments', () {
    late FakeFilePicker picker;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      Repositories.reset();
      picker = FakeFilePicker();
      FilePickerPlatform.instance = picker;
    });
    tearDown(Repositories.reset);

    testWidgets('calling has been removed from the chat header',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDirectChat(tester);

      expect(find.byIcon(LucideIcons.phone), findsNothing);
      expect(find.textContaining('Calling'), findsNothing);
      // The attachment button is still there.
      expect(find.byIcon(LucideIcons.paperclip), findsOneWidget);
    });

    testWidgets('the sheet offers photos and documents, capped at 5 MB',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDirectChat(tester);
      await _openPicker(tester);

      expect(find.text('Max 5 MB'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
      // No location / audio / video options.
      expect(find.text('Location'), findsNothing);
    });

    testWidgets('a photo from the device is sent and rendered', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDirectChat(tester);
      await _openPicker(tester);

      picker.offer('campus.png', tinyPngBytes);
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      // The device picker was asked for images specifically.
      expect(picker.lastType, FileType.image);
      // Sheet closed, bubble rendered from the real bytes, message sent.
      expect(find.text('Share a file'), findsNothing);
      expect(find.textContaining('campus.png'), findsWidgets);
      expect(chatRepo.calls.where((c) => c.startsWith('send:')), hasLength(1));
    });

    testWidgets('a document from the device is sent with its type and size',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDirectChat(tester);
      await _openPicker(tester);

      picker.offer('DBMS Unit-3 Notes.pdf', textBytes('unit three notes'));
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      // Documents are filtered to the extensions the database will accept.
      expect(picker.lastType, FileType.custom);
      expect(picker.lastAllowedExtensions,
          AttachmentService.documentExtensions);
      expect(find.text('Share a file'), findsNothing);
      expect(find.text('DBMS Unit-3 Notes.pdf'), findsOneWidget);
      expect(find.textContaining('PDF •'), findsOneWidget);
    });

    testWidgets('an oversized file is refused before anything is sent',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDirectChat(tester);
      await _openPicker(tester);

      picker.offer('farewell.jpg', bytesOfSize(6 * 1024 * 1024));
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      // The sheet stays open and explains why.
      expect(find.text('Share a file'), findsOneWidget);
      expect(find.textContaining('the limit is 5 MB'), findsOneWidget);
      expect(find.textContaining('6.0 MB'), findsOneWidget);
      expect(chatRepo.calls.where((c) => c.startsWith('send:')), isEmpty);
    });

    testWidgets('an unsupported type is refused', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDirectChat(tester);
      await _openPicker(tester);

      // A picker on some platforms will hand back whatever the user chose.
      picker.offer('clip.mp4', bytesOfSize(2048));
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(find.text('Share a file'), findsOneWidget);
      expect(find.textContaining('images can be shared'), findsOneWidget);
      expect(chatRepo.calls.where((c) => c.startsWith('send:')), isEmpty);
    });

    testWidgets('cancelling the device picker sends nothing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _openDirectChat(tester);
      await _openPicker(tester);

      picker.next = null;
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      expect(find.text('Share a file'), findsOneWidget);
      expect(chatRepo.calls.where((c) => c.startsWith('send:')), isEmpty);
    });
  });
}

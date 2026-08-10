import 'package:flutter/material.dart';
import 'package:campus_connect/core/data/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_connect/main.dart';
import 'package:campus_connect/features/auth/screens/email_login_screen.dart';
import 'package:campus_connect/features/auth/screens/otp_screen.dart';
import 'package:campus_connect/features/auth/screens/registration_wizard.dart';
import 'package:campus_connect/features/auth/screens/welcome_screen.dart';
import 'package:campus_connect/features/navigation/main_navigation.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Repositories caches its instances; a leaked mock store would sign the
    // next test in before it starts.
    Repositories.reset();
  });

  testWidgets('a @cuchd.in student can sign in and reach the app',
      (tester) async {
    await tester.pumpWidget(const CampusConnectApp());
    await tester.pumpAndSettle();

    // 1. Welcome screen.
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    // 2. Enter the CU email.
    expect(find.byType(EmailLoginScreen), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '21bcs5084@cuchd.in');
    await tester.pump();

    // The decoded university id is shown back to the student.
    expect(find.text('21BCS5084'), findsOneWidget);

    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 3. OTP screen — tap the demo banner to autofill and verify.
    expect(find.byType(OTPScreen), findsOneWidget);
    await tester.tap(find.textContaining('Demo mode'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 4. First time in, so the profile wizard opens.
    expect(find.byType(RegistrationWizard), findsOneWidget);

    // Step 1 — basic info.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Enter your full name'),
        'Sumit Mishra');
    await tester.tap(find.text('Male'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2 — academics are pre-filled from the UID.
    expect(find.text('Computer Science'), findsWidgets);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3 — pick an interest and a purpose.
    await tester.ensureVisible(find.text('Coding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coding'));
    await tester.pump();

    await tester.ensureVisible(find.text('Study Partner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Study Partner'));
    await tester.pump();

    await tester.tap(find.text('Complete Profile'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 5. We are inside the app.
    expect(find.byType(MainNavigation), findsOneWidget);
    expect(find.text('Discover'), findsWidgets);
  });

  testWidgets('a non-CU email is rejected', (tester) async {
    await tester.pumpWidget(const CampusConnectApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).first, '21bcs5084@gmail.com');
    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Only @cuchd.in'), findsOneWidget);
    expect(find.byType(OTPScreen), findsNothing);
  });

  testWidgets('a returning student skips the wizard', (tester) async {
    // A profile already cached on the device for this university id.
    SharedPreferences.setMockInitialValues({
      'cc_known_accounts': ['21bcs5084'],
      'cc_profile':
          '{"id":"me","name":"Sumit Mishra","username":"21bcs5084",'
              '"email":"21bcs5084@cuchd.in","uid":"21BCS5084","phoneNumber":"",'
              '"gender":"Male","department":"Computer Science","course":"B.E. CSE",'
              '"year":"4th Year","bio":"Hello","interests":["Coding"],'
              '"languages":["Hindi"],"lookingFor":["Study Partner"],'
              '"profilePhotoUrl":"","trustLevel":1,"verificationLevel":3,'
              '"badges":[],"achievements":[],"campusStatus":null,'
              '"hideDepartment":false,"hideYear":false,'
              '"hideLookingFor":false,"hideActiveStatus":false}',
    });

    await tester.pumpWidget(const CampusConnectApp());
    await tester.pumpAndSettle();

    // The saved session is restored, so we land straight in the app.
    expect(find.byType(MainNavigation), findsOneWidget);
  });
}

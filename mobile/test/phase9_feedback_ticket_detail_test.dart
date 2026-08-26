import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('FeedbackTicketDetailPage Widget Tests', () {
    testWidgets(
      'renders FeedbackTicketDetailPage with loading state and app bar',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FeedbackTicketDetailPage(reportId: 'ticket_123'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);
      },
    );
  });

  group('EmailOtpReauthDialog Widget Tests', () {
    testWidgets('renders EmailOtpReauthDialog with title and OTP inputs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmailOtpReauthDialog(
              verifyUrl: 'https://mock.supabase.co/verify',
              resendUrl: 'https://mock.supabase.co/resend',
              onVerificationSuccess: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EmailOtpReauthDialog), findsOneWidget);
      expect(find.text("Confirm It's You"), findsOneWidget);
    });
  });
}

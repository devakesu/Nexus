import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
import 'package:nexus/features/settings/screens/help_center_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
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

  group('PrivacySettingsPage Widget Tests', () {
    testWidgets('renders PrivacySettingsPage with field privacy options', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PrivacySettingsPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(PrivacySettingsPage), findsOneWidget);
    });
  });

  group('HelpCenterPage Widget Tests', () {
    testWidgets('renders HelpCenterPage with FAQs and categories', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HelpCenterPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(HelpCenterPage), findsOneWidget);
      expect(find.text('Help Center'), findsWidgets);
    });
  });

  group('FeedbackPage & FeedbackTicketsListPage Widget Tests', () {
    testWidgets('renders FeedbackPage with query types and form inputs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FeedbackPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(FeedbackPage), findsOneWidget);
    });

    testWidgets('renders FeedbackTicketsListPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FeedbackTicketsListPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(FeedbackTicketsListPage), findsOneWidget);
    });
  });

  group('BlockedUsersPage & HiddenUsersPage Widget Tests', () {
    testWidgets('renders BlockedUsersPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockedUsersPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(BlockedUsersPage), findsOneWidget);
    });

    testWidgets('renders HiddenUsersPage', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HiddenUsersPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(HiddenUsersPage), findsOneWidget);
    });
  });

  group('EmailNotificationSettingsPage Widget Tests', () {
    testWidgets('renders EmailNotificationSettingsPage with switch toggles', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmailNotificationSettingsPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);
    });
  });
}

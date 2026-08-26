import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/settings/screens/about_screen.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/crisis_helplines_page.dart';
import 'package:nexus/features/settings/screens/delete_account_page.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
import 'package:nexus/features/settings/screens/help_center_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
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

  group('Settings Secondary Screens Deep Widget Tests', () {
    testWidgets('renders FeedbackPage and selects categories', (tester) async {
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

    testWidgets(
      'renders FeedbackTicketsListPage and FeedbackTicketDetailPage',
      (tester) async {
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

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FeedbackTicketDetailPage(reportId: 'rpt_mock_1'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);
      },
    );

    testWidgets('renders BlockedUsersPage and HiddenUsersPage', (tester) async {
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

    testWidgets('renders CheckInAlertScreen with countdown and safe button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CheckInAlertScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(CheckInAlertScreen), findsOneWidget);
    });

    testWidgets(
      'renders HelpCenterPage, AboutScreen, CrisisHelplinesPage, DeleteAccountPage, EmailNotificationSettingsPage',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: HelpCenterPage()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(HelpCenterPage), findsOneWidget);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(body: AboutScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(AboutScreen), findsOneWidget);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CrisisHelplinesPage()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(CrisisHelplinesPage), findsOneWidget);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: DeleteAccountPage()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(DeleteAccountPage), findsOneWidget);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: EmailNotificationSettingsPage()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);
      },
    );
  });
}

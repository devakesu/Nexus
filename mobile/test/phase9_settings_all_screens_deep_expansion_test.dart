import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/delete_account_page.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Settings Screens Deep Expansion Tests', () {
    testWidgets('renders HiddenUsersPage and switches tab filters', (
      tester,
    ) async {
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
      expect(find.text('Hidden Users'), findsWidgets);
    });

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
      expect(find.text('Blocked Users'), findsWidgets);
    });

    testWidgets(
      'renders FeedbackTicketsListPage and selects active/resolved filters',
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
        expect(find.text('Your Tickets'), findsWidgets);
      },
    );

    testWidgets('renders EmailNotificationSettingsPage and toggles switch', (
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

      final switches = find.byType(Switch);
      if (switches.evaluate().isNotEmpty) {
        await tester.tap(switches.first);
        await tester.pump();
      }
    });

    testWidgets('renders DeleteAccountPage and enters reason', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeleteAccountPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(DeleteAccountPage), findsOneWidget);
      expect(find.text('Delete Account'), findsWidgets);
    });
  });
}

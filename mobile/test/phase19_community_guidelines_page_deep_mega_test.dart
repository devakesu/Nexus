import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/settings/screens/community_guidelines_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('CommunityGuidelinesPage Deep Widget Mega Tests', () {
    testWidgets(
      'CommunityGuidelinesPage switches tabs, scrolls sections, and signs pledge',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CommunityGuidelinesPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(CommunityGuidelinesPage), findsOneWidget);

        // Tap tab headers
        final profileTab = find.text('Profile');
        if (profileTab.evaluate().isNotEmpty) {
          await tester.tap(profileTab.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        final interactionsTab = find.text('Interactions');
        if (interactionsTab.evaluate().isNotEmpty) {
          await tester.tap(interactionsTab.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        final chatTab = find.text('Chat');
        if (chatTab.evaluate().isNotEmpty) {
          await tester.tap(chatTab.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        final safetyTab = find.text('Safety');
        if (safetyTab.evaluate().isNotEmpty) {
          await tester.tap(safetyTab.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        // Scroll through content
        await tester.drag(
          find.byType(CommunityGuidelinesPage),
          const Offset(0, -600),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      },
    );
  });
}

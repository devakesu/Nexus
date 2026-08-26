import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('PrivacySettingsPage Comprehensive Coverage Tests', () {
    testWidgets(
      'renders PrivacySettingsPage and scrolls through all privacy controls',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: PrivacySettingsPage(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(PrivacySettingsPage), findsOneWidget);
        expect(find.text('Privacy Settings'), findsWidgets);

        // Toggle any available switches in view
        final switches = find.byType(Switch);
        for (var i = 0; i < switches.evaluate().length && i < 4; i++) {
          await tester.tap(switches.at(i));
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Scroll down to see more switches
        await tester.drag(
          find.byType(PrivacySettingsPage),
          const Offset(0, -500),
        );
        await tester.pump(const Duration(seconds: 1));

        final updatedSwitches = find.byType(Switch);
        for (var i = 0; i < updatedSwitches.evaluate().length && i < 3; i++) {
          await tester.tap(updatedSwitches.at(i));
          await tester.pump(const Duration(milliseconds: 200));
        }
      },
    );
  });
}

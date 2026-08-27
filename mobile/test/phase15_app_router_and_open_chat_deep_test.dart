import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/navigation/app_router.dart';
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

  group('AppRouter Deep Route Tests', () {
    testWidgets('renders MaterialApp.router with goRouter and navigates', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: goRouter,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(goRouter, isNotNull);

      // Navigate to /settings/about
      goRouter.go('/settings/about');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Navigate to /settings/community-guidelines
      goRouter.go('/settings/community-guidelines');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Navigate to /settings/help
      goRouter.go('/settings/help');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}

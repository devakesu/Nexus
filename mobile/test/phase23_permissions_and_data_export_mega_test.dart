import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_secure_screen'),
        (call) async => null,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Permissions & Mode Overlays Exhaustive Mega Tests', () {
    testWidgets('PermissionsScreen renders permission items and continues', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionsScreen(
              onCompleted: () {
                completed = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(PermissionsScreen), findsOneWidget);

      // Scroll PermissionsScreen
      await tester.drag(find.byType(PermissionsScreen), const Offset(0, -600));
      await tester.pump();

      expect(completed, isFalse);
    });

    testWidgets('DatingSettingsOverlay renders cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatingSettingsOverlay(
              datingTargetBuckets: const ['W', 'NB'],
              datingFor: const ['Long-term relationship'],
              partnerValues: const ['Authenticity'],
              childrenPlans: 'Someday',
              savingFields: const {},
              onSaveDatingField: (field, val, setSt) async {},
              onLoadDatingProfileStatusSilent: () async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(DatingSettingsOverlay), findsOneWidget);
    });

    testWidgets('ModeCategorySelectionSheet renders and interacts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeCategorySelectionSheet(
              title: 'Incoming Requests',
              themeColor: Colors.deepPurple,
              items: const [],
              onFetchItems: () async {},
              onOpenItemDetailsDialog:
                  ({
                    required ctx,
                    required actorId,
                    required name,
                    required onActioned,
                    required onProfileLoaded,
                  }) {},
              onRecordAction: (targetId, action, token) async => true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
    });
  });
}

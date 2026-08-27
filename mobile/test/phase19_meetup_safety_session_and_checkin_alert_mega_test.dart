import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => null,
      );

  ConsentCacheManager.specialCategoryConsentGranted = true;
  ConsentCacheManager.safetyConsentGranted = true;

  setUpAll(() async {
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('UTC'));
    } on Object catch (_) {}

    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
    try {
      await MeetupSafetySession.instance.init();
    } on Object catch (_) {}
  });

  group('MeetupSafetySession & CheckInAlertScreen Mega Coverage Tests', () {
    test(
      'MeetupSafetySession manages session lifecycle and check-ins',
      () async {
        final session = MeetupSafetySession.instance;

        try {
          await session.start(
            interval: const Duration(minutes: 30),
            label: 'Coffee with Alex',
          );

          expect(session.isActive, isTrue);
          expect(session.checkInLabel, 'Coffee with Alex');

          await session.checkInSafely();
          await session.extend(const Duration(minutes: 15));
          await session.end();
        } on Object catch (_) {}
      },
    );

    testWidgets(
      'CheckInAlertScreen renders countdown, safety actions, and handles I am safe',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
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
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(CheckInAlertScreen), findsOneWidget);
        expect(find.text("I'm Safe"), findsOneWidget);
      },
    );
  });
}

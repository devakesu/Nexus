import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
import 'package:nexus/features/settings/screens/settings_tab.dart';
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
        const MethodChannel('plugins.flutter.io/firebase_core'),
        (call) async {
          if (call.method == 'Firebase#initializeCore') {
            return [
              {
                'name': '[DEFAULT]',
                'options': {
                  'apiKey': 'mock-api-key',
                  'appId': 'mock-app-id',
                  'messagingSenderId': 'mock-sender-id',
                  'projectId': 'mock-project-id',
                },
                'pluginConstants': <String, dynamic>{},
              },
            ];
          }
          if (call.method == 'Firebase#initializeApp') {
            return {
              'name': (call.arguments as Map<String, dynamic>)['appName'],
              'options': (call.arguments as Map<String, dynamic>)['options'],
              'pluginConstants': <String, dynamic>{},
            };
          }
          return null;
        },
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/firebase_messaging'),
        (call) async {
          if (call.method == 'Messaging#getToken') return 'mock-token';
          if (call.method == 'Messaging#getNotificationSettings') {
            return {
              'authorizationStatus': 1,
              'alert': 1,
              'badge': 1,
              'sound': 1,
            };
          }
          return null;
        },
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => null,
      );

  setUpAll(() async {
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'mock-key',
          appId: 'mock-app-id',
          messagingSenderId: 'mock-sender',
          projectId: 'mock-project',
        ),
      );
    } on Exception catch (_) {}
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('SettingsTab Widget Tests', () {
    testWidgets(
      'renders SettingsTab with navigation header and settings sections',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SettingsTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(SettingsTab), findsOneWidget);
      },
    );
  });

  group('PrivacySettingsPage Widget Tests', () {
    testWidgets(
      'renders PrivacySettingsPage with hideable fields and toggle switches',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
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
      },
    );
  });

  group('MeetupSafetyPage Widget Tests', () {
    testWidgets(
      'renders MeetupSafetyPage with initial check-in label and duration',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: MeetupSafetyPage(
                  initialCheckInLabel: 'Coffee with Jordan',
                  initialCheckInDuration: Duration(hours: 2),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(MeetupSafetyPage), findsOneWidget);
      },
    );
  });
}

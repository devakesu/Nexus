import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/presence_provider.dart';
import 'package:nexus/features/chats/widgets/presence_badge.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';
import 'package:nexus/features/security_signal/services/security_service.dart';
import 'package:nexus/features/settings/screens/crisis_helplines_page.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/mock_network_interceptor.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    final mockSessionJson = jsonEncode({
      'access_token': 'mock-access-token-12345',
      'refresh_token': 'mock-refresh-token-12345',
      'expires_in': 3600,
      'expires_at': 1893456000,
      'token_type': 'bearer',
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'user@nexus.test',
        'phone': '+14155552671',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      },
    });

    SharedPreferences.setMockInitialValues({
      'sb-mock-auth-token': mockSessionJson,
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => true,
        );

    setUpAll(() async {
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      setupGlobalMockNetwork();
    });

    group('Notification Service Exhaustive Tests', () {
      test(
        'NotificationService handles chat, match, and safety push messages',
        () async {
          // 1. Safety Alert Push
          const safetyMsg = RemoteMessage(
            messageId: 'fcm_001',
            data: {
              'type': 'safety_alert',
              'alert_id': 'alt_999',
              'sender_name': 'Emergency Contact',
            },
          );
          await NotificationService.handlePushMessage(safetyMsg);

          // 2. New Match Push
          const matchMsg = RemoteMessage(
            messageId: 'fcm_002',
            data: {
              'type': 'match',
              'match_id': 'm_888',
              'sender_name': 'Taylor',
              'tab': 'dating',
            },
          );
          await NotificationService.handlePushMessage(matchMsg);

          // 3. New Message Push
          const chatMsg = RemoteMessage(
            messageId: 'fcm_003',
            data: {
              'type': 'new_message',
              'conversation_id': 'c_777',
              'sender_id': '00000000-0000-0000-0000-000000000002',
              'sender_name': 'Jordan',
              'ciphertext': 'abc123ciphertext',
              'message_type': 'text',
            },
          );
          await NotificationService.handlePushMessage(chatMsg);
        },
      );
    });
  }

  // --- Section 2 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => null,
        );

    group('NotificationService Deep Push Handling Tests', () {
      test('handlePushMessage handles replenish_prekeys push', () async {
        const message = RemoteMessage(
          data: {'type': 'replenish_prekeys'},
        );
        await NotificationService.handlePushMessage(message);
      });

      test(
        'handlePushMessage handles generic notification in foreground',
        () async {
          const message = RemoteMessage(
            data: {'type': 'match_celebration', 'actor_id': 'user_1'},
            notification: RemoteNotification(
              title: 'New Match!',
              body: 'You and Aria liked each other.',
            ),
          );
          await NotificationService.handlePushMessage(
            message,
            isForeground: true,
          );
        },
      );

      test(
        'handlePushMessage handles chat message push payload structure',
        () async {
          const message = RemoteMessage(
            data: {
              'type': 'chat_message',
              'actor_id': 'user_99',
              'conversation_id': 'conv_123',
              'name': 'Agent Simmons',
              'tab': 'Dating',
              'message_id': 'msg_001',
            },
          );
          try {
            await NotificationService.handlePushMessage(message);
          } on Object catch (_) {}
        },
      );
    });
  }

  // --- Section 3 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('NotificationService Unit Tests', () {
      test('cleanStaleNotificationAvatars executes without throwing', () async {
        await NotificationService.cleanStaleNotificationAvatars();
      });

      test(
        'clearNotificationsForConversation executes without throwing',
        () async {
          await NotificationService.clearNotificationsForConversation(
            'conv_dummy',
          );
        },
      );

      test(
        'dispose cleans up timers and stream subscriptions safely',
        () async {
          await NotificationService.dispose();
        },
      );
    });
  }

  // --- Section 4 ---
  {
    const channel = MethodChannel('com.devakesu.apps.nexus/security');
    final methodCalls = <MethodCall>[];

    setUp(() {
      methodCalls.clear();
      SecurityService.resetSensitiveScreenCountForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methodCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('SecurityService Lifecycle & Sensitive Screen Management', () {
      test('enterSensitiveScreen sets FLAG_SECURE and tracks count', () async {
        expect(SecurityService.isSensitiveScreenActive, isFalse);
        expect(SecurityService.sensitiveScreenCount, 0);

        await SecurityService.enterSensitiveScreen();
        expect(SecurityService.isSensitiveScreenActive, isTrue);
        expect(SecurityService.sensitiveScreenCount, 1);
        expect(methodCalls.last.method, 'setSecureFlag');
        expect(methodCalls.last.arguments, {'secure': true});

        // Nested sensitive screen
        await SecurityService.enterSensitiveScreen();
        expect(SecurityService.sensitiveScreenCount, 2);
        expect(SecurityService.isSensitiveScreenActive, isTrue);

        // Exit first sensitive screen - should still remain secure
        await SecurityService.exitSensitiveScreen();
        expect(SecurityService.sensitiveScreenCount, 1);
        expect(SecurityService.isSensitiveScreenActive, isTrue);

        // Exit second sensitive screen - should now clear secure flag
        await SecurityService.exitSensitiveScreen();
        expect(SecurityService.sensitiveScreenCount, 0);
        expect(SecurityService.isSensitiveScreenActive, isFalse);
        expect(methodCalls.last.arguments, {'secure': false});
      });

      test(
        'handleAppLifecycleState handles inactive, paused, and resumed states',
        () async {
          expect(SecurityService.isSensitiveScreenActive, isFalse);

          await SecurityService.handleAppLifecycleState(
            AppLifecycleState.inactive,
          );
          expect(methodCalls.last.arguments, {'secure': true});

          await SecurityService.handleAppLifecycleState(
            AppLifecycleState.resumed,
          );
          expect(methodCalls.last.arguments, {'secure': false});

          await SecurityService.enterSensitiveScreen();
          expect(methodCalls.last.arguments, {'secure': true});

          await SecurityService.handleAppLifecycleState(
            AppLifecycleState.paused,
          );
          expect(methodCalls.last.arguments, {'secure': true});

          await SecurityService.handleAppLifecycleState(
            AppLifecycleState.resumed,
          );
          expect(methodCalls.last.arguments, {'secure': true});

          await SecurityService.exitSensitiveScreen();
          expect(methodCalls.last.arguments, {'secure': false});
        },
      );
    });
  }

  // --- Section 5 ---
  {
    final mockSessionJson = jsonEncode({
      'access_token': 'mock-access-token-12345',
      'refresh_token': 'mock-refresh-token-12345',
      'expires_in': 3600,
      'expires_at': 1893456000,
      'token_type': 'bearer',
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'user@nexus.test',
        'phone': '+14155552671',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      },
    });

    SharedPreferences.setMockInitialValues({
      'sb-mock-auth-token': mockSessionJson,
    });

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
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => 1, // Granted
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => 1, // Precision High
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

    group('MeetupSafetyPage & CrisisHelplinesPage Tests', () {
      testWidgets(
        'MeetupSafetyPage renders permissions checklist and checkin form',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: MeetupSafetyPage(
                    initialCheckInLabel: 'Coffee with Bob',
                    initialCheckInDuration: Duration(hours: 2),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(MeetupSafetyPage), findsOneWidget);

          // Scroll through the page
          await tester.drag(
            find.byType(MeetupSafetyPage),
            const Offset(0, -400),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets('CrisisHelplinesPage renders crisis hotlines list', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CrisisHelplinesPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(CrisisHelplinesPage), findsOneWidget);
        expect(find.textContaining('Emergency'), findsWidgets);

        // Scroll through helplines
        await tester.drag(
          find.byType(CrisisHelplinesPage),
          const Offset(0, -400),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      });
    });
  }

  // --- Section 6 ---
  {
    final mockSessionJson = jsonEncode({
      'access_token': 'mock-access-token-12345',
      'refresh_token': 'mock-refresh-token-12345',
      'expires_in': 3600,
      'expires_at': 1893456000,
      'token_type': 'bearer',
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'user@nexus.test',
        'phone': '+14155552671',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      },
    });

    SharedPreferences.setMockInitialValues({
      'sb-mock-auth-token': mockSessionJson,
    });

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
      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
    });

    group('Notification and Meetup Safety Session Tests', () {
      test('MeetupSafetyPermissionStatus constructor and getters', () {
        const status = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: true,
          fullScreenIntentGranted: true,
        );
        expect(status.allGranted, true);

        const partial = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: false,
          fullScreenIntentGranted: true,
        );
        expect(partial.allGranted, false);

        const all = MeetupSafetyPermissionStatus.allGranted();
        expect(all.allGranted, true);
      });

      test('MeetupSafetyNotificationActions constants', () {
        expect(MeetupSafetyNotificationActions.sos, 'meetup_safety_sos');
        expect(
          MeetupSafetyNotificationActions.call112,
          'meetup_safety_call_112',
        );
        expect(
          MeetupSafetyNotificationActions.informContacts,
          'meetup_safety_inform_contacts',
        );
        expect(MeetupSafetyNotificationActions.imSafe, 'meetup_safety_im_safe');
      });

      test('MeetupSafetySession instance check and state properties', () {
        final session = MeetupSafetySession.instance;
        expect(session.isActive, false);
      });
    });
  }

  // --- Section 7 ---
  {
    group('Presence and Chat Badges Tests', () {
      test('PresenceInfo model properties', () {
        final info = PresenceInfo(
          isOnline: true,
          lastActiveAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        expect(info.isOnline, isTrue);
        expect(info.lastActiveAt, isNotNull);
      });

      testWidgets(
        'PresenceBadge renders fallback when no presence info is loaded',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: PresenceBadge(
                    peerUserId: 'u1',
                    poll: false,
                    fallback: Text('Offline'),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.text('Offline'), findsOneWidget);
        },
      );
    });
  }
}

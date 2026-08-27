import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Phase 76 - Notification and Meetup Safety Session Mega Tests', () {
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
      expect(MeetupSafetyNotificationActions.call112, 'meetup_safety_call_112');
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

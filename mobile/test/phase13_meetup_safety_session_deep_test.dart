import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

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

  group('MeetupSafetySession Deep Unit Tests', () {
    test('MeetupSafetyPermissionStatus properties and constructor', () {
      const status = MeetupSafetyPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: true,
        fullScreenIntentGranted: true,
      );
      expect(status.allGranted, isTrue);

      const statusPartial = MeetupSafetyPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: false,
        fullScreenIntentGranted: true,
      );
      expect(statusPartial.allGranted, isFalse);

      const allGranted = MeetupSafetyPermissionStatus.allGranted();
      expect(allGranted.allGranted, isTrue);
    });

    test('MeetupSafetyNotificationActions constants', () {
      expect(MeetupSafetyNotificationActions.imSafe, 'meetup_safety_im_safe');
      expect(MeetupSafetyNotificationActions.sos, 'meetup_safety_sos');
      expect(MeetupSafetyNotificationActions.call112, 'meetup_safety_call_112');
      expect(
        MeetupSafetyNotificationActions.informContacts,
        'meetup_safety_inform_contacts',
      );
    });

    test(
      'drainPendingEndSessions processes queued sessions via SafetyAlertApi',
      () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/safety/session/end')) {
            return ResponseBody.fromString(
              jsonEncode({'status': 'ok'}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{}', 200);
        });

        final drained = await MeetupSafetySession.drainPendingEndSessions();
        expect(drained, isTrue);
      },
    );
  });
}

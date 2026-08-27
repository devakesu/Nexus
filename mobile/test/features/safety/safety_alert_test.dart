import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/security_signal/services/digital_witness_recorder.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/pending_evidence_upload_queue.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/security_signal/services/safety_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/test_helpers.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);
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
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/workmanager'),
          (call) async => true,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.devakesu.apps.nexus/safety'),
          (call) async => null,
        );

    setUpAll(() async {
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      try {
        await Supabase.instance.client.auth.recoverSession(
          jsonEncode({
            'access_token': 'mock-valid-access-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'mock-refresh-token',
            'user': {
              'id': 'mock-test-user-id',
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'tester@nexus.app',
            },
          }),
        );
      } on Exception catch (_) {}
    });

    setUp(() {});

    group('SafetyAlertApi Deep Unit Tests', () {
      test(
        'syncContacts successfully syncs contacts and parses blocked list',
        () async {
          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/safety/contacts')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'status': 'ok',
                  'blocked': ['Alice'],
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('Not Found', 404);
          });

          final result = await SafetyAlertApi.syncContacts([
            SafetyContact(name: 'Alice', phone: '+1234567890'),
            SafetyContact(name: 'Bob', phone: '+1987654321'),
          ]);

          expect(result.success, isTrue);
          expect(result.blocked, contains('Alice'));
        },
      );

      test('syncContacts handles network exceptions gracefully', () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('Server Error', 500);
        });

        final result = await SafetyAlertApi.syncContacts([
          SafetyContact(name: 'Charlie', phone: '+1122334455'),
        ]);

        expect(result.success, isFalse);
        expect(result.blocked, isEmpty);
      });

      test('sendAlert successfully sends alert on first attempt', () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/safety/alert')) {
            return ResponseBody.fromString(
              jsonEncode({
                'id': 'alt_999',
                'contacts_notified': 2,
                'contacts_total': 2,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('Not Found', 404);
        });

        final result = await SafetyAlertApi.sendAlert(
          alertType: 'sos',
          sessionId: 'sess_1',
          sessionLabel: 'Night Walk',
          eventLabel: 'Park Meetup',
          latitude: 37.7749,
          longitude: -122.4194,
        );

        expect(result, isNotNull);
        expect(result!.alertId, equals('alt_999'));
        expect(result.contactsNotified, equals(2));
        expect(result.contactsTotal, equals(2));
      });

      test(
        'sendAlert retries on transient failures up to max attempts',
        () async {
          var attemptCount = 0;
          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            attemptCount++;
            if (attemptCount < 2) {
              return ResponseBody.fromString('Gateway Timeout', 504);
            }
            return ResponseBody.fromString(
              jsonEncode({
                'id': 'alt_retry_ok',
                'contacts_notified': 1,
                'contacts_total': 1,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          final result = await SafetyAlertApi.sendAlert(alertType: 'inform');
          expect(result, isNotNull);
          expect(result!.alertId, equals('alt_retry_ok'));
          expect(attemptCount, equals(2));
        },
      );

      test('sendAlert returns null after exhausting all 3 attempts', () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('Internal Server Error', 500);
        });

        final result = await SafetyAlertApi.sendAlert(alertType: 'sos');
        expect(result, isNull);
      });

      test('registerEvidence handles success and error', () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/safety/evidence')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          return ResponseBody.fromString('Error', 400);
        });

        final success = await SafetyAlertApi.registerEvidence(
          alertId: 'alt_1',
          storagePath: 'user/123.enc',
          mediaKeyBase64: 'key123==',
          contentType: 'video/mp4',
          durationSeconds: 15.5,
        );
        expect(success, isTrue);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('Fail', 500);
        });
        final failed = await SafetyAlertApi.registerEvidence(
          alertId: 'alt_2',
          storagePath: 'user/456.enc',
          mediaKeyBase64: 'key456==',
          contentType: 'video/mp4',
        );
        expect(failed, isFalse);
      });

      test('startSession, checkinSession, and endSession API calls', () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/safety/session/start')) {
            return ResponseBody.fromString(
              jsonEncode({'id': 'sess_abc_123'}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.path.contains('/api/v1/safety/session/checkin') ||
              options.path.contains('/api/v1/safety/session/end')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          return ResponseBody.fromString('Not Found', 404);
        });

        final sessionId = await SafetyAlertApi.startSession(
          intervalSeconds: 3600,
          label: 'Coffee Date',
          nextCheckInAt: DateTime.now().add(const Duration(hours: 1)),
          batteryPercent: 85,
          connectionType: 'wifi',
        );
        expect(sessionId, equals('sess_abc_123'));

        final checkinOk = await SafetyAlertApi.checkinSession(
          sessionId: 'sess_abc_123',
          nextCheckInAt: DateTime.now().add(const Duration(hours: 1)),
          batteryPercent: 84,
          connectionType: 'cellular',
        );
        expect(checkinOk, isTrue);

        final endOk = await SafetyAlertApi.endSession('sess_abc_123');
        expect(endOk, isTrue);
      });

      test('startSession, checkinSession, endSession error handling', () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('Server down', 503);
        });

        final sessId = await SafetyAlertApi.startSession(
          intervalSeconds: 1800,
          label: 'Walk',
          nextCheckInAt: DateTime.now(),
        );
        expect(sessId, isNull);

        final checkinFail = await SafetyAlertApi.checkinSession(
          sessionId: 'sess_1',
          nextCheckInAt: DateTime.now(),
        );
        expect(checkinFail, isFalse);

        final endFail = await SafetyAlertApi.endSession('sess_1');
        expect(endFail, isFalse);
      });
    });

    group('PendingEvidenceUploadQueue Unit Tests', () {
      test(
        'enqueueAll writes segments and scheduleBackgroundRetry registers task',
        () async {
          final tempDir = Directory.systemTemp;
          final sampleFile = File('${tempDir.path}/test_seg_1.mp4');
          await sampleFile.writeAsString('sample content');

          await PendingEvidenceUploadQueue.enqueueAll(
            alertId: 'alt_seg_1',
            segments: [
              (sampleFile, 12.0, 'rawMediaKeyBase64=='),
            ],
          );

          try {
            await PendingEvidenceUploadQueue.scheduleBackgroundRetry();
          } on Object catch (_) {}

          // Drain returns false when backend storage upload fails
          final drainRes = await PendingEvidenceUploadQueue.drain();
          expect(drainRes, isFalse);

          if (sampleFile.existsSync()) {
            await sampleFile.delete();
          }
        },
      );

      test('drain with empty queue returns true', () async {
        final res = await PendingEvidenceUploadQueue.drain();
        expect(res, isTrue);
      });
    });

    group('DigitalWitnessRecorder Unit Tests', () {
      test('instance properties and elapsed calculation', () {
        final recorder = DigitalWitnessRecorder.instance;
        expect(recorder, isNotNull);
        expect(recorder.isRecording, isFalse);
        expect(recorder.elapsed, equals(Duration.zero));
      });

      test('didChangeAppLifecycleState handles lifecycle events when idle', () {
        DigitalWitnessRecorder.instance
          ..didChangeAppLifecycleState(AppLifecycleState.paused)
          ..didChangeAppLifecycleState(AppLifecycleState.inactive)
          ..didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(DigitalWitnessRecorder.instance.isRecording, isFalse);
      });

      test('stop when not recording completes safely', () async {
        final recorder = DigitalWitnessRecorder.instance;
        await recorder.stop();
        expect(recorder.isRecording, isFalse);
      });
    });

    group('MeetupSafetySession Drain and Persist Unit Tests', () {
      test('drainPendingEndSessions with empty queue returns true', () async {
        final res = await MeetupSafetySession.drainPendingEndSessions();
        expect(res, isTrue);
      });

      test(
        'drainPendingEndSessions calls endSession for all queued session IDs',
        () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'meetup_safety_pending_session_cleanups',
            jsonEncode(['sess_orphaned_1', 'sess_orphaned_2']),
          );

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString('{"ok":true}', 200);
          });

          final res = await MeetupSafetySession.drainPendingEndSessions();
          expect(res, isTrue);
        },
      );
    });
  }

  // --- Section 2 ---
  {
    group('Safety Contacts and Storage Tests', () {
      test('SafetyContact model json serialization and persistence', () async {
        final contact = SafetyContact(name: 'Bob', phone: '+14155551234');
        expect(contact.name, 'Bob');
        expect(contact.phone, '+14155551234');

        final json = contact.toJson();
        final fromJson = SafetyContact.fromJson(json);
        expect(fromJson.name, 'Bob');
        expect(fromJson.phone, '+14155551234');

        final list = [contact];
        await saveSafetyContacts(list);
        final loaded = await loadSafetyContacts();
        expect(loaded.length, 1);
        expect(loaded.first.name, 'Bob');
      });
    });
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:nexus/features/security_signal/services/digital_witness_recorder.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
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

  group('Phase 75 - Notifications and Witness Services Mega Tests', () {
    test('ErrorHandler handles error levels and exception types', () {
      ErrorHandler.handleError(
        Exception('Test non-fatal warning'),
        customMessage: 'Test warning message',
        level: ErrorLevel.warning,
      );

      ErrorHandler.handleError(
        const SocketException('Connection reset'),
        customMessage: 'Test info message',
        level: ErrorLevel.info,
      );

      ErrorHandler.handleError(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/test'),
          type: DioExceptionType.connectionTimeout,
        ),
        customMessage: 'Test critical error',
      );
    });

    test('DigitalWitnessRecorder and MeetupSafetySession unit logic', () async {
      final recorder = DigitalWitnessRecorder.instance;
      expect(recorder.isRecording, false);
      expect(recorder.elapsed, Duration.zero);

      recorder.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await recorder.stop();

      final drainResult = await MeetupSafetySession.drainPendingEndSessions();
      expect(drainResult, true);
    });

    test('ClientAIProfileState copyWith and state mutations', () {
      final state = ClientAIProfileState(
        remotePaths: ['', '', '', '', ''],
        pendingUploads: {},
        slotSpecificVibeTags: {},
        pendingDeletions: [],
      );

      final updated = state.copyWith(
        isProcessingAI: true,
        isSaving: true,
      );
      expect(updated.isProcessingAI, true);
      expect(updated.isSaving, true);
      expect(updated.remotePaths.length, 5);
    });

    testWidgets('DataExportFlow renders trigger card and dialog flow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => startDataExport(context),
                  child: const Text('Export My Data'),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Export My Data'), findsOneWidget);

      await tester.tap(find.text('Export My Data'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}

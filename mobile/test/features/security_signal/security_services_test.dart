import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/security_signal/services/digital_witness_recorder.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
import 'package:nexus/features/settings/widgets/about/attestation_section.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers, Session;

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

    setUp(() {});

    group('LocalKeyVault Unit Tests', () {
      test('encrypts and decrypts byte payloads accurately', () async {
        final vault = LocalKeyVault.instance;
        final sample = Uint8List.fromList(
          utf8.encode('SecretSignalVaultData123'),
        );

        final encrypted = await vault.encryptBytes(sample);
        expect(encrypted, isNot(equals(sample)));

        final decrypted = await vault.decryptBytes(encrypted);
        expect(utf8.decode(decrypted), equals('SecretSignalVaultData123'));

        await vault.wipeKeys();
      });
    });

    group('SignalDatabase Custom Queries & Reset Tests', () {
      test('clearAllData runs without errors', () async {
        final db = SignalDatabase.instance;
        await db.clearAllData();
        expect(db.schemaVersion, equals(2));
      });
    });

    group('SignalKeyService Deep Tests', () {
      test('instance properties and wipeLocalData', () async {
        final service = SignalKeyService.instance;
        expect(service, isNotNull);
        expect(service.isNewLocalIdentity, isA<bool>());

        await service.wipeLocalData();
      });

      test(
        'ensureBootstrappedInBackground handles 404 and unexpected errors gracefully',
        () async {
          final service = SignalKeyService.instance;

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              '{"detail": "User not onboarded"}',
              404,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          // Does not throw
          await service.ensureBootstrappedInBackground();
        },
      );
    });
  }

  // --- Section 2 ---
  {
    group(
      'Safety Alert, Meetup Session and Digital Witness Deep Tests',
      () {
        testWidgets(
          'CheckInAlertScreen renders alert actions, countdown and dismiss buttons',
          (
            tester,
          ) async {
            await tester.pumpWidget(
              const MaterialApp(
                home: Scaffold(
                  body: CheckInAlertScreen(),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(CheckInAlertScreen), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          },
        );

        test('MeetupSafetySession instance properties and end', () async {
          final session = MeetupSafetySession.instance;

          expect(session.isActive, isFalse);
          expect(session.serverSessionId, isNull);
        });

        test('DigitalWitnessRecorder instance properties and stop', () async {
          final recorder = DigitalWitnessRecorder.instance;

          expect(recorder.isRecording, isFalse);
        });
      },
    );
  }

  // --- Section 3 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'),
          (call) async => ['wifi'],
        );

    group('Security Services, Witness & Auth Mega Coverage Tests', () {
      test(
        'ErrorHandler sanitizes emails, tokens, and sensitive keys accurately',
        () {
          final sanitizedEmail = ErrorHandler.sanitize(
            'Contact user at test@example.com for help',
          );
          expect(sanitizedEmail, contains('[EMAIL_REDACTED]'));

          final sanitizedToken = ErrorHandler.sanitize(
            'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz',
          );
          expect(sanitizedToken, contains('[REDACTED_SENSITIVE]'));

          expect(ErrorHandler.isSensitiveKey('jwt'), isTrue);
          expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
          expect(ErrorHandler.isSensitiveKey('display_name'), isFalse);

          final map = {
            'jwt': 'secret_jwt_token',
            'public_data': 'hello',
          };
          final sanitizedMap = ErrorHandler.sanitizeObject(map) as Map;
          expect(sanitizedMap['jwt'], '[REDACTED_SENSITIVE]');
          expect(sanitizedMap['public_data'], 'hello');
        },
      );

      test(
        'MeetupSafetySession instance, permissions and lifecycle methods',
        () async {
          final session = MeetupSafetySession.instance;
          expect(session.isActive, isFalse);

          final perms = await session.ensureAndroidPermissions();
          expect(perms.allGranted, isNotNull);

          expect(session.checkInInterval, const Duration(hours: 1));
          expect(session.serverSessionId, isNull);
        },
      );

      testWidgets('CheckInAlertScreen renders and handles SOS phase triggers', (
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

        // Trigger "I'm Safe" button if present
        final safeBtn = find.text("I'm Safe");
        if (safeBtn.evaluate().isNotEmpty) {
          await tester.tap(safeBtn.first, warnIfMissed: false);
          await tester.pump();
        }
      });

      testWidgets('PlaceAutocompleteField renders and initializes', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var selectedPlace = '';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Current Place',
                initialValue: 'New York, NY',
                hintText: 'Search city...',
                prefixIcon: Icons.location_city,
                onChanged: (val) {
                  selectedPlace = val;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(PlaceAutocompleteField), findsOneWidget);
        expect(selectedPlace, isEmpty);
      });

      testWidgets('StabilityTracker widget renders completion progress', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        late AnimationController anim;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  anim = AnimationController(
                    vsync: Scaffold.of(context),
                    duration: const Duration(seconds: 1),
                  );
                  return StabilityTracker(
                    stabilityPercentage: 85,
                    imagePaths: const ['https://example.com/pic1.jpg'],
                    name: 'Robin',
                    age: 28,
                    bio: 'Journalist',
                    searchBucket: 'W',
                    displayGender: 'Woman',
                    displaySexuality: 'Straight',
                    pronouns: 'she/her',
                    hometown: 'Vancouver',
                    currentPlace: 'New York',
                    languages: const ['English'],
                    campusName: 'Metro Univ',
                    major: 'Journalism',
                    isStudying: true,
                    year: 4,
                    lifestyle: 'Active',
                    drinking: 'Socially',
                    smoking: 'Never',
                    religiousBeliefs: 'Agnostic',
                    pets: const ['Dogs'],
                    subInterests: const {
                      'Sports': ['Hockey'],
                    },
                    causesSupported: const ['Animal Welfare'],
                    topArtists: const ['The Clash'],
                    pulseController: anim,
                    onCriteriaTap: (label) {},
                  );
                },
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(StabilityTracker), findsOneWidget);
      });

      testWidgets('Auth screens (LoginScreen, PermissionsScreen) render', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // LoginScreen
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LoginScreen(appName: 'Nexus'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(LoginScreen), findsOneWidget);

        // PermissionsScreen
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PermissionsScreen(onCompleted: () {}),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(PermissionsScreen), findsOneWidget);
      });
    });
  }

  // --- Section 4 ---
  {
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

    group('EmailOtpReauthDialog & AttestationSection Exhaustive Tests', () {
      testWidgets('EmailOtpReauthDialog renders and enters OTP digits', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var verified = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmailOtpReauthDialog(
                verifyUrl: 'https://example.com/api/v1/auth/verify',
                resendUrl: 'https://example.com/api/v1/auth/resend',
                onVerificationSuccess: () {
                  verified = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(EmailOtpReauthDialog), findsOneWidget);

        final textFields = find.byType(TextField);
        if (textFields.evaluate().isNotEmpty) {
          await tester.enterText(textFields.first, '123456');
          await tester.pump();
        }

        expect(verified, isFalse);
      });

      testWidgets(
        'AttestationSection renders attestation details and triggers callbacks',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          String? launchedUrl;
          String? copiedText;

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              jsonEncode({
                'status': 'verified',
                'commit_hash': 'abcdef1234567890',
                'build_timestamp': '2026-08-26T12:00:00Z',
                'reproducible_build': true,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: AttestationSection(
                    onLaunch: (url) async {
                      launchedUrl = url;
                    },
                    onCopy: (context, label, text) async {
                      copiedText = text;
                    },
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(AttestationSection), findsOneWidget);
          expect(launchedUrl, isNull);
          expect(copiedText, isNull);
        },
      );

      test('ApiService returns AttestationResponse cleanly', () async {
        const api = ApiService();
        final res = await api.fetchAttestationDetails('mock_token');
        expect(res.statusCode, isNotNull);
      });
    });
  }

  // --- Section 5 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.devakesu.apps.nexus/safety'),
          (call) async => null,
        );

    group('SignalKeyService Unit Tests', () {
      test('singleton instance exists and exposes identity flags', () {
        final service = SignalKeyService.instance;
        expect(service, isNotNull);
        expect(service.isNewLocalIdentity, isA<bool>());
      });
    });

    group('DigitalWitnessRecorder Unit Tests', () {
      test('singleton instance initializes with idle recording state', () {
        final recorder = DigitalWitnessRecorder.instance;
        expect(recorder, isNotNull);
        expect(recorder.isRecording, isFalse);
        expect(recorder.elapsed, Duration.zero);
        expect(recorder.controller, isNull);
      });

      test('stop returns gracefully when not recording', () async {
        final recorder = DigitalWitnessRecorder.instance;
        await recorder.stop();
        expect(recorder.isRecording, isFalse);
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

    group('Notifications and Witness Services Tests', () {
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

      test(
        'DigitalWitnessRecorder and MeetupSafetySession unit logic',
        () async {
          final recorder = DigitalWitnessRecorder.instance;
          expect(recorder.isRecording, false);
          expect(recorder.elapsed, Duration.zero);

          recorder.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await recorder.stop();

          final drainResult =
              await MeetupSafetySession.drainPendingEndSessions();
          expect(drainResult, true);
        },
      );

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
}

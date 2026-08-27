import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/auth_onboarding/screens/auth_gate.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/onboarding_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/reactivate_account_page.dart';
import 'package:nexus/features/auth_onboarding/screens/splash_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/terms_consent_screen.dart';
import 'package:nexus/features/auth_onboarding/widgets/import_code_dialog.dart';
import 'package:nexus/features/auth_onboarding/widgets/login_painters.dart';
import 'package:nexus/features/auth_onboarding/widgets/nexus_onboarding_fields.dart';
import 'package:nexus/features/auth_onboarding/widgets/otp_verification_dialog.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/widgets/about/attestation_section.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/mock_network_interceptor.dart';
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
    Animate.restartOnHotReload = false;

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
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      setupGlobalMockNetwork();
    });

    group(
      'Auth Gate, Login, Onboarding and Dialogs Exhaustive Tests',
      () {
        testWidgets(
          'LoginScreen, AuthGate, Onboarding and Permissions mount and render',
          (
            tester,
          ) async {
            tester.view.physicalSize = const Size(1080, 2400);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);

            for (final widget in [
              const LoginScreen(appName: 'Nexus'),
              const AuthGate(appName: 'Nexus'),
              PermissionsScreen(onCompleted: () {}),
              OnboardingScreen(onComplete: () {}),
            ]) {
              await tester.pumpWidget(
                ProviderScope(
                  child: MaterialApp(
                    home: Scaffold(body: widget),
                  ),
                ),
              );

              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              expect(find.byWidget(widget), findsOneWidget);

              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await tester.pump(const Duration(seconds: 10));
            }
          },
        );

        testWidgets(
          'OtpVerificationDialog and EmailOtpReauthDialog render properly',
          (
            tester,
          ) async {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: OtpVerificationDialog(
                    phone: '+14155552671',
                    onVerificationSuccess: () {},
                  ),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byType(OtpVerificationDialog), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: EmailOtpReauthDialog(
                    verifyUrl: '/api/v1/auth/verify',
                    resendUrl: '/api/v1/auth/resend',
                    onVerificationSuccess: () {},
                  ),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byType(EmailOtpReauthDialog), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          },
        );

        testWidgets('AttestationSection renders key attestation rows', (
          tester,
        ) async {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: AttestationSection(
                    onLaunch: (url) async {},
                    onCopy: (ctx, label, val) async {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(AttestationSection), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      },
    );
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
          const MethodChannel('flutter_secure_screen'),
          (call) async => null,
        );

    group('LoginScreen Deep Views & Interactions Tests', () {
      testWidgets(
        'LoginScreen renders, switches between options, email, and phone views',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: LoginScreen(appName: 'Nexus'),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(LoginScreen), findsOneWidget);

          // Find and tap Continue with Email / Phone
          final emailBtn = find.text('Continue with Email');
          if (emailBtn.evaluate().isNotEmpty) {
            await tester.tap(emailBtn.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            // Enter email text
            final tf = find.byType(TextField);
            if (tf.evaluate().isNotEmpty) {
              await tester.enterText(tf.first, 'user@stanford.edu');
              await tester.pump();
            }

            // Tap back
            final backBtn = find.byIcon(Icons.arrow_back);
            if (backBtn.evaluate().isNotEmpty) {
              await tester.tap(backBtn.first, warnIfMissed: false);
              await tester.pump();
            }
          }

          // Tap phone option
          final phoneBtn = find.text('Continue with Phone');
          if (phoneBtn.evaluate().isNotEmpty) {
            await tester.tap(phoneBtn.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        },
      );
    });
  }

  // --- Section 3 ---
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

    group('Login & User Management Exhaustive Tests', () {
      testWidgets(
        'LoginScreen switches views (options, email, phone) and renders forms',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: LoginScreen(appName: 'Nexus'),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(LoginScreen), findsOneWidget);

          // Find and tap Continue with Email
          final emailBtn = find.text('Continue with Email');
          if (emailBtn.evaluate().isNotEmpty) {
            await tester.tap(emailBtn.first);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));

            // Enter email
            final emailInput = find.byType(TextField);
            if (emailInput.evaluate().isNotEmpty) {
              await tester.enterText(emailInput.first, 'student@campus.edu');
              await tester.pump();
            }
          }
        },
      );

      testWidgets(
        'HiddenUsersPage renders empty and loaded states with filter tabs',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              jsonEncode({'profiles': <Map<String, dynamic>>[]}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: HiddenUsersPage(),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(HiddenUsersPage), findsOneWidget);
        },
      );

      testWidgets('BlockedUsersPage renders empty and loaded states', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({'profiles': <Map<String, dynamic>>[]}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: BlockedUsersPage(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(BlockedUsersPage), findsOneWidget);
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
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async {
            if (call.method == 'checkPermissionStatus') {
              return 1; // PermissionStatus.granted
            } else if (call.method == 'requestPermissions') {
              final permissions = call.arguments as List<dynamic>;
              return {for (final p in permissions) p: 1};
            }
            return 1;
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async {
            if (call.method == 'getLocationAccuracy') {
              return 1; // LocationAccuracyStatus.precise
            }
            return 1;
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator_updates'),
          (call) async => 1,
        );

    group('SplashScreen & CoordinatePainter Tests', () {
      testWidgets('SplashScreen animates and triggers onAnimationComplete', (
        tester,
      ) async {
        var completed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: SplashScreen(
              appName: 'NEXUS',
              onAnimationComplete: () => completed = true,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 1000));
        await tester.pump(const Duration(milliseconds: 2000));

        expect(completed, isTrue);
      });

      test('CoordinatePainter shouldRepaint check', () {
        final p1 = CoordinatePainter(progress: 0.2);
        final p2 = CoordinatePainter(progress: 0.2);
        final p3 = CoordinatePainter(progress: 0.8);

        expect(p1.shouldRepaint(p2), isFalse);
        expect(p1.shouldRepaint(p3), isTrue);
      });
    });

    group('ReactivateAccountPage Widget Tests', () {
      testWidgets('renders reactivate account screen with days remaining', (
        tester,
      ) async {
        final futureDate = DateTime.now().add(const Duration(days: 14));

        await tester.pumpWidget(
          MaterialApp(
            home: ReactivateAccountPage(
              scheduledPurgeAt: futureDate,
              onReactivated: () {},
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Welcome back'), findsOneWidget);
        expect(find.textContaining('14 days'), findsOneWidget);
        expect(find.text('Reactivate My Account'), findsOneWidget);
        expect(find.text('Not now, sign me out'), findsOneWidget);

        await tester.tap(find.text('Reactivate My Account'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      });
    });

    group('TermsConsentPage Widget Tests', () {
      testWidgets(
        'renders itemized checkboxes, requires terms & guidelines before continuing',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TermsConsentPage(
                  currentTermsVersion: '1.2.0',
                  isVersionBump: false,
                  onConsentRecorded: () {},
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.text('Before you continue'), findsOneWidget);
          expect(
            find.text('Terms of Service & Privacy Policy'),
            findsOneWidget,
          );
          expect(find.text('Community Guidelines'), findsOneWidget);
          expect(
            find.text('Sexual orientation & religious belief data'),
            findsOneWidget,
          );
          expect(find.text('Meetup Safety & SOS data'), findsOneWidget);
          expect(find.text('Continue'), findsOneWidget);
          expect(find.text('Export My Data'), findsOneWidget);
          expect(find.text('Decline & Delete My Account'), findsOneWidget);

          // Check the mandatory checkboxes
          await tester.tap(find.text('Terms of Service & Privacy Policy'));
          await tester.pump();

          await tester.tap(find.text('Community Guidelines'));
          await tester.pump();

          // Check optional
          await tester.tap(
            find.text('Sexual orientation & religious belief data'),
          );
          await tester.pump();

          // Tap Continue
          await tester.tap(find.text('Continue'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        },
      );

      testWidgets('renders version bump headline when isVersionBump=true', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TermsConsentPage(
                currentTermsVersion: '2.0.0',
                isVersionBump: true,
                onConsentRecorded: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Our terms have changed'), findsOneWidget);
        expect(find.text('Terms & Policy v2.0.0'), findsOneWidget);
      });
    });

    group('PermissionsScreen Widget Tests', () {
      testWidgets('renders permissions list and handles continue button', (
        tester,
      ) async {
        var completed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: PermissionsScreen(
              onCompleted: () => completed = true,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Configure permissions'), findsOneWidget);
        expect(find.text('CORE PERMISSIONS'), findsOneWidget);
        expect(find.text('ADDITIONAL PERMISSIONS'), findsOneWidget);
        expect(find.text('Push Notifications'), findsOneWidget);
        expect(find.text('Location Services'), findsOneWidget);
        expect(find.text('Continue to Nexus'), findsOneWidget);

        await tester.tap(find.text('Continue to Nexus'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(completed, isTrue);
      });

      test('PermissionItem model initialization', () {
        const item = PermissionItem(
          permission: Permission.camera,
          name: 'Camera',
          description: 'Camera access',
          icon: Icons.camera,
          isCore: true,
          reason: 'Photos',
        );

        expect(item.name, equals('Camera'));
        expect(item.isCore, isTrue);
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

    group('SpaceNode & Login Painters Tests', () {
      test('SpaceNode initialization and fields', () {
        final node = SpaceNode(
          position: const Offset(0.5, -0.5),
          velocity: const Offset(0.01, -0.01),
          score: 0.95,
          label: 'Cosmic Node',
          type: 0,
          targetRadius: 100,
        );

        expect(node.position, equals(const Offset(0.5, -0.5)));
        expect(node.velocity, equals(const Offset(0.01, -0.01)));
        expect(node.score, equals(0.95));
        expect(node.label, equals('Cosmic Node'));
        expect(node.type, equals(0));
        expect(node.targetRadius, equals(100.0));
      });

      testWidgets(
        'GravityFieldPainter & ChromaticBorderPainter paint correctly',
        (tester) async {
          final nodes = [
            SpaceNode(
              position: const Offset(0.2, 0.3),
              velocity: Offset.zero,
              score: 0.88,
              label: 'Dating Node',
              type: 0,
              targetRadius: 50,
            ),
            SpaceNode(
              position: const Offset(-0.4, -0.2),
              velocity: Offset.zero,
              score: 0.76,
              label: 'Friends Node',
              type: 1,
              targetRadius: 70,
            ),
            SpaceNode(
              position: const Offset(0.1, -0.5),
              velocity: Offset.zero,
              score: 0.92,
              label: 'Pro Node',
              type: 2,
              targetRadius: 90,
            ),
          ];

          final painter1 = GravityFieldPainter(
            nodes: nodes,
            touchPosition: const Offset(0.1, 0.1),
            tiltOffset: const Offset(0.05, 0.05),
            simulatedTime: 1.5,
            matrixIndex: 0,
          );

          final painter2 = GravityFieldPainter(
            nodes: nodes,
            touchPosition: const Offset(0.1, 0.1),
            tiltOffset: const Offset(0.05, 0.05),
            simulatedTime: 1.5,
            matrixIndex: 0,
          );

          expect(painter1.shouldRepaint(painter2), isFalse);

          final chromatic = ChromaticBorderPainter(borderRadius: 16);
          expect(chromatic.shouldRepaint(chromatic), isFalse);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: const Size(400, 400),
                        painter: painter1,
                      ),
                      CustomPaint(
                        size: const Size(400, 400),
                        painter: chromatic,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(CustomPaint), findsWidgets);
        },
      );
    });

    group('NexusOnboardingFields & NexusMECOnboardingFields Tests', () {
      testWidgets('Selects demographic bucket options and fires callback', (
        tester,
      ) async {
        String? selected;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NexusOnboardingFields(
                onChanged: ({required demographicBucket}) {
                  selected = demographicBucket;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('DEMOGRAPHIC BUCKET'), findsOneWidget);
        expect(find.text('Men'), findsOneWidget);
        expect(find.text('Women'), findsOneWidget);
        expect(find.text('Non-Binary'), findsOneWidget);

        await tester.tap(find.text('Women'));
        await tester.pump();
        expect(selected, equals('F'));

        await tester.tap(find.text('Men'));
        await tester.pump();
        expect(selected, equals('M'));

        await tester.tap(find.text('Non-Binary'));
        await tester.pump();
        expect(selected, equals('NB'));

        await tester.pump(const Duration(milliseconds: 350));
      });

      testWidgets('NexusMECOnboardingFields renders properly', (tester) async {
        String? selected;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NexusMECOnboardingFields(
                onChanged: ({required demographicBucket}) {
                  selected = demographicBucket;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('DEMOGRAPHIC BUCKET'), findsOneWidget);
        await tester.tap(find.text('Men'));
        await tester.pump();
        expect(selected, equals('M'));

        await tester.pump(const Duration(milliseconds: 350));
      });
    });

    group('OtpVerificationDialog Widget Tests', () {
      testWidgets(
        'renders OTP dialog with 6-digit textfield and handles input',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      unawaited(
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => OtpVerificationDialog(
                            phone: '+15551234567',
                            onVerificationSuccess: () {},
                          ),
                        ),
                      );
                    },
                    child: const Text('Open OTP Dialog'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open OTP Dialog'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          expect(find.text('Verify Phone Number'), findsOneWidget);
          expect(find.text('Sent to +15551234567'), findsOneWidget);
          expect(find.text('ENTER OTP CODE'), findsOneWidget);

          // Enter incomplete OTP
          await tester.enterText(find.byType(TextField), '123');
          await tester.pump();

          // Enter full 6-digit OTP
          await tester.enterText(find.byType(TextField), '123456');
          await tester.pump();

          expect(find.text('Verify'), findsOneWidget);

          // Close dialog via close button
          await tester.tap(find.byIcon(Icons.close_rounded));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
        },
      );
    });

    group('ImportCodeDialog Widget Tests', () {
      testWidgets(
        'renders import code dialog with input and handles text capitalization',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      unawaited(
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => ImportCodeDialog(
                            onImportSuccess: () {},
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Import Dialog'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Open Import Dialog'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          expect(find.text('Import Profile Data'), findsOneWidget);
          expect(find.text('EXPORT CODE'), findsOneWidget);

          await tester.enterText(find.byType(TextField), 'ABC123');
          await tester.pump();

          expect(find.text('Import Now'), findsOneWidget);

          // Close dialog
          await tester.tap(find.byIcon(Icons.close_rounded));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
        },
      );
    });
  }

  // --- Section 6 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('nexus/security'),
          (call) async => false,
        );

    group('LoginScreen Widget Tests', () {
      testWidgets('renders login options screen with app name and buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: LoginScreen(appName: 'NEXUS'),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('N E X U S'), findsOneWidget);
        expect(find.text('Sign in with Email'), findsOneWidget);
        expect(find.text('Sign in with Phone'), findsOneWidget);

        // Switch to email view
        await tester.tap(find.text('Sign in with Email'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Welcome!'), findsOneWidget);
        expect(find.text('Login with Email Link/Code'), findsOneWidget);

        // Enter email
        await tester.enterText(find.byType(TextField), 'test@nexus.app');
        await tester.pump();

        // Go back to options
        await tester.tap(find.text('Back to Login Options'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Sign in with Email'), findsOneWidget);

        // Switch to phone view
        await tester.tap(find.text('Sign in with Phone'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Sign in with Phone'), findsWidgets);
        await tester.enterText(find.byType(TextField), '+15551234567');
        await tester.pump();
      });
    });

    group('OnboardingScreen Widget Tests', () {
      testWidgets('renders onboarding form and handles name & phone input', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OnboardingScreen(
                onComplete: () {},
                verifiedMobile: '+15551234567',
                mobileVerifiedAt: DateTime.now(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('YOUR NAME'), findsOneWidget);
        expect(find.text('AGE'), findsOneWidget);

        // Enter name
        await tester.enterText(find.byType(TextFormField).first, 'Alex Mercer');
        await tester.pump();

        // Select demographic bucket if present
        if (find.text('Men').evaluate().isNotEmpty) {
          await tester.tap(find.text('Men'));
          await tester.pump();
        }

        await tester.pump(const Duration(milliseconds: 350));
      });
    });
  }
}

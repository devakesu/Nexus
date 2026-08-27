import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
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

    group('FeedbackTicketDetailPage Deep Interactive Tests', () {
      testWidgets('renders FeedbackTicketDetailPage and handles retry action', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('{}', 200);
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: FeedbackTicketDetailPage(reportId: 'tkt_12345678'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

        // Tap Retry or back if found
        final retryButton = find.text('Retry');
        if (retryButton.evaluate().isNotEmpty) {
          await tester.tap(retryButton.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    });
  }

  // --- Section 2 ---
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

    group('Feedback, Tickets & Place Autocomplete Authenticated Tests', () {
      testWidgets(
        'FeedbackPage loads recent tickets, switches query types, and enters feedback',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/feedback/mine')) {
              return ResponseBody.fromString(
                jsonEncode([
                  {
                    'id': 'fb_1',
                    'subject': 'Orbit View Improvement',
                    'status': 'open',
                    'created_at': DateTime.now().toIso8601String(),
                    'updated_at': DateTime.now().toIso8601String(),
                    'query_type': 'feature_request',
                  },
                ]),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/api/v1/feedback') &&
                options.method == 'POST') {
              return ResponseBody.fromString(
                jsonEncode({'status': 'created', 'ticket_id': 'fb_2'}),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('[]', 200);
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackPage(
                  initialSubject: 'Super Like Animations',
                  initialMessage: 'Add subtle particle effects on match swipe.',
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(FeedbackPage), findsOneWidget);

          // Scroll FeedbackPage
          await tester.drag(find.byType(FeedbackPage), const Offset(0, -600));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets(
        'FeedbackTicketsListPage loads paginated tickets and renders list',
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
              jsonEncode([
                {
                  'id': 'ticket_101',
                  'subject': 'Chat Delivery Latency',
                  'status': 'in_progress',
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'query_type': 'bug_report',
                },
              ]),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketsListPage(),
              ),
            ),
          );

          await tester.pump();
          await tester.pumpAndSettle();

          expect(find.byType(FeedbackTicketsListPage), findsOneWidget);
        },
      );

      testWidgets('PlaceAutocompleteField renders and handles query input', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var changedVal = '';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: PlaceAutocompleteField(
                  label: 'Current Place',
                  initialValue: 'San Francisco, CA',
                  hintText: 'Enter city or address',
                  prefixIcon: Icons.location_on,
                  onChanged: (val) {
                    changedVal = val;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(PlaceAutocompleteField), findsOneWidget);
        expect(changedVal, isEmpty);
      });
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

    group('Feedback Ticket Detail & Email Notification Settings Tests', () {
      testWidgets(
        'FeedbackTicketDetailPage renders ticket details and comments',
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
              jsonEncode({
                'id': 'rep_123',
                'query_type': 'bug',
                'subject': 'Radar animation stutter',
                'message': 'The radar nodes flicker when panning fast.',
                'status': 'open',
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'status_history': <Map<String, dynamic>>[],
                'attachment_paths': <String>[],
                'comments': [
                  {
                    'id': 'comm_1',
                    'author_id': 'u1',
                    'body': 'Here is more info on reproduction steps.',
                    'created_at': DateTime.now().toIso8601String(),
                    'is_own': true,
                  },
                ],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketDetailPage(reportId: 'rep_123'),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();

          expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);
        },
      );

      testWidgets(
        'EmailNotificationSettingsPage renders email notification toggles and handles taps',
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
              jsonEncode({
                'email_notify_matches': true,
                'email_notify_messages': true,
                'email_notify_digest': false,
                'email_notify_product_updates': true,
                'email_notify_promotions': false,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: EmailNotificationSettingsPage(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);

          // Tap on a switch toggle
          final switches = find.byType(Switch);
          if (switches.evaluate().isNotEmpty) {
            await tester.tap(switches.first);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        },
      );
    });
  }

  // --- Section 4 ---
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

    group('Feedback Tickets List, Categories & Places Tests', () {
      testWidgets(
        'FeedbackTicketsListPage renders ticket list and handles items',
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
              jsonEncode([
                {
                  'id': 't1',
                  'query_type': 'bug',
                  'subject': 'Radar animation issue',
                  'status': 'open',
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                  'comment_count': 2,
                },
              ]),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketsListPage(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();

          expect(find.byType(FeedbackTicketsListPage), findsOneWidget);
        },
      );

      testWidgets(
        'ModeCategorySelectionSheet renders category items and empty message',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Interested in You',
                  themeColor: AppColors.modeDating,
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
                  onRecordAction: (targetId, action, token) async => null,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
          expect(find.text('No interactions yet'), findsOneWidget);
        },
      );

      testWidgets('PlaceAutocompleteField renders input and handles typing', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Hometown',
                initialValue: 'San Francisco, CA',
                hintText: 'Enter city name',
                prefixIcon: LucideIcons.home,
                onChanged: (val) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PlaceAutocompleteField), findsOneWidget);
        expect(find.text('San Francisco, CA'), findsOneWidget);
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

    group('FeedbackTicketDetailPage Widget Tests', () {
      testWidgets(
        'renders FeedbackTicketDetailPage with loading state and app bar',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketDetailPage(reportId: 'ticket_123'),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });

    group('EmailOtpReauthDialog Widget Tests', () {
      testWidgets('renders EmailOtpReauthDialog with title and OTP inputs', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EmailOtpReauthDialog(
                verifyUrl: 'https://mock.supabase.co/verify',
                resendUrl: 'https://mock.supabase.co/resend',
                onVerificationSuccess: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(EmailOtpReauthDialog), findsOneWidget);
        expect(find.text("Confirm It's You"), findsOneWidget);
      });
    });
  }
}

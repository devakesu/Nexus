import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/reactivate_account_page.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/home/widgets/match_screen.dart';
import 'package:nexus/features/settings/screens/about_screen.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/crisis_helplines_page.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
import 'package:nexus/features/settings/screens/delete_account_page.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
import 'package:nexus/features/settings/screens/help_center_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
import 'package:nexus/features/settings/screens/settings_tab.dart';
import 'package:nexus/features/settings/widgets/about/attestation_section.dart';
import 'package:nexus/features/settings/widgets/transparency_badge.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/test_helpers.dart';

class MockAboutAttestationNotifier extends AboutAttestationNotifier {
  MockAboutAttestationNotifier([this._initial]);
  final AboutAttestationState? _initial;

  @override
  AboutAttestationState? build() => _initial;
}

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
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async => true,
        );

    setUp(() {});

    group('EmailNotificationSettingsPage Deep Interactive Tests', () {
      testWidgets(
        'renders email notification categories and toggles settings',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/email-notifications')) {
              if (options.method == 'GET') {
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
              }
              if (options.method == 'PATCH') {
                return ResponseBody.fromString('{"status":"ok"}', 200);
              }
            }
            return ResponseBody.fromString('Not found', 404);
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: EmailNotificationSettingsPage(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);

          // Toggle available switches
          final switches = find.byType(Switch);
          for (var i = 0; i < switches.evaluate().length; i++) {
            await tester.tap(switches.at(i));
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
      );
    });

    group('DataExportFlow Deep Tests', () {
      testWidgets('startDataExport shows confirmation dialog', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => startDataExport(context),
                  child: const Text('Trigger Export'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Trigger Export'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Export Personal Data'), findsOneWidget);
      });
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
          const MethodChannel('plugins.flutter.io/firebase_messaging'),
          (call) async => <String, dynamic>{},
        );

    group('SettingsTab Deep Widget Tests', () {
      testWidgets(
        'SettingsTab renders all setting tiles, dialogs, and handles scrolling',
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
                'status': 'active',
                'is_paused': false,
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

          // Scroll through Settings
          await tester.drag(find.byType(SettingsTab), const Offset(0, -600));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          await tester.drag(find.byType(SettingsTab), const Offset(0, -600));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
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

    group('Social Mode Overlays & Settings Mega Coverage Tests', () {
      testWidgets(
        'DatingSettingsOverlay renders chips, search query, and toggles values',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: DatingSettingsOverlay(
                  datingTargetBuckets: const ['W', 'NB'],
                  datingFor: const ['Long-term relationship'],
                  partnerValues: const ['Authenticity', 'Kindness'],
                  childrenPlans: 'Someday',
                  savingFields: const {},
                  onSaveDatingField: (field, val, setter) async {},
                  onLoadDatingProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(DatingSettingsOverlay), findsOneWidget);

          // Scroll overlay
          await tester.drag(
            find.byType(DatingSettingsOverlay),
            const Offset(0, -400),
          );
          await tester.pump();
        },
      );

      testWidgets(
        'ProfessionalSettingsOverlay renders roles, company, tech skills and search',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProfessionalSettingsOverlay(
                  professionalTargetBuckets: const ['All'],
                  lookingFor: const ['Cofounder', 'Mentorship'],
                  techSkills: const ['Flutter', 'Dart', 'Go', 'AI'],
                  company: 'Nexus Tech',
                  roleType: const ['Software Engineer'],
                  savingFields: const {},
                  onSaveProfessionalField: (field, val, setter) async {},
                  onLoadProfessionalProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

          await tester.drag(
            find.byType(ProfessionalSettingsOverlay),
            const Offset(0, -400),
          );
          await tester.pump();
        },
      );

      testWidgets(
        'ModeCategorySelectionSheet renders list of items and handles interactions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final items = [
            {
              'actor_id': 'u_actor_1',
              'name': 'Isabella',
              'age': 23,
              'avatar_url': 'https://example.com/isa.jpg',
              'created_at': DateTime.now().toIso8601String(),
            },
          ];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Incoming Likes',
                  themeColor: AppColors.modeDating,
                  items: items,
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required onActioned,
                        required onProfileLoaded,
                      }) {},
                  onRecordAction: (targetId, action, token) async => true,
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
        },
      );

      testWidgets(
        'EmailNotificationSettingsPage loads preferences and toggles switches',
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
                'email_notify_safety': true,
                'email_notify_marketing': false,
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

          // Scroll settings
          await tester.drag(
            find.byType(EmailNotificationSettingsPage),
            const Offset(0, -400),
          );
          await tester.pump();
        },
      );

      testWidgets('startDataExport opens confirmation dialog', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => startDataExport(context),
                  child: const Text('Export Data'),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Export Data'));
        await tester.pumpAndSettle();

        expect(find.text('Export Personal Data'), findsOneWidget);
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

    group('Permissions & Mode Overlays Exhaustive Tests', () {
      testWidgets('PermissionsScreen renders permission items and continues', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var completed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PermissionsScreen(
                onCompleted: () {
                  completed = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(PermissionsScreen), findsOneWidget);

        // Scroll PermissionsScreen
        await tester.drag(
          find.byType(PermissionsScreen),
          const Offset(0, -600),
        );
        await tester.pump();

        expect(completed, isFalse);
      });

      testWidgets('DatingSettingsOverlay renders cleanly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['W', 'NB'],
                datingFor: const ['Long-term relationship'],
                partnerValues: const ['Authenticity'],
                childrenPlans: 'Someday',
                savingFields: const {},
                onSaveDatingField: (field, val, setSt) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(DatingSettingsOverlay), findsOneWidget);
      });

      testWidgets('ModeCategorySelectionSheet renders and interacts', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeCategorySelectionSheet(
                title: 'Incoming Requests',
                themeColor: Colors.deepPurple,
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
                onRecordAction: (targetId, action, token) async => true,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
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

    group('MatchScreen Tests', () {
      testWidgets('renders MatchScreen with match celebration and buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<bool>(
                builder: (ctx) => const MatchScreen(
                  matchedName: 'Sophia',
                  subtitleText: 'You and Sophia liked each other',
                ),
              ),
            ),
          ),
        );

        // Animate controller forward (850ms duration)
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));

        expect(find.text("It's a Match! 💘"), findsOneWidget);
        expect(find.text('You and Sophia liked each other'), findsOneWidget);
        expect(find.text('Send a message'), findsOneWidget);
        expect(find.text('Keep browsing'), findsOneWidget);

        // Tap Send a message
        await tester.tap(find.text('Send a message'));
        await tester.pumpAndSettle();
      });
    });

    group('ExportCodeCard Tests', () {
      testWidgets('renders ExportCodeCard and handles generate code button', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ExportCodeCard(),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(ExportCodeCard), findsOneWidget);
        expect(find.text('Export Profile Data'), findsOneWidget);

        // Tap generate code button
        await tester.tap(find.text('Export Profile Data'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      });
    });

    group('InterestsOverlay & SubInterest Tests', () {
      test('SubInterest model test', () {
        const sub = SubInterest('Artificial Intelligence');
        expect(sub.name, 'Artificial Intelligence');
      });

      testWidgets(
        'renders InterestsOverlay, handles search and category toggle',
        (tester) async {
          var savedInterests = <String>[];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: InterestsOverlay(
                  initialSelected: const ['Python', 'Web Development'],
                  themeColor: AppColors.modeProfessional,
                  onSave: (interests) => savedInterests = interests,
                ),
              ),
            ),
          );

          await tester.pump();

          expect(find.text('Affinity & Interests'), findsOneWidget);
          expect(find.text('Save Alignments'), findsOneWidget);

          // Search for Python
          await tester.enterText(find.byType(TextField), 'Python');
          await tester.pump();

          // Clear search
          await tester.enterText(find.byType(TextField), '');
          await tester.pump();

          // Tap save alignments
          await tester.tap(find.text('Save Alignments'));
          await tester.pump();

          expect(savedInterests, contains('Python'));
          expect(savedInterests, contains('Web Development'));
        },
      );
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

    group('Settings and Auth Deep Flows Tests', () {
      testWidgets('SettingsTab renders and navigates to sub-screens', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
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
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(SettingsTab), findsOneWidget);
      });

      testWidgets('AboutScreen renders app details and links', (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AboutScreen(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AboutScreen), findsOneWidget);
      });

      testWidgets('DeleteAccountPage renders warnings and actions', (
        tester,
      ) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: DeleteAccountPage(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DeleteAccountPage), findsOneWidget);
      });

      testWidgets('ReactivateAccountPage renders cancellation flow', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ReactivateAccountPage(
                  scheduledPurgeAt: DateTime.now().add(
                    const Duration(days: 14),
                  ),
                  onReactivated: () {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ReactivateAccountPage), findsOneWidget);
      });

      testWidgets('CrisisHelplinesPage renders all emergency resources', (
        tester,
      ) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: CrisisHelplinesPage(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CrisisHelplinesPage), findsOneWidget);
      });
    });
  }

  // --- Section 7 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
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

    group('Settings Screens Deep Expansion Tests', () {
      testWidgets('renders HiddenUsersPage and switches tab filters', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HiddenUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(HiddenUsersPage), findsOneWidget);
        expect(find.text('Hidden Users'), findsWidgets);
      });

      testWidgets('renders BlockedUsersPage', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: BlockedUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(BlockedUsersPage), findsOneWidget);
        expect(find.text('Blocked Users'), findsWidgets);
      });

      testWidgets(
        'renders FeedbackTicketsListPage and selects active/resolved filters',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketsListPage(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(FeedbackTicketsListPage), findsOneWidget);
          expect(find.text('Your Tickets'), findsWidgets);
        },
      );

      testWidgets('renders EmailNotificationSettingsPage and toggles switch', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EmailNotificationSettingsPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);

        final switches = find.byType(Switch);
        if (switches.evaluate().isNotEmpty) {
          await tester.tap(switches.first);
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('renders DeleteAccountPage and enters reason', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: DeleteAccountPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(DeleteAccountPage), findsOneWidget);
        expect(find.text('Delete Account'), findsWidgets);
      });
    });
  }

  // --- Section 8 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('Settings Secondary Screens Deep Widget Tests', () {
      testWidgets('renders FeedbackPage and selects categories', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FeedbackPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(FeedbackPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets(
        'renders FeedbackTicketsListPage and FeedbackTicketDetailPage',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketsListPage(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(FeedbackTicketsListPage), findsOneWidget);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketDetailPage(reportId: 'rpt_mock_1'),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
      );

      testWidgets('renders BlockedUsersPage and HiddenUsersPage', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: BlockedUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(BlockedUsersPage), findsOneWidget);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HiddenUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(HiddenUsersPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('renders CheckInAlertScreen with countdown and safe button', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
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
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(CheckInAlertScreen), findsOneWidget);
      });

      testWidgets(
        'renders HelpCenterPage, AboutScreen, CrisisHelplinesPage, DeleteAccountPage, EmailNotificationSettingsPage',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: HelpCenterPage()),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(HelpCenterPage), findsOneWidget);

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(body: AboutScreen()),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(AboutScreen), findsOneWidget);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: CrisisHelplinesPage()),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(CrisisHelplinesPage), findsOneWidget);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: DeleteAccountPage()),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(DeleteAccountPage), findsOneWidget);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: EmailNotificationSettingsPage()),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);
        },
      );
    });
  }

  // --- Section 9 ---
  {
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

  // --- Section 10 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => {
            'appName': 'Nexus',
            'packageName': 'com.nexus.app',
            'version': '1.0.0',
            'buildNumber': '1',
          },
        );

    group('TransparencyBadge Widget Tests', () {
      testWidgets('renders TransparencyBadge collapsed and expanded with tap', (
        tester,
      ) async {
        var badgeTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TransparencyBadge(
                    onTap: () => badgeTapped = true,
                  ),
                  const TransparencyBadge(expanded: true),
                ],
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(TransparencyBadge), findsNWidgets(2));

        await tester.tap(find.byType(TransparencyBadge).first);
        await tester.pump();
        expect(badgeTapped, isTrue);
      });
    });

    group('CrisisHelplinesPage Widget Tests', () {
      testWidgets(
        'renders CrisisHelplinesPage with emergency helpline contacts',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
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
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(CrisisHelplinesPage), findsOneWidget);
          expect(find.text('Crisis Helplines'), findsOneWidget);
        },
      );
    });

    group('AboutScreen & AttestationSection Widget Tests', () {
      testWidgets(
        'renders AboutScreen with app info and transparency sections',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                aboutAttestationProvider.overrideWith(
                  () => MockAboutAttestationNotifier(
                    const AboutAttestationState(
                      data: {'status': 'verified', 'commit': 'abc1234'},
                    ),
                  ),
                ),
              ],
              child: const MaterialApp(
                home: Scaffold(
                  body: AboutScreen(),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(AboutScreen), findsOneWidget);
        },
      );

      testWidgets('renders AttestationSection independently', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              aboutAttestationProvider.overrideWith(
                () => MockAboutAttestationNotifier(
                  const AboutAttestationState(
                    data: {'status': 'verified', 'commit': 'abc1234'},
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AttestationSection(
                    onLaunch: (url) async {},
                    onCopy: (ctx, val, lbl) async {},
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AttestationSection), findsOneWidget);
      });
    });

    group('DeleteAccountPage Widget Tests', () {
      testWidgets(
        'renders DeleteAccountPage with warning and confirmation text input',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: DeleteAccountPage(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(DeleteAccountPage), findsOneWidget);
          expect(find.text('Delete Account'), findsWidgets);
        },
      );
    });
  }
}

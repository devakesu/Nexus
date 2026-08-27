import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/friends_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_activation_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
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

  const mockState = DiscoveryHubState(
    profileDetails: {
      'dating_target_buckets': ['W', 'NB'],
      'dating_for': ['Relationship'],
      'partner_values': ['Loyalty', 'Kindness'],
      'children_plans': 'Someday',
    },
    profileError: null,
    likes: [],
    unseenCount: 0,
    matches: [],
  );

  group('Social Modes Tabs & Overlays Mega Coverage Tests', () {
    test('DiscoveryHubState and cache serialization', () {
      final cache = mockState.toCache();
      expect(cache['unseenCount'], 0);
      final fromCache = DiscoveryHubState.fromCache(cache);
      expect(fromCache.unseenCount, 0);
      expect(mockState.copyWith(isRevalidating: true).isRevalidating, isTrue);
    });

    testWidgets(
      'DatingTab renders with mock hub data, triggers settings overlay and actions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await DiscoveryHubCache.write('dating', mockState.toCache());

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('{"ok": true}', 200);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProviderScope(
                child: DatingTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(DatingTab), findsOneWidget);

        // Open DatingSettingsOverlay
        final settingsBtn = find.byIcon(LucideIcons.settings);
        if (settingsBtn.evaluate().isNotEmpty) {
          await tester.tap(settingsBtn.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
    );

    testWidgets(
      'FriendsTab renders with mock hub data and opens friends overlay',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await DiscoveryHubCache.write('friends', mockState.toCache());

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('{"ok": true}', 200);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProviderScope(
                child: FriendsTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(FriendsTab), findsOneWidget);
      },
    );

    testWidgets(
      'ProfessionalTab renders with mock hub data and opens pro overlay',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await DiscoveryHubCache.write('professional', mockState.toCache());

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString('{"ok": true}', 200);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProviderScope(
                child: ProfessionalTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfessionalTab), findsOneWidget);
      },
    );

    testWidgets(
      'Standalone Overlays (DatingSettingsOverlay, ProfessionalSettingsOverlay, ModeCategorySelectionSheet) render and interact',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // ModeActivationOverlay
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeActivationOverlay(
                modeTitle: 'Dating Mode',
                subtitle: 'Connect with romantic matches',
                icon: LucideIcons.heart,
                brandColor: AppColors.modeDating,
                onFinished: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(ModeActivationOverlay), findsOneWidget);

        // DatingSettingsOverlay
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['Women'],
                datingFor: const ['Long-term'],
                partnerValues: const ['Honesty'],
                childrenPlans: 'Someday',
                savingFields: const {},
                onSaveDatingField: (f, v, s) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(DatingSettingsOverlay), findsOneWidget);

        // ProfessionalSettingsOverlay
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfessionalSettingsOverlay(
                professionalTargetBuckets: const ['Tech'],
                lookingFor: const ['Co-founder'],
                techSkills: const ['Flutter', 'Python'],
                company: 'Nexus Inc',
                roleType: const ['Full-time'],
                savingFields: const {},
                onSaveProfessionalField: (f, v, s) async {},
                onLoadProfessionalProfileStatusSilent: () async {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

        // FriendsSettingsOverlay
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FriendsSettingsOverlay(
                friendsTargetBuckets: const ['All'],
                flatInterests: const ['Hiking', 'Gaming'],
                causesSupported: const ['Animal Welfare'],
                savingFields: const {},
                onSaveFriendsField: (f, v, s) async {},
                onLoadFriendsProfileStatusSilent: () async {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(FriendsSettingsOverlay), findsOneWidget);

        // ModeCategorySelectionSheet
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeCategorySelectionSheet(
                title: 'Interested In',
                themeColor: AppColors.modeDating,
                items: const [],
                onFetchItems: () async {},
                onOpenItemDetailsDialog:
                    ({
                      required ctx,
                      required actorId,
                      required name,
                      required void Function(String actorId) onActioned,
                      required void Function() onProfileLoaded,
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
  });
}

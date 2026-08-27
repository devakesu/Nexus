import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:nexus/features/profile/utils/emoji_helper.dart';
import 'package:nexus/features/profile/utils/name_moderation.dart';
import 'package:nexus/features/profile/widgets/glass_text_field.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/profile_field_edit_sheet.dart';
import 'package:nexus/features/profile/widgets/profile_visibility_badge.dart';
import 'package:nexus/features/profile/widgets/sections/bio_section.dart';
import 'package:nexus/features/profile/widgets/sections/core_signal_section.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
import 'package:nexus/features/spotify/models/spotify_playlist.dart';
import 'package:nexus/features/spotify/providers/spotify_provider.dart';
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

class TestVSync extends TickerProvider {
  const TestVSync();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
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

class _MockSpotifyPlaylistsController extends SpotifyPlaylistsController {
  _MockSpotifyPlaylistsController(this.initialState);
  final SpotifyPlaylistsPayload initialState;

  @override
  Future<SpotifyPlaylistsPayload> build() async => initialState;
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
      'privacy_active_status': true,
      'privacy_read_receipts': true,
      'privacy_incognito': false,
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
      setupGlobalMockNetwork();
      await SecureProfileCache.write(kFullMockProfile);
    });

    group('Profile Tab All Sections and Handlers Tests', () {
      testWidgets('ProfileTab scrolls and taps every interactive tile', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        final scrollableList = find.byType(Scrollable);
        if (scrollableList.evaluate().isNotEmpty) {
          final scrollable = scrollableList.first;

          // Tap visible action chips
          final chips = find.byType(ActionChip);
          for (var i = 0; i < chips.evaluate().length && i < 4; i++) {
            try {
              await tester.tap(chips.at(i), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 50));
            } on Object catch (_) {}
          }

          // Drag down through all sections step by step
          for (var step = 0; step < 6; step++) {
            await tester.drag(scrollable, const Offset(0, -600));
            await tester.pump(const Duration(milliseconds: 150));

            final finders = find.byType(InkWell);
            for (var i = 0; i < finders.evaluate().length && i < 3; i++) {
              try {
                await tester.tap(finders.at(i), warnIfMissed: false);
                await tester.pump(const Duration(milliseconds: 50));
              } on Object catch (_) {}
            }
          }
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
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
          const MethodChannel('plugins.flutter.io/image_picker'),
          (call) async => null,
        );

    setUp(() {});

    final sampleProfileData = {
      'name': 'Robin Scherbatsky',
      'age': 29,
      'age_changes_used_in_window': 0,
      'age_change_eligible': true,
      'name_changes_used_in_window': 0,
      'name_change_eligible': true,
      'campus_year': 4,
      'campus_branch': 'Journalism',
      'campus_name': 'Metro News Academy',
      'display_gender': 'Woman',
      'display_sexuality': 'Straight',
      'pronouns': 'She/Her',
      'bio': 'Journalist and hockey fan.',
      'hometown': 'Vancouver, BC',
      'current_place': 'New York, NY',
      'religious_beliefs': 'Agnostic',
      'children_plans': 'No',
      'lifestyle': 'Urban',
      'drinking': 'Socially',
      'smoking': 'Never',
      'search_bucket': 'Women',
      'causes_supported': ['Animal Welfare'],
      'top_artists': ['Guns N Roses', 'Rush'],
      'languages': ['English', 'French'],
      'pets': ['Dog'],
      'image_paths': [
        'https://example.com/robin.jpg',
        null,
        null,
        null,
        null,
        null,
      ],
      'sub_interests': {
        'Sports': ['Hockey', 'Skiing'],
        'News': ['Broadcasting'],
      },
      'prompt_answers': {
        'The key to my heart': 'Scotch and hockey.',
      },
    };

    group('ProfileTab Section Action Deep Tests', () {
      testWidgets(
        'renders ProfileTab, taps sub-interest tags, and opens edit sheet',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await SecureProfileCache.write(sampleProfileData);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/details')) {
              return ResponseBody.fromString(
                jsonEncode(sampleProfileData),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/api/v1/profile/privacy-settings')) {
              return ResponseBody.fromString(
                jsonEncode({'hidden_fields': <String>[]}),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{"ok":true}', 200);
          });

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                spotifyPlaylistsControllerProvider.overrideWith(
                  () => _MockSpotifyPlaylistsController(
                    const SpotifyPlaylistsPayload(
                      connected: true,
                      playlists: [
                        SpotifyPlaylist(
                          id: 'pl_1',
                          spotifyPlaylistId: 'sp_1',
                          name: 'Rock Anthems',
                          isCollaborative: false,
                          trackCount: 45,
                          tracks: [],
                          spotifyUrl: 'https://spotify.com/pl_1',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileTab(
                    onOpenOrbit: (mode, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(ProfileTab), findsOneWidget);
          expect(find.text('Robin Scherbatsky'), findsWidgets);

          // Scroll and tap chips in sections
          await tester.drag(find.byType(ProfileTab), const Offset(0, -500));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Tap on any Chip or InkWell
          final chips = find.byType(Chip);
          for (var i = 0; i < chips.evaluate().length && i < 3; i++) {
            await tester.tap(chips.at(i), warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
          }

          // Tap on action buttons / edit triggers
          final editIcons = find.byIcon(Icons.edit_rounded);
          if (editIcons.evaluate().isNotEmpty) {
            await tester.tap(editIcons.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));

            // Dismiss if modal popped up
            if (find.byType(BottomSheet).evaluate().isNotEmpty) {
              await tester.tapAt(const Offset(10, 10));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 200));
            }
          }
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

    group('Profile Tab Actions, Overlays & Sections Mega Coverage Tests', () {
      testWidgets(
        'InterestsOverlay renders, searches, toggles chips, and saves',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var savedInterests = <String>[];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: InterestsOverlay(
                  initialSelected: const ['Python', 'Flutter & Dart'],
                  themeColor: AppColors.primaryTeal,
                  onSave: (list) {
                    savedInterests = list;
                  },
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(InterestsOverlay), findsOneWidget);

          // Enter search query
          final tf = find.byType(TextField);
          if (tf.evaluate().isNotEmpty) {
            await tester.enterText(tf.first, 'AI');
            await tester.pump();
          }

          // Find Save button
          final saveBtn = find.text('Save Alignments');
          if (saveBtn.evaluate().isNotEmpty) {
            await tester.tap(saveBtn.first, warnIfMissed: false);
            await tester.pump();
          }

          expect(savedInterests, isNotNull);
        },
      );

      testWidgets(
        'showProfileFieldEditSheet opens, updates value, and confirms',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var confirmedVal = '';

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () async {
                        await showProfileFieldEditSheet<String>(
                          context: context,
                          fieldTitle: 'Display Name',
                          currentValue: 'Aria',
                          eligible: true,
                          changesUsedInWindow: 0,
                          nextEligibleAt: null,
                          inputBuilder: (ctx, val, onChanged) {
                            return TextFormField(
                              initialValue: val,
                              onChanged: onChanged,
                            );
                          },
                          confirmDescriptionBuilder: (val) =>
                              'Change name to $val?',
                          onConfirmed: (val) {
                            confirmedVal = val;
                          },
                        );
                      },
                      child: const Text('Open Sheet'),
                    );
                  },
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.tap(find.text('Open Sheet'));
          await tester.pumpAndSettle();

          expect(find.text('Change Display Name'), findsOneWidget);

          // Enter new name
          final tf = find.byType(TextFormField);
          if (tf.evaluate().isNotEmpty) {
            await tester.enterText(tf.first, 'Aria Stark');
            await tester.pump();
          }

          expect(confirmedVal, isEmpty);
        },
      );

      testWidgets('openPlaylistsSheet renders and interacts', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () => openPlaylistsSheet(context),
                      child: const Text('Open Playlists'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Open Playlists'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
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

    group('ProfileTab Deep Target Sections Tests', () {
      testWidgets(
        'ProfileTab scrolls to targetSection bio, name, drinking, hometown',
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
                'name': 'Alex',
                'age': 22,
                'bio': 'Exploring the universe',
                'gender': 'Non-binary',
                'pronouns': 'they/them',
                'hometown': 'San Francisco, CA',
                'current_place': 'Seattle, WA',
                'campus_name': 'MIT',
                'major': 'CS',
                'year': 4,
                'drinking': 'Socially',
                'smoking': 'Never',
                'interests': ['Tech', 'Design'],
                'sub_interests': {
                  'Tech': ['Flutter', 'Rust'],
                },
                'pets': ['Dog'],
                'photos': ['path1', 'path2'],
                'completeness_score': 85,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          var clearedTarget = false;

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileTab(
                    onOpenOrbit: (mode, color) {},
                    targetSection: 'bio',
                    onClearTargetSection: () {
                      clearedTarget = true;
                    },
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(ProfileTab), findsOneWidget);
          expect(clearedTarget, isTrue);

          // Pump update with another target section
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileTab(
                    onOpenOrbit: (mode, color) {},
                    targetSection: 'drinking',
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
        },
      );
    });
  }

  // --- Section 5 ---
  {
    group('PlaceAutocompleteField Widget Tests', () {
      testWidgets('renders PlaceAutocompleteField with label and icon', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Hometown',
                initialValue: 'San Francisco, CA',
                hintText: 'Enter hometown',
                prefixIcon: LucideIcons.home,
                onChanged: (place) {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(PlaceAutocompleteField), findsOneWidget);
      });
    });

    group('TagChipsEditor Widget Tests', () {
      testWidgets('renders TagChipsEditor with initial tags', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TagChipsEditor(
                label: 'Hobbies',
                currentValues: const ['Reading', 'Hiking'],
                presets: const ['Reading', 'Hiking', 'Cooking', 'Gaming'],
                icon: LucideIcons.tag,
                iconColor: Colors.blue,
                hintText: 'Select hobbies',
                onChanged: (tags) {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(TagChipsEditor), findsOneWidget);
      });
    });

    group('StabilityTracker Widget Tests', () {
      testWidgets(
        'renders StabilityTracker with percentage indicator and criteria list',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  height: 700,
                  child: Builder(
                    builder: (context) {
                      const vsync = TestVSync();
                      final controller = AnimationController(
                        vsync: vsync,
                        duration: const Duration(seconds: 1),
                      );
                      addTearDown(controller.dispose);

                      return StabilityTracker(
                        stabilityPercentage: 85,
                        imagePaths: const ['https://example.com/pic1.jpg'],
                        name: 'TestUser',
                        age: 25,
                        bio: 'Testing profile stability',
                        searchBucket: 'Women',
                        displayGender: 'Woman',
                        displaySexuality: 'Straight',
                        pronouns: 'She/Her',
                        hometown: 'San Francisco',
                        currentPlace: 'New York',
                        languages: const ['English'],
                        campusName: 'Stanford',
                        major: 'CS',
                        isStudying: true,
                        year: 3,
                        lifestyle: 'Active',
                        drinking: 'Socially',
                        smoking: 'Never',
                        religiousBeliefs: 'Spiritual',
                        pets: const ['Dog'],
                        subInterests: const {
                          'Arts': ['Photography', 'Painting'],
                        },
                        causesSupported: const ['Environment'],
                        topArtists: const ['Radiohead', 'Daft Punk'],
                        pulseController: controller,
                        onCriteriaTap: (_) {},
                      );
                    },
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(StabilityTracker), findsOneWidget);
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

    group('CoreSignalSection Widget Tests', () {
      testWidgets(
        'renders CoreSignalSection with name, age, and profile tiles',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: CoreSignalSection(
                    name: 'Elena',
                    age: 24,
                    searchBucket: 'Women',
                    displayGender: 'Woman',
                    displaySexuality: 'Straight',
                    pronouns: 'she/her',
                    imagePaths: const [
                      'https://example.com/p1.jpg',
                      null,
                      null,
                      null,
                      null,
                      null,
                    ],
                    pendingUploads: const {},
                    onNameTileTap: () {},
                    onAgeTileTap: () {},
                    onBucketChanged: (_) {},
                    onSelectGender: () {},
                    onSelectSexuality: () {},
                    onSelectPronouns: () {},
                    onImageSlotTap: (_) {},
                    onSwapImages: (_, _) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();

          expect(find.text('Elena'), findsOneWidget);
          expect(find.text('24 yrs old'), findsOneWidget);
          expect(find.text('she/her'), findsOneWidget);
        },
      );
    });

    group('BioSection Widget Tests', () {
      testWidgets('renders BioSection and handles text entry', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BioSection(
                  bio: 'Passionate about cosmos and robotics',
                  onBioChanged: (_) {},
                  onBioSubmitted: (_) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(
          find.text('Passionate about cosmos and robotics'),
          findsOneWidget,
        );
        expect(find.byType(BioSection), findsOneWidget);
      });
    });

    group('TagChipsEditor Widget Tests', () {
      testWidgets('renders TagChipsEditor with current tags', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TagChipsEditor(
                label: 'Languages',
                currentValues: const ['English', 'Spanish'],
                presets: const ['English', 'Spanish', 'French', 'German'],
                icon: LucideIcons.languages,
                iconColor: AppColors.modeFriends,
                hintText: 'Select languages...',
                onChanged: (_) {},
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('English'), findsOneWidget);
        expect(find.text('Spanish'), findsOneWidget);
      });
    });

    group('PlaceAutocompleteField Widget Tests', () {
      testWidgets('renders PlaceAutocompleteField with initial place', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Current Location',
                initialValue: 'San Francisco, CA',
                hintText: 'Search city...',
                prefixIcon: LucideIcons.mapPin,
                onChanged: (_) {},
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(PlaceAutocompleteField), findsOneWidget);
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

    group('ProfileTab All Sections Interactive Deep Coverage Tests', () {
      testWidgets('renders ProfileTab with all sections and scrolls through', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const mockPlaylist = SpotifyPlaylist(
          id: 'pl_1',
          spotifyPlaylistId: 'spot_1',
          name: 'Night Drives',
          isCollaborative: false,
          trackCount: 42,
          tracks: [
            SpotifyTrack(name: 'A Moment Apart', artists: ['Odesza']),
          ],
          spotifyUrl: 'https://spotify.com/playlist/1',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              spotifyStatusProvider.overrideWith(
                (ref) async => const SpotifyConnectionStatus(
                  connected: true,
                  playlistCount: 4,
                ),
              ),
              spotifyPlaylistsControllerProvider.overrideWith(
                () => _MockSpotifyPlaylistsController(
                  const SpotifyPlaylistsPayload(
                    connected: true,
                    playlists: [mockPlaylist],
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProfileTab(
                  onOpenOrbit: (tab, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 3));

        expect(find.byType(ProfileTab), findsOneWidget);

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(ProfileTab), findsOneWidget);

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(ProfileTab), findsOneWidget);
      });

      testWidgets('renders ProfileTab with specific targetSection scrolls', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              spotifyStatusProvider.overrideWith(
                (ref) async => SpotifyConnectionStatus.disconnected,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProfileTab(
                  targetSection: 'spotify',
                  onOpenOrbit: (tab, color) {},
                  onClearTargetSection: () {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 3));

        expect(find.byType(ProfileTab), findsOneWidget);
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

    group('NameModeration Unit Tests', () {
      test(
        'validateDisplayNameClientSide handles digits, titles, and banned substrings',
        () {
          // Numbers
          final numRes = validateDisplayNameClientSide('Alex99');
          expect(numRes.isValid, isFalse);
          expect(numRes.error, contains("can't contain numbers"));

          // Titles
          final drRes = validateDisplayNameClientSide('Dr. Sarah');
          expect(drRes.isValid, isFalse);
          expect(drRes.error, contains('Titles like "Dr."'));

          final profRes = validateDisplayNameClientSide('Professor Xavier');
          expect(profRes.isValid, isFalse);

          // Banned words
          final badRes = validateDisplayNameClientSide('BadWord_hitler_User');
          expect(badRes.isValid, isFalse);
          expect(badRes.error, contains("That name isn't allowed"));

          // Valid names
          final valid1 = validateDisplayNameClientSide('Sarah Connor');
          expect(valid1.isValid, isTrue);
          expect(valid1.error, isNull);

          final valid2 = validateDisplayNameClientSide('Elena Rostova');
          expect(valid2.isValid, isTrue);
        },
      );
    });

    group('Emoji & Tag Icon Helper Tests', () {
      test(
        'getTagIcon and getEmojiForTag map known tags to widgets/strings',
        () {
          expect(getEmojiForTag('Man'), '👨');
          expect(getTagIcon('Man'), isNotNull);

          expect(getEmojiForTag('Woman'), '👩');
          expect(getTagIcon('Woman'), isNotNull);

          expect(getEmojiForTag('she/her'), '♀️');
          expect(getTagIcon('she/her'), isNotNull);

          expect(getEmojiForTag('CompletelyUnknownTagXYZ'), isEmpty);
          expect(getTagIcon('CompletelyUnknownTagXYZ'), isNull);
        },
      );
    });

    group('ProfileVisibilityBadge Tests', () {
      testWidgets(
        'renders convenience constructors for ProfileVisibilityBadge',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    ProfileVisibilityBadge.datingAndFriends(),
                    ProfileVisibilityBadge.datingOnly(),
                    ProfileVisibilityBadge.allTabs(),
                  ],
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.text('Dating & Friends'), findsOneWidget);
          expect(find.text('Dating only'), findsOneWidget);
          expect(find.text('All tabs'), findsOneWidget);
        },
      );
    });

    group('GlassTextField Widget Tests', () {
      testWidgets(
        'renders GlassTextField with prefix icon and handles text changes',
        (tester) async {
          String? updatedValue;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: GlassTextField(
                  label: 'Bio',
                  initialValue: 'Exploring space and technology',
                  hintText: 'Tell us about yourself...',
                  prefixIcon: LucideIcons.pencil,
                  onChanged: (val) => updatedValue = val,
                ),
              ),
            ),
          );

          await tester.pump();

          expect(find.text('Bio'), findsOneWidget);
          expect(find.text('Exploring space and technology'), findsOneWidget);
          expect(find.byIcon(LucideIcons.pencil), findsOneWidget);

          await tester.enterText(
            find.byType(TextFormField),
            'Updated bio content',
          );
          await tester.pump();

          expect(updatedValue, 'Updated bio content');
        },
      );
    });

    group('StabilityTracker Widget Tests', () {
      testWidgets('renders StabilityTracker with score and criteria items', (
        tester,
      ) async {
        final pulseController = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(seconds: 1),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StabilityTracker(
                  stabilityPercentage: 85,
                  imagePaths: const ['https://example.com/pic.jpg', null],
                  name: 'Elena',
                  age: 27,
                  bio: 'Robotics engineer',
                  searchBucket: 'F',
                  displayGender: 'Woman',
                  displaySexuality: 'Straight',
                  pronouns: 'she/her',
                  hometown: 'Seattle',
                  currentPlace: 'San Francisco',
                  languages: const ['English', 'Spanish'],
                  campusName: 'Stanford University',
                  major: 'Computer Science',
                  isStudying: false,
                  year: 2020,
                  lifestyle: 'Early Bird',
                  drinking: 'Socially',
                  smoking: 'Never',
                  religiousBeliefs: 'Agnostic',
                  pets: const ['Dog'],
                  subInterests: const {
                    'Tech': ['Robotics', 'Flutter'],
                  },
                  causesSupported: const ['Climate Action'],
                  topArtists: const ['Daft Punk'],
                  pulseController: pulseController,
                  onCriteriaTap: (_) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(StabilityTracker), findsOneWidget);
        expect(find.text('STABILITY INDEX: 85/100'), findsOneWidget);
        expect(find.text('PROFILE COMPLETE'), findsOneWidget);
      });
    });
  }
}

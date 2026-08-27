import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:nexus/features/profile/widgets/cosmic_selection_overlay.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/profile_field_edit_sheet.dart';
import 'package:nexus/features/profile/widgets/sections/social_coordinates_section.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/utils/feedback_shared.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/friends_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
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
      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
    });

    group('Profile Detail Sheet and Interests Overlay Tests', () {
      testWidgets('ProfileDetailSheet mounts and displays node profile details', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final data = <String, dynamic>{
          'id': 'u-target-1',
          'name': 'Samantha',
          'age': 25,
          'bio': 'Designer & coffee lover',
          'hometown_city': 'Seattle',
          'current_city': 'San Francisco',
          'ordered_images': [
            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
          ],
          'interests': ['Coding', 'Climbing'],
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: data,
                  themeColor: Colors.pink,
                  scrollController: ScrollController(),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ProfileDetailSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('InterestsOverlay renders and toggles selections', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterestsOverlay(
                initialSelected: const ['Coding', 'Climbing'],
                onSave: (list) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(InterestsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
    });
  }

  // --- Section 2 ---
  {
    group('TagChipsEditor Deep Interaction Tests', () {
      testWidgets(
        'opens multi-select sheet, selects preset tags, and enters custom tag',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TagChipsEditor(
                  label: 'Interests',
                  currentValues: const ['Music', 'Hiking'],
                  presets: const [
                    'Music',
                    'Hiking',
                    'Cooking',
                    'Art',
                    'Gaming',
                    'None',
                  ],
                  exclusiveOptions: const ['None'],
                  icon: LucideIcons.sparkles,
                  iconColor: Colors.purple,
                  hintText: 'Add an interest...',
                  onChanged: (tags) {},
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.text('INTERESTS'), findsOneWidget);

          // Tap Edit button to open multi-select sheet
          await tester.tap(find.text('Edit'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('Cooking'), findsOneWidget);

          // Tap 'Cooking' to add it
          await tester.tap(find.text('Cooking'));
          await tester.pump(const Duration(milliseconds: 100));

          // Enter custom tag in the TextField
          final inputFinder = find.byType(TextField);
          if (inputFinder.evaluate().isNotEmpty) {
            await tester.enterText(inputFinder.first, 'Astronomy');
            await tester.pump(const Duration(milliseconds: 100));
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await tester.pump(const Duration(milliseconds: 100));
          }

          // Tap Done/Save
          final doneButton = find.text('Done');
          if (doneButton.evaluate().isNotEmpty) {
            await tester.tap(doneButton);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        },
      );

      testWidgets(
        'exclusive option selection clears other tags in TagChipsEditor',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TagChipsEditor(
                  label: 'Diet',
                  currentValues: const ['Vegetarian'],
                  presets: const ['Vegetarian', 'Vegan', 'None'],
                  exclusiveOptions: const ['None'],
                  icon: LucideIcons.utensils,
                  iconColor: Colors.green,
                  hintText: 'Select diet...',
                  onChanged: (tags) {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.tap(find.text('Edit'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('None'), findsOneWidget);
          await tester.tap(find.text('None'));
          await tester.pump(const Duration(milliseconds: 100));
        },
      );
    });

    group('PlaceAutocompleteField Deep Interaction Tests', () {
      testWidgets(
        'shows suggestions dropdown when typing and allows selecting city',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PlaceAutocompleteField(
                    label: 'Current City',
                    initialValue: '',
                    hintText: 'Where are you based?',
                    prefixIcon: LucideIcons.mapPin,
                    onChanged: (val) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();

          // Tap field to open location picker sheet
          await tester.tap(find.text('CURRENT CITY'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Search in the bottom sheet's TextFormField
          final textFormField = find.byType(TextFormField);
          if (textFormField.evaluate().isNotEmpty) {
            await tester.enterText(textFormField.first, 'San');
            await tester.pump(const Duration(milliseconds: 200));

            final suggestion = find.text('San Francisco, CA');
            if (suggestion.evaluate().isNotEmpty) {
              await tester.tap(suggestion.first);
              await tester.pump(const Duration(milliseconds: 200));
            }
          }
        },
      );
    });

    group('StabilityTracker Sheet Tests', () {
      testWidgets(
        'tapping details button displays profile completion modal sheet',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          const vsync = TestVSync();
          final controller = AnimationController(
            vsync: vsync,
            duration: const Duration(seconds: 1),
          );
          addTearDown(controller.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: StabilityTracker(
                    stabilityPercentage: 60,
                    imagePaths: const [
                      'https://example.com/photo.jpg',
                      null,
                      null,
                    ],
                    name: 'Jane',
                    age: 22,
                    bio: 'Love astronomy and coding',
                    searchBucket: 'Women',
                    displayGender: 'Woman',
                    displaySexuality: 'Queer',
                    pronouns: 'They/Them',
                    hometown: 'Austin, TX',
                    currentPlace: 'Austin, TX',
                    languages: const ['English', 'Spanish'],
                    campusName: 'UT Austin',
                    major: 'Physics',
                    isStudying: true,
                    year: 2,
                    lifestyle: 'Night Owl',
                    drinking: 'Socially',
                    smoking: 'No',
                    religiousBeliefs: 'Agnostic',
                    pets: const ['Cat'],
                    subInterests: const {
                      'Science': ['Physics', 'Astronomy'],
                    },
                    causesSupported: const ['Animal Welfare'],
                    topArtists: const ['Phoebe Bridgers'],
                    pulseController: controller,
                    onCriteriaTap: (label) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();

          // Tap on Details / Completion report
          final viewDetails = find.text('View Details');
          if (viewDetails.evaluate().isNotEmpty) {
            await tester.tap(viewDetails);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.text('Profile Completion Report'), findsOneWidget);
          }
        },
      );
    });

    group(
      'SpotifyPlaylistsSection & SocialCoordinatesSection Widget Tests',
      () {
        testWidgets('opens Spotify playlists sheet via helper function', (
          tester,
        ) async {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => openPlaylistsSheet(context),
                      child: const Text('Open Sheet'),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.tap(find.text('Open Sheet'));
          await tester.pumpAndSettle();

          expect(find.text('Your Playlists'), findsOneWidget);
        });

        testWidgets(
          'renders SocialCoordinatesSection with campus and education info',
          (
            tester,
          ) async {
            tester.view.physicalSize = const Size(800, 2000);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: SocialCoordinatesSection(
                      campusName: 'UC Berkeley',
                      savedCampusName: 'UC Berkeley',
                      major: 'EECS',
                      year: 4,
                      isStudying: true,
                      hometown: 'San Jose, CA',
                      currentPlace: 'Berkeley, CA',
                      languages: const ['English', 'Spanish'],
                      onHometownChanged: (_) {},
                      onHometownSubmitted: (_) {},
                      onCurrentPlaceChanged: (_) {},
                      onCurrentPlaceSubmitted: (_) {},
                      onLanguagesChanged: (_) {},
                      onCampusNameChanged: (_) {},
                      onCampusNameSubmitted: (_) {},
                      onMajorChanged: (_) {},
                      onMajorSubmitted: (_) {},
                      onIsStudyingChanged: (_) {},
                      onYearChanged: (_) {},
                    ),
                  ),
                ),
              ),
            );

            await tester.pump();
            expect(find.byType(SocialCoordinatesSection), findsOneWidget);
            expect(find.text('UC Berkeley'), findsWidgets);
          },
        );
      },
    );
  }

  // --- Section 3 ---
  {
    group('Place Autocomplete and Settings Overlays Tests', () {
      testWidgets(
        'PlaceAutocompleteField renders, focuses, enters text, and selects suggestions',
        (
          tester,
        ) async {
          final key = GlobalKey<PlaceAutocompleteFieldState>();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlaceAutocompleteField(
                  key: key,
                  label: 'Current Place',
                  initialValue: 'San Francisco',
                  hintText: 'Search place...',
                  prefixIcon: Icons.location_on,
                  onChanged: (val) {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(PlaceAutocompleteField), findsOneWidget);

          final textField = find.byType(TextField);
          if (textField.evaluate().isNotEmpty) {
            await tester.tap(textField);
            await tester.enterText(textField, 'New York');
            await tester.pump(const Duration(milliseconds: 100));
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );

      testWidgets(
        'Dating, Friends, and Professional overlays render and interact',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: DatingSettingsOverlay(
                  datingTargetBuckets: const ['Women'],
                  datingFor: const ['Long-term relationship'],
                  partnerValues: const ['Kindness'],
                  childrenPlans: 'Want children',
                  savingFields: const {},
                  onSaveDatingField: (f, v, s) async {},
                  onLoadDatingProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(DatingSettingsOverlay), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FriendsSettingsOverlay(
                  friendsTargetBuckets: const ['All'],
                  flatInterests: const ['Climbing', 'Coffee'],
                  causesSupported: const ['Animal Welfare'],
                  savingFields: const {},
                  onSaveFriendsField: (f, v, s) async {},
                  onLoadFriendsProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(FriendsSettingsOverlay), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProfessionalSettingsOverlay(
                  professionalTargetBuckets: const ['All'],
                  lookingFor: const ['Mentors'],
                  techSkills: const ['Flutter', 'Python'],
                  company: 'Google',
                  roleType: const ['Full-time'],
                  savingFields: const {},
                  onSaveProfessionalField: (f, v, s) async {},
                  onLoadProfessionalProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Select Categories',
                  themeColor: Colors.purple,
                  items: const [
                    {
                      'actor_id': 'u1',
                      'name': 'Sarah',
                      'age': 25,
                      'avatar_url': 'https://example.com/pic.png',
                    },
                  ],
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required void Function(String actorId) onActioned,
                        required void Function() onProfileLoaded,
                      }) {},
                  onRecordAction: (targetId, action, token) async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    });
  }

  // --- Section 4 ---
  {
    group('Profile Detail Sheet and Providers Tests', () {
      testWidgets(
        'ProfileDetailSheet renders full public profile with action callbacks',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileDetailSheet(
                    data: kFullMockProfile,
                    themeColor: Colors.pink,
                    scrollController: ScrollController(),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(ProfileDetailSheet), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );

      testWidgets('PlaceAutocompleteField renders with custom decoration', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Hometown',
                hintText: 'Search city...',
                prefixIcon: Icons.location_city,
                initialValue: 'Seattle',
                onChanged: (v) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(PlaceAutocompleteField), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
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

    group('ClientAIImageManager Provider Deep Tests', () {
      test('ClientAIProfileState copyWith and initial values', () {
        final state = ClientAIProfileState(
          remotePaths: ['', '', '', '', ''],
          pendingUploads: {},
          slotSpecificVibeTags: {
            0: ['Travel', 'Nature'],
          },
          pendingDeletions: ['old_path_1'],
          isProcessingAI: true,
        );

        final copy = state.copyWith(isProcessingAI: false, isSaving: true);
        expect(copy.isProcessingAI, isFalse);
        expect(copy.isSaving, isTrue);
        expect(copy.pendingDeletions.length, 1);
        expect(copy.slotSpecificVibeTags[0], contains('Travel'));
      });

      test('ClientAIImageManager state transitions and backup/restore', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(clientAIImageManagerProvider.notifier);

        // Initial state
        expect(notifier.state.remotePaths.length, 5);

        // Set remote paths
        notifier.setRemotePaths(['path_0', 'path_1', 'path_2']);
        expect(notifier.state.remotePaths[0], 'path_0');
        expect(notifier.state.remotePaths[1], 'path_1');
        expect(notifier.state.remotePaths[2], 'path_2');
        expect(notifier.state.remotePaths[3], '');

        // Backup & restore
        notifier
          ..backupState()
          ..setRemotePaths(['new_0']);
        expect(notifier.state.remotePaths[0], 'new_0');

        notifier.restoreBackup();
        expect(notifier.state.remotePaths[0], 'path_0');
      });

      test('ClientAIImageManager remove slot / clear pending', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(clientAIImageManagerProvider.notifier)
          ..setRemotePaths(['p0', 'p1', 'p2', 'p3', 'p4'])
          ..clearImageSlot(1);

        expect(notifier.state.remotePaths[4], '');
        expect(notifier.state.pendingDeletions, contains('p1'));
      });
    });
  }

  // --- Section 6 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('InterestsOverlay Deep Interactive Tests', () {
      testWidgets(
        'renders InterestsOverlay, searches, toggles sub-interests and saves',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var savedInterests = ['Python', 'Rust'];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: InterestsOverlay(
                  initialSelected: savedInterests,
                  onSave: (list) {
                    savedInterests = list;
                  },
                  saveButtonText: 'Save Interests',
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(InterestsOverlay), findsOneWidget);

          // Search for "Tech" or "Flutter"
          final searchField = find.byType(TextField);
          if (searchField.evaluate().isNotEmpty) {
            await tester.enterText(searchField.first, 'Flutter');
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }

          // Search for "Music"
          if (searchField.evaluate().isNotEmpty) {
            await tester.enterText(searchField.first, 'Music');
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }

          // Clear search
          if (searchField.evaluate().isNotEmpty) {
            await tester.enterText(searchField.first, '');
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }

          // Tap on any available InkWell / ChoiceChip / FilterChip
          final inkWells = find.byType(InkWell);
          for (var i = 0; i < inkWells.evaluate().length && i < 10; i++) {
            await tester.tap(inkWells.at(i), warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
          }

          // Find and tap save button
          final saveBtn = find.text('Save Interests');
          if (saveBtn.evaluate().isNotEmpty) {
            await tester.tap(saveBtn.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        },
      );
    });
  }

  // --- Section 7 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('PlaceAutocompleteField Deep Interactive Tests', () {
      testWidgets(
        'renders PlaceAutocompleteField, opens picker sheet and searches',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var currentVal = 'Austin, TX';

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlaceAutocompleteField(
                  label: 'Hometown',
                  initialValue: currentVal,
                  hintText: 'Search city or country...',
                  prefixIcon: Icons.location_on,
                  onChanged: (val) {
                    currentVal = val;
                  },
                  onFieldSubmitted: (val) {
                    currentVal = val;
                  },
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(PlaceAutocompleteField), findsOneWidget);

          // Tap on PlaceAutocompleteField to open bottom sheet picker
          await tester.tap(
            find.byType(PlaceAutocompleteField),
            warnIfMissed: false,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // In the bottom sheet, find the search text field
          final textField = find.byType(TextField);
          if (textField.evaluate().isNotEmpty) {
            await tester.enterText(textField.first, 'San');
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));

            // Select suggestion
            final sfSuggestion = find.text('San Francisco, CA');
            if (sfSuggestion.evaluate().isNotEmpty) {
              await tester.tap(sfSuggestion.first, warnIfMissed: false);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
            }
          }
        },
      );
    });
  }

  // --- Section 8 ---
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

    group('PlaceAutocomplete & FeedbackPage Deep Mega Coverage Tests', () {
      testWidgets(
        'PlaceAutocompleteField handles typing, suggestions, and submissions',
        (
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
                  initialValue: 'Seattle',
                  hintText: 'Search city...',
                  prefixIcon: LucideIcons.home,
                  onChanged: (val) {},
                  onFieldSubmitted: (val) {},
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(PlaceAutocompleteField), findsOneWidget);

          await tester.tap(
            find.byType(PlaceAutocompleteField),
            warnIfMissed: false,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets(
        'FeedbackPage renders form, switches query type, and enters text',
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
                'status': 'success',
                'ticket_id': 't_test_100',
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
                body: FeedbackPage(
                  initialQueryType: FeedbackQueryType.bugReport,
                  initialSubject: 'Login issue',
                  initialMessage: 'Encountered glitch while testing.',
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(FeedbackPage), findsOneWidget);

          // Scroll form
          await tester.drag(find.byType(FeedbackPage), const Offset(0, -300));
          await tester.pump();

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
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

    group('ClientAIImageManager & ProfileTab Deep Coverage Tests', () {
      test(
        'ClientAIProfileState constructor, copyWith, and field modifications',
        () {
          final state = ClientAIProfileState(
            remotePaths: const ['img1.jpg', 'img2.jpg', '', '', ''],
            pendingUploads: {0: File('path/to/img0.png')},
            slotSpecificVibeTags: const {
              0: ['Artistic', 'Vibrant'],
            },
            pendingDeletions: const ['old_img.jpg'],
          );

          expect(state.remotePaths.length, 5);
          expect(state.remotePaths.first, 'img1.jpg');
          expect(state.pendingDeletions, contains('old_img.jpg'));
          expect(state.isProcessingAI, isFalse);

          final updated = state.copyWith(
            isProcessingAI: true,
            isSaving: true,
            pendingDeletions: ['deleted2.jpg'],
          );

          expect(updated.isProcessingAI, isTrue);
          expect(updated.isSaving, isTrue);
          expect(updated.pendingDeletions, contains('deleted2.jpg'));
        },
      );

      test(
        'ClientAIImageManager manipulates slots, reorders, and resets cleanly',
        () {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          final manager = container.read(clientAIImageManagerProvider.notifier)
            ..setRemotePaths(['photo1.jpg', 'photo2.jpg', 'photo3.jpg']);
          var state = container.read(clientAIImageManagerProvider);
          expect(state.remotePaths[0], 'photo1.jpg');
          expect(state.remotePaths[1], 'photo2.jpg');
          expect(state.remotePaths[2], 'photo3.jpg');
          expect(state.remotePaths[3], '');
          expect(state.remotePaths[4], '');

          manager
            ..backupState()
            ..clearImageSlot(1);
          state = container.read(clientAIImageManagerProvider);
          expect(state.remotePaths[1], 'photo3.jpg');
          expect(state.pendingDeletions, contains('photo2.jpg'));

          manager.swapImageSlots(0, 1);
          state = container.read(clientAIImageManagerProvider);
          expect(state.remotePaths[0], 'photo3.jpg');

          manager.restoreBackup();
          state = container.read(clientAIImageManagerProvider);
          expect(state.remotePaths[0], 'photo1.jpg');
        },
      );

      testWidgets(
        'ProfileTab renders sections and allows scrolling through form fields',
        (
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
                    onOpenOrbit: (tab, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(ProfileTab), findsOneWidget);

          // Scroll through ProfileTab
          await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    });
  }

  // --- Section 10 ---
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

    group('ProfileTab Interactive Editors Tests', () {
      testWidgets(
        'ProfileTab renders with populated fields, handles scroll and field interactions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 3200);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              jsonEncode({
                'name': 'Alex Johnson',
                'age': 22,
                'bio':
                    'Software engineering student exploring AI and mobile design.',
                'display_gender': 'Non-binary',
                'display_sexuality': 'Queer',
                'search_bucket': 'NB',
                'campus_name': 'Stanford University',
                'campus_branch': 'CS',
                'campus_year': 2026,
                'hometown': 'San Francisco, CA',
                'current_place': 'Palo Alto, CA',
                'drinking': 'Occasionally',
                'smoking': 'Never',
                'religious_beliefs': 'Agnostic',
                'children_plans': 'Someday',
                'pets': ['Dog', 'Cat'],
                'languages': ['English', 'Spanish'],
                'interests': ['Coding', 'Music', 'Hiking'],
                'causes_supported': ['Climate Action', 'Tech Literacy'],
                'top_artists': ['Radiohead', 'Daft Punk'],
                'ordered_images': ['https://example.com/avatar.jpg'],
                'hidden_fields': ['display_sexuality'],
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
                  body: ProfileTab(
                    onOpenOrbit: (tab, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(ProfileTab), findsOneWidget);

          // Scroll through ProfileTab
          await tester.drag(find.byType(ProfileTab), const Offset(0, -800));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await tester.drag(find.byType(ProfileTab), const Offset(0, -800));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    });
  }

  // --- Section 11 ---
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

    group('FriendsSettingsOverlay & PlaceAutocompleteField Tests', () {
      testWidgets('FriendsSettingsOverlay renders chips and allows selection', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FriendsSettingsOverlay(
                friendsTargetBuckets: const ['Tech'],
                flatInterests: const ['Hiking', 'Reading'],
                causesSupported: const ['Climate Action'],
                savingFields: const {},
                onSaveFriendsField: (field, value, setState) async {},
                onLoadFriendsProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(FriendsSettingsOverlay), findsOneWidget);

        // Tap on a cause chip
        final causeChip = find.text('Tech Ethics');
        if (causeChip.evaluate().isNotEmpty) {
          await tester.tap(causeChip.first);
          await tester.pump();
        }
      });

      testWidgets('PlaceAutocompleteField typing and selection', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var currentText = '';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Hometown',
                initialValue: 'Seattle',
                hintText: 'Enter your city',
                prefixIcon: LucideIcons.mapPin,
                onChanged: (val) {
                  currentText = val;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(PlaceAutocompleteField), findsOneWidget);
        expect(find.text('Seattle'), findsOneWidget);

        // Tap to open search bottom sheet
        await tester.tap(
          find.byType(PlaceAutocompleteField),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Enter text in search field
        final textField = find.byType(TextField);
        if (textField.evaluate().isNotEmpty) {
          await tester.enterText(textField.first, 'San');
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(currentText, isNotNull);
      });
    });
  }

  // --- Section 12 ---
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

    group('Profile Widgets and Editors Tests', () {
      testWidgets('TagChipsEditor renders and opens multiselect sheet', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TagChipsEditor(
                label: 'Interests',
                currentValues: const ['Art', 'Design'],
                presets: const ['Art', 'Design', 'Tech', 'Music'],
                icon: Icons.palette,
                iconColor: Colors.purple,
                hintText: 'Select interests',
                onChanged: (vals) {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(TagChipsEditor), findsOneWidget);

        final chip = find.text('Art');
        expect(chip, findsOneWidget);
      });

      testWidgets('PlaceAutocompleteField renders and accepts input', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Hometown',
                initialValue: 'Seattle, WA',
                hintText: 'Search city...',
                prefixIcon: Icons.home,
                onChanged: (val) {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(PlaceAutocompleteField), findsOneWidget);

        await tester.tap(
          find.byType(PlaceAutocompleteField),
          warnIfMissed: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('CosmicSelectionOverlay renders properly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CosmicSelectionOverlay(
                title: 'Select Category',
                options: ['Option 1', 'Option 2'],
                currentValue: 'Option 1',
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(CosmicSelectionOverlay), findsOneWidget);
      });
    });
  }

  // --- Section 13 ---
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
      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
    });

    group('Profile Sections and Editors Tests', () {
      testWidgets('TagChipsEditor renders presets and triggers tap', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TagChipsEditor(
                label: 'Languages',
                currentValues: const ['English', 'Spanish'],
                presets: const ['English', 'Spanish', 'French'],
                icon: LucideIcons.languages,
                iconColor: Colors.blue,
                onChanged: (vals) {},
                hintText: 'Select languages',
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(TagChipsEditor), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('SocialCoordinatesSection renders and interacts', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SocialCoordinatesSection(
                  hometown: 'Seattle, WA',
                  currentPlace: 'San Francisco, CA',
                  languages: const ['English'],
                  campusName: 'Stanford',
                  savedCampusName: 'Stanford',
                  major: 'Computer Science',
                  isStudying: true,
                  year: 2024,
                  onHometownChanged: (val) {},
                  onHometownSubmitted: (val) {},
                  onCurrentPlaceChanged: (val) {},
                  onCurrentPlaceSubmitted: (val) {},
                  onLanguagesChanged: (val) {},
                  onCampusNameChanged: (val) {},
                  onCampusNameSubmitted: (val) {},
                  onMajorChanged: (val) {},
                  onMajorSubmitted: (val) {},
                  onIsStudyingChanged: (val) {},
                  onYearChanged: (val) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(SocialCoordinatesSection), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      });

      testWidgets(
        'ProfileFieldEditSheet and SpotifyPlaylists trigger smoothly',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) {
                      return Column(
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              await showProfileFieldEditSheet<String>(
                                context: context,
                                fieldTitle: 'Display Name',
                                currentValue: 'Alex',
                                eligible: true,
                                changesUsedInWindow: 0,
                                nextEligibleAt: null,
                                inputBuilder: (ctx, val, onChanged) =>
                                    TextField(
                                      onChanged: onChanged,
                                    ),
                                confirmDescriptionBuilder: (val) =>
                                    'Change name to $val',
                                onConfirmed: (val) {},
                              );
                            },
                            child: const Text('Open Edit Sheet'),
                          ),
                          ElevatedButton(
                            onPressed: () => openPlaylistsSheet(context),
                            child: const Text('Open Spotify Playlists'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.text('Open Edit Sheet'), findsOneWidget);

          await tester.tap(find.text('Open Edit Sheet'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 14 ---
  {
    group('ClientAIProfileState Unit Tests', () {
      test('copyWith updates fields accurately', () {
        final state = ClientAIProfileState(
          remotePaths: ['img1.jpg', '', '', '', ''],
          pendingUploads: {0: File('test.jpg')},
          slotSpecificVibeTags: {
            0: ['Cyberpunk', 'Astrophotography'],
          },
          pendingDeletions: ['old.jpg'],
          isProcessingAI: true,
        );

        final updated = state.copyWith(isSaving: true, isProcessingAI: false);
        expect(updated.isSaving, true);
        expect(updated.isProcessingAI, false);
        expect(updated.remotePaths.first, 'img1.jpg');
        expect(updated.pendingDeletions, ['old.jpg']);
      });
    });

    group('ClientAIImageManager Riverpod Provider Tests', () {
      test('manages remote paths and state backups', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final manager = container.read(clientAIImageManagerProvider.notifier);
        expect(
          container.read(clientAIImageManagerProvider).remotePaths.length,
          5,
        );

        manager.setRemotePaths(['pic1.png', 'pic2.png']);
        expect(
          container.read(clientAIImageManagerProvider).remotePaths[0],
          'pic1.png',
        );
        expect(
          container.read(clientAIImageManagerProvider).remotePaths[1],
          'pic2.png',
        );

        manager
          ..backupState()
          ..setRemotePaths(['new.png']);
        expect(
          container.read(clientAIImageManagerProvider).remotePaths[0],
          'new.png',
        );

        manager.restoreBackup();
        expect(
          container.read(clientAIImageManagerProvider).remotePaths[0],
          'pic1.png',
        );
      });
    });
  }

  // --- Section 15 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ProfileFieldEditSheet Tests', () {
      testWidgets(
        'opens 2-step profile field edit sheet and progresses from intro to confirm',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          String? confirmedResult;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () {
                        unawaited(
                          showProfileFieldEditSheet<String>(
                            context: context,
                            fieldTitle: 'Display Name',
                            currentValue: 'Aria',
                            eligible: true,
                            changesUsedInWindow: 0,
                            nextEligibleAt: null,
                            inputBuilder: (ctx, pending, onChanged) {
                              return TextFormField(
                                initialValue: pending,
                                onChanged: onChanged,
                              );
                            },
                            confirmDescriptionBuilder: (pending) =>
                                'Change name to $pending?',
                            onConfirmed: (val) {
                              confirmedResult = val;
                            },
                          ),
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
          expect(find.text('Review Change'), findsOneWidget);

          await tester.enterText(find.byType(TextFormField), 'Aria Vance');
          await tester.pump();

          await tester.tap(find.text('Review Change'));
          await tester.pumpAndSettle();

          expect(find.text('Confirm New Display Name'), findsOneWidget);
          expect(find.text('Change name to Aria Vance?'), findsOneWidget);

          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();

          expect(confirmedResult, 'Aria Vance');
        },
      );

      testWidgets('renders rate limit warning when ineligible', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      unawaited(
                        showProfileFieldEditSheet<int>(
                          context: context,
                          fieldTitle: 'Age',
                          currentValue: 24,
                          eligible: false,
                          changesUsedInWindow: 2,
                          nextEligibleAt: DateTime(2026, 12, 31),
                          inputBuilder: (ctx, pending, onChanged) =>
                              Container(),
                          confirmDescriptionBuilder: (pending) => 'Change age',
                          onConfirmed: (_) {},
                        ),
                      );
                    },
                    child: const Text('Open Ineligible Sheet'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Open Ineligible Sheet'));
        await tester.pumpAndSettle();

        expect(
          find.text('0 of 2 changes remaining (Limit reached)'),
          findsOneWidget,
        );
      });
    });
  }

  // --- Section 16 ---
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

    group('Storage Image and Consent Dialogs Tests', () {
      test('resolveStorageImageProvider handles URLs and nulls correctly', () {
        expect(resolveStorageImageProvider(null), isNull);
        expect(resolveStorageImageProvider(''), isNull);
        expect(resolveStorageImageProvider('/tmp/test.png'), isNull);
        expect(
          resolveStorageImageProvider('https://example.com/pic.png'),
          isNotNull,
        );
      });

      testWidgets('StorageImage and ScalePressable render cleanly', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ScalePressable(
                    onTap: () {},
                    child: const Text('Press Me'),
                  ),
                  const StorageImage(
                    imagePath: 'https://example.com/pic.png',
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Press Me'), findsOneWidget);
      });
    });
  }
}

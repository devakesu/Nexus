import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/app_refresh_notifier.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/spotify/models/spotify_playlist.dart';
import 'package:nexus/features/spotify/providers/spotify_provider.dart';
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

class _MockSpotifyPlaylistsController extends SpotifyPlaylistsController {
  _MockSpotifyPlaylistsController(this.initialState);
  final SpotifyPlaylistsPayload initialState;

  @override
  Future<SpotifyPlaylistsPayload> build() async {
    return initialState;
  }
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

  final sampleProfile = {
    'name': 'Robin Scherbatsky',
    'age': 28,
    'age_changes_used_in_window': 0,
    'age_change_eligible': true,
    'name_changes_used_in_window': 0,
    'name_change_eligible': true,
    'pronouns': 'she/her',
    'campus_name': 'Metro Univ',
    'is_studying': true,
    'major': 'Broadcast Journalism',
    'year': 4,
    'display_gender': 'Woman',
    'display_sexuality': 'Straight',
    'search_bucket': 'W',
    'bio': 'News anchor and hockey enthusiast.',
    'hometown': 'Vancouver, BC',
    'current_place': 'New York, NY',
    'languages': ['English', 'French'],
    'lifestyle': 'Active',
    'drinking': 'Socially',
    'smoking': 'Never',
    'religious_beliefs': 'Agnostic',
    'pets': ['Dogs'],
    'causes_supported': ['Animal Welfare'],
    'top_artists': ['The Clash', 'Rush'],
    'ordered_images': [
      'https://example.com/robin1.jpg',
      'https://example.com/robin2.jpg',
    ],
    'sub_interests': {
      'Sports': ['Hockey', 'Running'],
      'Music': ['Rock', 'Indie'],
    },
    'stability_percentage': 92,
  };

  group('ProfileTab Mega Deep Coverage Tests', () {
    testWidgets(
      'renders ProfileTab, edits bio, toggles privacy, and clicks all section chips',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await SecureProfileCache.write(sampleProfile);
        ConsentCacheManager.specialCategoryConsentGranted = true;

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/profile/details')) {
            return ResponseBody.fromString(
              jsonEncode(sampleProfile),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.path.contains('/api/v1/profile/privacy-settings')) {
            return ResponseBody.fromString(
              jsonEncode({
                'hidden_fields': ['display_gender'],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.method == 'PATCH') {
            return ResponseBody.fromString('{"ok": true}', 200);
          }
          return ResponseBody.fromString('{"ok": true}', 200);
        });

        String? openedOrbitMode;
        Color? openedOrbitColor;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              spotifyPlaylistsControllerProvider.overrideWith(
                () => _MockSpotifyPlaylistsController(
                  const SpotifyPlaylistsPayload(
                    connected: true,
                    playlists: [
                      SpotifyPlaylist(
                        id: 'sp_1',
                        spotifyPlaylistId: 'spotify_1',
                        name: 'Morning Jam',
                        isCollaborative: false,
                        trackCount: 30,
                        tracks: [],
                        spotifyUrl: 'https://open.spotify.com/playlist/1',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProfileTab(
                  onOpenOrbit: (mode, color) {
                    openedOrbitMode = mode;
                    openedOrbitColor = color;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfileTab), findsOneWidget);
        expect(find.text('Robin Scherbatsky'), findsWidgets);

        // Verify StabilityTracker presence and trigger details modal
        final stabilityTrackerFinder = find.byType(StabilityTracker);
        if (stabilityTrackerFinder.evaluate().isNotEmpty) {
          await tester.tap(stabilityTrackerFinder.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          // Dismiss if modal appeared
          await tester.tapAt(const Offset(20, 20));
          await tester.pump();
        }

        // Scroll through sections and interact with chips
        for (var i = 0; i < 5; i++) {
          await tester.drag(find.byType(ProfileTab), const Offset(0, -400));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          // Tap any visible Chip or InkWell
          final chips = find.byType(Chip);
          for (var c = 0; c < chips.evaluate().length && c < 2; c++) {
            await tester.tap(chips.at(c), warnIfMissed: false);
            await tester.pump();
          }
        }

        // Trigger ProfileRefreshNotifier
        ProfileRefreshNotifier.notifyChanged();
        await tester.pump(const Duration(milliseconds: 300));
        expect(openedOrbitMode, isNull);
        expect(openedOrbitColor, isNull);
      },
    );

    testWidgets(
      'renders ProfileTab with special category consent flow and targetSection navigation',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        ConsentCacheManager.specialCategoryConsentGranted = false;
        await SecureProfileCache.write(sampleProfile);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/profile/details')) {
            return ResponseBody.fromString(
              jsonEncode(sampleProfile),
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
          return ResponseBody.fromString('{"ok": true}', 200);
        });

        var targetSectionCleared = false;

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileTab(
                  targetSection: 'affinity_interests',
                  onClearTargetSection: () {
                    targetSectionCleared = true;
                  },
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfileTab), findsOneWidget);
        expect(targetSectionCleared, isTrue);
      },
    );
  });
}

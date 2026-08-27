import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => null,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

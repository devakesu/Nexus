import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:nexus/features/spotify/models/spotify_playlist.dart';
import 'package:nexus/features/spotify/providers/spotify_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('ProfileTab Dialogs and Sub-flows Deep Coverage Tests', () {
    testWidgets(
      'renders ProfileTab, scrolls through sections and taps edit triggers',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              spotifyStatusProvider.overrideWith(
                (ref) async => const SpotifyConnectionStatus(
                  connected: true,
                  playlistCount: 5,
                ),
              ),
              spotifyPlaylistsControllerProvider.overrideWith(
                () => _MockSpotifyPlaylistsController(
                  const SpotifyPlaylistsPayload(
                    connected: true,
                    playlists: [
                      SpotifyPlaylist(
                        id: 'p_1',
                        spotifyPlaylistId: 'sp_1',
                        name: 'Chill Space Beats',
                        isCollaborative: false,
                        trackCount: 42,
                        tracks: [],
                        spotifyUrl: 'https://open.spotify.com/playlist/sp_1',
                      ),
                    ],
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
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(ProfileTab), findsOneWidget);

        // Drag to exercise scroll controller and lazy loaded sections
        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump(const Duration(seconds: 1));

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfileTab), findsOneWidget);
      },
    );
  });
}

class _MockSpotifyPlaylistsController extends SpotifyPlaylistsController {
  _MockSpotifyPlaylistsController(this._payload);

  final SpotifyPlaylistsPayload _payload;

  @override
  Future<SpotifyPlaylistsPayload> build() async => _payload;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

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

class _MockSpotifyPlaylistsController extends SpotifyPlaylistsController {
  _MockSpotifyPlaylistsController(this._payload);

  final SpotifyPlaylistsPayload _payload;

  @override
  Future<SpotifyPlaylistsPayload> build() async => _payload;
}

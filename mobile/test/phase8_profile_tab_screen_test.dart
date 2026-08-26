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

  group('ProfileTab Widget Tests', () {
    testWidgets('renders ProfileTab with controls and background', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spotifyStatusProvider.overrideWith(
              (ref) async => const SpotifyConnectionStatus(
                connected: true,
                playlistCount: 3,
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
    });
  });
}

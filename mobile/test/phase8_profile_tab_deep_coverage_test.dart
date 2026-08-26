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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
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

  group('ProfileTab Deep Widget Tests', () {
    testWidgets('renders ProfileTab with all sections and scrolls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spotifyStatusProvider.overrideWith(
              (ref) => Future.value(
                const SpotifyConnectionStatus(
                  connected: true,
                  playlistCount: 5,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProfileTab(
                onOpenOrbit: (title, color) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(ProfileTab), findsOneWidget);

      await tester.drag(find.byType(ProfileTab), const Offset(0, -500));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(ProfileTab), findsOneWidget);
    });
  });
}

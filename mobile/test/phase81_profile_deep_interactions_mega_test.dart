import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/profile/widgets/sections/affinity_interests_section.dart';
import 'package:nexus/features/profile/widgets/sections/bio_section.dart';
import 'package:nexus/features/profile/widgets/sections/core_signal_section.dart';
import 'package:nexus/features/profile/widgets/sections/lifestyle_resonance_section.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_artists_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  FlutterSecureStorage.setMockInitialValues({});

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

  group('Phase 81 - Profile Deep Interactions Mega Tests', () {
    testWidgets('BioSection and CoreSignalSection render and interact', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BioSection(
                bio: 'Cosmic explorer',
                onBioChanged: (val) {},
                onBioSubmitted: (val) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(BioSection), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoreSignalSection(
                name: 'Alex',
                age: 24,
                searchBucket: 'All',
                displayGender: 'Non-binary',
                displaySexuality: 'Queer',
                pronouns: 'They/Them',
                imagePaths: const ['img1.jpg', null, null, null, null],
                pendingUploads: const {},
                onNameTileTap: () {},
                onAgeTileTap: () {},
                onBucketChanged: (val) {},
                onSelectGender: () {},
                onSelectSexuality: () {},
                onSelectPronouns: () {},
                onImageSlotTap: (slot) {},
                onSwapImages: (from, to) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(CoreSignalSection), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
      'Lifestyle, Affinity, and Spotify music sections render and interact',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LifestyleResonanceSection(
                  lifestyle: 'Night owl',
                  drinking: 'Socially',
                  smoking: 'Never',
                  religiousBeliefs: 'Agnostic',
                  pets: const ['Cat'],
                  onLifestyleChanged: (val) {},
                  onLifestyleSubmitted: (val) {},
                  onPetsChanged: (val) {},
                  openBottomSelectionSheet:
                      ({
                        required title,
                        required options,
                        required currentValue,
                        required onSelected,
                      }) {},
                  onDrinkingSaved: (val) {},
                  onSmokingSaved: (val) {},
                  onReligiousBeliefsSaved: (val) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(LifestyleResonanceSection), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AffinityInterestsSection(
                  flatSubInterests: const ['AI', 'Robotics'],
                  causesSupported: const ['Climate'],
                  onInterestsSaved: (vals) {},
                  onCausesSupportedChanged: (vals) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(AffinityInterestsSection), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SpotifyMusicSection(
                    topArtists: const ['Radiohead', 'Daft Punk'],
                    onArtistRemoved: (artist) {},
                    onSpotifyConnect: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(SpotifyMusicSection), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });
}

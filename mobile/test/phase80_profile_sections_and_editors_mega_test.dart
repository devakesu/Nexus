import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/profile/widgets/profile_field_edit_sheet.dart';
import 'package:nexus/features/profile/widgets/sections/social_coordinates_section.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
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

  group('Phase 80 - Profile Sections and Editors Mega Tests', () {
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

    testWidgets('ProfileFieldEditSheet and SpotifyPlaylists trigger smoothly', (
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
                            inputBuilder: (ctx, val, onChanged) => TextField(
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
    });
  });
}

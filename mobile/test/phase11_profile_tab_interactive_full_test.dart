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
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
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
    'name': 'Alex Rivera',
    'age': 24,
    'age_changes_used_in_window': 0,
    'age_change_eligible': true,
    'name_changes_used_in_window': 0,
    'name_change_eligible': true,
    'campus_year': 4,
    'campus_branch': 'Astrophysics',
    'campus_name': 'Stanford University',
    'display_gender': 'Non-binary',
    'display_sexuality': 'Pansexual',
    'pronouns': 'They/Them',
    'bio': 'Exploring cosmic wonders and stargazing adventures 🌌',
    'hometown': 'San Francisco, CA',
    'current_place': 'Palo Alto, CA',
    'religious_beliefs': 'Spiritual',
    'children_plans': 'Not sure yet',
    'lifestyle': 'Night Owl',
    'drinking': 'Socially',
    'smoking': 'Never',
    'search_bucket': 'NB',
    'causes_supported': ['Climate Action', 'Space Exploration', 'Education'],
    'top_artists': ['Radiohead', 'Daft Punk', 'AURORA'],
    'languages': ['English', 'Spanish', 'French'],
    'pets': ['Dog', 'Cat'],
    'image_paths': [
      'https://example.com/p1.jpg',
      'https://example.com/p2.jpg',
      'https://example.com/p3.jpg',
      null,
      null,
      null,
    ],
    'sub_interests': {
      'Science': ['Astrophysics', 'Quantum Computing'],
      'Music': ['Indie Rock', 'Electronic'],
      'Arts': ['Photography'],
    },
    'prompt_answers': {
      'The cosmic secret to my heart': 'Fresh coffee under a starry sky.',
      'A non-negotiable for me': 'Kindness to all living beings.',
    },
  };

  group('ProfileTab Interactive Full Coverage Tests', () {
    testWidgets(
      'renders loaded ProfileTab with all sections and scrolls through content',
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
              spotifyStatusProvider.overrideWith(
                (ref) async => const SpotifyConnectionStatus(
                  connected: true,
                  playlistCount: 2,
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
        expect(find.text('Alex Rivera'), findsWidgets);

        // Scroll down to reveal all sections
        final scrollable = find.byType(Scrollable).first;
        await tester.drag(scrollable, const Offset(0, -800));
        await tester.pump(const Duration(milliseconds: 300));

        await tester.drag(scrollable, const Offset(0, -800));
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  });
}

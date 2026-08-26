import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
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
        const MethodChannel('nexus/security'),
        (call) async => false,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('DiscoveryHubState Tests', () {
    test(
      'DiscoveryHubState fromCache, toCache, and copyWith work accurately',
      () {
        final cacheData = {
          'profileDetails': {'name': 'Alice', 'age': 24},
          'likes': [
            {'id': 'like_1', 'user_id': 'u1'},
          ],
          'unseenCount': 3,
          'matches': [
            {'id': 'match_1', 'user_id': 'u2'},
          ],
        };

        final state = DiscoveryHubState.fromCache(cacheData);
        expect(state.profileDetails?['name'], 'Alice');
        expect(state.likes.length, 1);
        expect(state.unseenCount, 3);
        expect(state.matches.length, 1);
        expect(state.isRevalidating, isFalse);

        final exported = state.toCache();
        expect(exported['unseenCount'], 3);

        final updated = state.copyWith(isRevalidating: true);
        expect(updated.isRevalidating, isTrue);
        expect(updated.profileDetails?['name'], 'Alice');
      },
    );
  });

  group('ProfileDetailSheet Tests', () {
    testWidgets('renders ProfileDetailSheet with profile data and action bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testProfileData = {
        'name': 'Elena Rostova',
        'age': 23,
        'bio': 'Astrophysics enthusiast & cosmic coffee lover.',
        'ordered_images': [
          'https://test.supabase.co/storage/v1/object/public/avatars/elena.jpg',
        ],
        'affinity_score': 88,
        'interests': ['Quantum Physics', 'Python'],
        'viewer_spotify_connected': true,
      };

      final scrollController = ScrollController();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileDetailSheet(
                data: testProfileData,
                themeColor: AppColors.modeDating,
                scrollController: scrollController,
                actionBar: const Text('Custom Action Bar'),
                onUnmatchTap: (ctx) async {},
                onHideTap: (ctx) async {},
                onBlockTap: (ctx) async {},
                onReportTap: (ctx) async {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Elena Rostova, 23'), findsOneWidget);
      expect(find.text('Custom Action Bar'), findsOneWidget);
    });
  });
}

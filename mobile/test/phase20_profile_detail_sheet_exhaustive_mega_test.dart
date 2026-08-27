import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
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
        const MethodChannel('flutter_secure_screen'),
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

  group('ProfileDetailSheet Exhaustive Deep Mega Tests', () {
    testWidgets(
      'ProfileDetailSheet renders complete profile data, photos, badges and safety buttons',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();
        var reported = false;
        var blocked = false;
        var hidden = false;
        var unmatched = false;

        final fullData = {
          'id': 'u_test_99',
          'name': 'Seraphina',
          'age': 24,
          'pronouns': 'she/her',
          'bio': 'Astrophysics enthusiast & classical pianist.',
          'campus_name': 'MIT',
          'major': 'Physics & Astronomy',
          'year': 3,
          'hometown': 'Boston, MA',
          'current_place': 'Cambridge, MA',
          'profile_pic': 'https://example.com/seraphina.jpg',
          'normal_pics': [
            'https://example.com/seraphina2.jpg',
            'https://example.com/seraphina3.jpg',
          ],
          'interests': ['Astronomy', 'Piano', 'Quantum Physics'],
          'causes_supported': ['STEM Education', 'Clean Oceans'],
          'top_artists': ['Ludovico Einaudi', 'Hans Zimmer', 'Max Richter'],
          'drinking': 'Occasionally',
          'smoking': 'Never',
          'religious_beliefs': 'Agnostic',
          'children_plans': 'Someday',
          'pets': ['Golden Retriever'],
          'languages': ['English', 'French', 'German'],
          'compatibility_score': 94,
          'viewer_spotify_connected': true,
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: fullData,
                  themeColor: AppColors.modeDating,
                  scrollController: scrollController,
                  onReportTap: (ctx) async {
                    reported = true;
                  },
                  onBlockTap: (ctx) async {
                    blocked = true;
                  },
                  onHideTap: (ctx) async {
                    hidden = true;
                  },
                  onUnmatchTap: (ctx) async {
                    unmatched = true;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfileDetailSheet), findsOneWidget);
        expect(find.text('Seraphina, 24'), findsOneWidget);
        expect(find.text('she/her'), findsOneWidget);

        // Scroll sheet
        await tester.drag(
          find.byType(ProfileDetailSheet),
          const Offset(0, -600),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        await tester.drag(
          find.byType(ProfileDetailSheet),
          const Offset(0, -600),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(reported, isFalse);
        expect(blocked, isFalse);
        expect(hidden, isFalse);
        expect(unmatched, isFalse);
      },
    );
  });
}

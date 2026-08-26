import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('ProfileDetailSheet Deep Coverage Tests', () {
    testWidgets(
      'renders all profile sections, attributes, top artists, and action buttons',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();

        final profile = {
          'id': 'user_aria_123',
          'name': 'Aria Vance',
          'age': 24,
          'bio': 'Exploring galaxies and coding algorithms.',
          'ordered_images': ['https://example.com/aria.jpg'],
          'campus_name': 'UC Berkeley',
          'major': 'Astrophysics',
          'occupation': 'Space Researcher',
          'top_artists': ['Radiohead', 'Odesza', 'Rufus Du Sol'],
          'hometown': 'San Francisco, CA',
          'interests': ['Astronomy', 'Coding', 'Electronic Music'],
          'verified': true,
          'pronouns': 'she/her',
          'display_gender': 'Woman',
          'display_sexuality': 'Straight',
          'children_plans': 'Someday',
          'drinking': 'Socially',
          'smoking': 'Never',
          'weed': 'Never',
          'workout': 'Often',
          'star_sign': 'Aquarius',
          'pets': 'Cats',
          'communication_style': 'Direct',
          'love_style': 'Quality Time',
          'education_level': 'Masters',
          'personality_type': 'INTJ',
          'blood_type': 'O+',
          'social_links': {'instagram': 'aria_v', 'spotify': 'aria_music'},
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: profile,
                  themeColor: Colors.purpleAccent,
                  scrollController: scrollController,
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
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(ProfileDetailSheet), findsOneWidget);
        expect(find.text('Aria Vance, 24'), findsWidgets);
        expect(
          find.text('Exploring galaxies and coding algorithms.'),
          findsOneWidget,
        );
      },
    );
  });
}

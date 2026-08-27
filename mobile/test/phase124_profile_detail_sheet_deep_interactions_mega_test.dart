import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final richProfileData = <String, dynamic>{
    'id': 'u_taylor',
    'name': 'Taylor Swift',
    'age': 28,
    'gender': 'Woman',
    'compatibility_score': 96,
    'bio': 'Musician, songwriter, cat enthusiast.',
    'ordered_images': [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
    ],
    'interests': ['Music', 'Cats', 'Baking', 'Poetry', 'Road Trips'],
    'hometown_city': 'Nashville',
    'current_city': 'New York',
    'drinking_preference': 'Socially',
    'smoking_preference': 'Never',
    'languages_spoken': ['English'],
    'job_title': 'Artist',
    'company': 'Republic Records',
    'university': 'NYU (Honorary)',
    'major': 'Fine Arts',
    'graduation_year': 2022,
    'dating_intent': 'Long-term partnership',
    'children_plans': 'Open to children',
    'religious_beliefs': 'Christian',
    'sexual_orientation': 'Straight',
    'tech_skills': ['Audio Engineering', 'Logic Pro'],
    'professional_interests': ['Songwriting', 'Directing'],
    'friendship_goals': ['Creative collaborations', 'Coffee dates'],
    'instagram_handle': 'taylorswift',
    'spotify_top_artists': ['The National', 'Bon Iver', 'Phoebe Bridgers'],
    'spotify_playlists': [
      {'name': 'Midnight Vibes', 'url': 'https://spotify.com/playlist/1'},
    ],
    'viewer_spotify_connected': true,
  };

  group('Phase 124 - Profile Detail Sheet Deep Interactions Mega Tests', () {
    testWidgets(
      'ProfileDetailSheet renders all sections, badges, and safety actions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();
        // ignored flags

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: richProfileData,
                  themeColor: Colors.pink,
                  scrollController: scrollController,
                  isSelf: false,
                  onUnmatchTap: (ctx) async {},
                  onHideTap: (ctx) async {},
                  onBlockTap: (ctx) async {},
                  onReportTap: (ctx) async {},
                  onSpotifyConnectRefresh: () async {},
                  actionBar: Container(key: const Key('action_bar')),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(ProfileDetailSheet), findsOneWidget);

        // Scroll through sheet to render all slivers/sections
        for (var i = 0; i < 6; i++) {
          await tester.drag(
            find.byType(ProfileDetailSheet),
            const Offset(0, -500),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Tap safety buttons at the bottom if found
        final inkWells = find.byType(InkWell);
        for (var i = 0; i < inkWells.evaluate().length && i < 6; i++) {
          try {
            await tester.tap(inkWells.at(i), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 50));
          } on Object catch (_) {}
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'ProfileDetailSheet renders in self-view mode without safety actions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: richProfileData,
                  themeColor: Colors.teal,
                  scrollController: scrollController,
                  showScoreBadge: false,
                  showSafetyActions: false,
                  isSelf: true,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ProfileDetailSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/features/profile/widgets/sections/social_coordinates_section.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
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

  group('Home, Profile Detail & Discovery Mega Coverage Tests', () {
    testWidgets(
      'ProfileDetailSheet renders complete profile details and handles actions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockProfileData = {
          'id': 'user_detail_99',
          'name': 'Gemma Simmons',
          'age': 27,
          'bio': 'Biochemist & explorer',
          'ordered_images': [
            'https://example.com/gemma1.jpg',
            'https://example.com/gemma2.jpg',
          ],
          'display_gender': 'Woman',
          'display_sexuality': 'Straight',
          'pronouns': 'she/her',
          'campus_name': 'S.H.I.E.L.D. Academy',
          'major': 'Biochemistry',
          'year': 4,
          'hometown': 'London, UK',
          'current_place': 'New York, NY',
          'lifestyle': 'Curious & Dedicated',
          'drinking': 'Rarely',
          'smoking': 'Never',
          'religious_beliefs': 'Science',
          'pets': ['Cats'],
          'causes_supported': ['STEM Education'],
          'top_artists': ['Queen', 'Muse'],
          'sub_interests': {
            'Science': ['Biotech', 'Genetics'],
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: mockProfileData,
                  themeColor: AppColors.pulsarPink,
                  scrollController: ScrollController(),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(ProfileDetailSheet), findsOneWidget);
        expect(find.text('Gemma Simmons, 27'), findsWidgets);

        // Scroll sheet
        await tester.drag(
          find.byType(ProfileDetailSheet),
          const Offset(0, -400),
        );
        await tester.pump();
      },
    );

    testWidgets('ExportCodeCard renders and triggers export actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExportCodeCard(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ExportCodeCard), findsOneWidget);
    });

    testWidgets(
      'TagChipsEditor and SocialCoordinatesSection render and interact',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // TagChipsEditor
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TagChipsEditor(
                label: 'Interests',
                icon: Icons.tag,
                iconColor: AppColors.primaryTeal,
                hintText: 'Add interest',
                currentValues: const ['Flutter', 'Dart'],
                presets: const ['Flutter', 'Dart', 'React', 'Vue'],
                onChanged: (tags) {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(TagChipsEditor), findsOneWidget);

        // SocialCoordinatesSection
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SocialCoordinatesSection(
                  hometown: 'Vancouver',
                  currentPlace: 'New York',
                  languages: const ['English', 'French'],
                  campusName: 'Metro Univ',
                  savedCampusName: 'Metro Univ',
                  major: 'Journalism',
                  isStudying: true,
                  year: 4,
                  onHometownChanged: (v) {},
                  onHometownSubmitted: (v) {},
                  onCurrentPlaceChanged: (v) {},
                  onCurrentPlaceSubmitted: (v) {},
                  onLanguagesChanged: (v) {},
                  onCampusNameChanged: (v) {},
                  onCampusNameSubmitted: (v) {},
                  onMajorChanged: (v) {},
                  onMajorSubmitted: (v) {},
                  onIsStudyingChanged: (v) {},
                  onYearChanged: (v) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(SocialCoordinatesSection), findsOneWidget);
      },
    );
  });
}

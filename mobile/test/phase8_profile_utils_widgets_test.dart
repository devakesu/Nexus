import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/features/profile/utils/emoji_helper.dart';
import 'package:nexus/features/profile/utils/name_moderation.dart';
import 'package:nexus/features/profile/widgets/glass_text_field.dart';
import 'package:nexus/features/profile/widgets/profile_visibility_badge.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('NameModeration Unit Tests', () {
    test(
      'validateDisplayNameClientSide handles digits, titles, and banned substrings',
      () {
        // Numbers
        final numRes = validateDisplayNameClientSide('Alex99');
        expect(numRes.isValid, isFalse);
        expect(numRes.error, contains("can't contain numbers"));

        // Titles
        final drRes = validateDisplayNameClientSide('Dr. Sarah');
        expect(drRes.isValid, isFalse);
        expect(drRes.error, contains('Titles like "Dr."'));

        final profRes = validateDisplayNameClientSide('Professor Xavier');
        expect(profRes.isValid, isFalse);

        // Banned words
        final badRes = validateDisplayNameClientSide('BadWord_hitler_User');
        expect(badRes.isValid, isFalse);
        expect(badRes.error, contains("That name isn't allowed"));

        // Valid names
        final valid1 = validateDisplayNameClientSide('Sarah Connor');
        expect(valid1.isValid, isTrue);
        expect(valid1.error, isNull);

        final valid2 = validateDisplayNameClientSide('Elena Rostova');
        expect(valid2.isValid, isTrue);
      },
    );
  });

  group('Emoji & Tag Icon Helper Tests', () {
    test('getTagIcon and getEmojiForTag map known tags to widgets/strings', () {
      expect(getEmojiForTag('Man'), '👨');
      expect(getTagIcon('Man'), isNotNull);

      expect(getEmojiForTag('Woman'), '👩');
      expect(getTagIcon('Woman'), isNotNull);

      expect(getEmojiForTag('she/her'), '♀️');
      expect(getTagIcon('she/her'), isNotNull);

      expect(getEmojiForTag('CompletelyUnknownTagXYZ'), isEmpty);
      expect(getTagIcon('CompletelyUnknownTagXYZ'), isNull);
    });
  });

  group('ProfileVisibilityBadge Tests', () {
    testWidgets('renders convenience constructors for ProfileVisibilityBadge', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ProfileVisibilityBadge.datingAndFriends(),
                ProfileVisibilityBadge.datingOnly(),
                ProfileVisibilityBadge.allTabs(),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Dating & Friends'), findsOneWidget);
      expect(find.text('Dating only'), findsOneWidget);
      expect(find.text('All tabs'), findsOneWidget);
    });
  });

  group('GlassTextField Widget Tests', () {
    testWidgets(
      'renders GlassTextField with prefix icon and handles text changes',
      (tester) async {
        String? updatedValue;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GlassTextField(
                label: 'Bio',
                initialValue: 'Exploring space and technology',
                hintText: 'Tell us about yourself...',
                prefixIcon: LucideIcons.pencil,
                onChanged: (val) => updatedValue = val,
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Bio'), findsOneWidget);
        expect(find.text('Exploring space and technology'), findsOneWidget);
        expect(find.byIcon(LucideIcons.pencil), findsOneWidget);

        await tester.enterText(
          find.byType(TextFormField),
          'Updated bio content',
        );
        await tester.pump();

        expect(updatedValue, 'Updated bio content');
      },
    );
  });

  group('StabilityTracker Widget Tests', () {
    testWidgets('renders StabilityTracker with score and criteria items', (
      tester,
    ) async {
      final pulseController = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StabilityTracker(
                stabilityPercentage: 85,
                imagePaths: const ['https://example.com/pic.jpg', null],
                name: 'Elena',
                age: 27,
                bio: 'Robotics engineer',
                searchBucket: 'F',
                displayGender: 'Woman',
                displaySexuality: 'Straight',
                pronouns: 'she/her',
                hometown: 'Seattle',
                currentPlace: 'San Francisco',
                languages: const ['English', 'Spanish'],
                campusName: 'Stanford University',
                major: 'Computer Science',
                isStudying: false,
                year: 2020,
                lifestyle: 'Early Bird',
                drinking: 'Socially',
                smoking: 'Never',
                religiousBeliefs: 'Agnostic',
                pets: const ['Dog'],
                subInterests: const {
                  'Tech': ['Robotics', 'Flutter'],
                },
                causesSupported: const ['Climate Action'],
                topArtists: const ['Daft Punk'],
                pulseController: pulseController,
                onCriteriaTap: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(StabilityTracker), findsOneWidget);
      expect(find.text('STABILITY INDEX: 85/100'), findsOneWidget);
      expect(find.text('PROFILE COMPLETE'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/friends_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_activation_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
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

  group('ModeActivationOverlay Tests', () {
    testWidgets(
      'renders ModeActivationOverlay and executes onFinished after animation',
      (tester) async {
        var finished = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeActivationOverlay(
                modeTitle: 'Dating Mode',
                subtitle: 'Calibrating romance orbit...',
                icon: LucideIcons.heart,
                brandColor: AppColors.modeDating,
                onFinished: () => finished = true,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2600));

        expect(finished, isTrue);
      },
    );
  });

  group('ModeCategorySelectionSheet Tests', () {
    testWidgets(
      'renders ModeCategorySelectionSheet with items and empty state',
      (tester) async {
        final sampleItems = [
          {'id': 'item_1', 'name': 'Maya Lin', 'profile_pic': null},
          {'id': 'item_2', 'name': 'Lucas Vance', 'profile_pic': null},
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeCategorySelectionSheet(
                title: 'Likes Sent',
                themeColor: AppColors.modeDating,
                items: sampleItems,
                emptyMessage: 'No likes sent yet',
                onFetchItems: () async {},
                onOpenItemDetailsDialog:
                    ({
                      required ctx,
                      required actorId,
                      required name,
                      required onActioned,
                      required onProfileLoaded,
                    }) {},
                onRecordAction: (targetId, action, token) async {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Likes Sent'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('Maya Lin'), findsOneWidget);
        expect(find.text('Lucas Vance'), findsOneWidget);
      },
    );
  });

  group('DatingSettingsOverlay Tests', () {
    testWidgets(
      'renders DatingSettingsOverlay and handles bucket toggles and partner values',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['M', 'F'],
                datingFor: const ['Long-term relationship'],
                partnerValues: const ['Empathy', 'Ambition'],
                childrenPlans: 'Want children',
                savingFields: const {},
                onSaveDatingField: (field, val, setter) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(DatingSettingsOverlay), findsOneWidget);
        expect(find.text('Dating Settings'), findsOneWidget);
      },
    );
  });

  group('FriendsSettingsOverlay Tests', () {
    testWidgets('renders FriendsSettingsOverlay and handles causes selection', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendsSettingsOverlay(
              friendsTargetBuckets: const ['M', 'F', 'NB'],
              flatInterests: const ['Hiking', 'Gaming'],
              causesSupported: const ['Climate Action', 'Mental Health'],
              savingFields: const {},
              onSaveFriendsField: (field, val, setter) async {},
              onLoadFriendsProfileStatusSilent: () async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(FriendsSettingsOverlay), findsOneWidget);
      expect(find.text('Friends Settings'), findsOneWidget);
    });
  });

  group('ProfessionalSettingsOverlay Tests', () {
    testWidgets(
      'renders ProfessionalSettingsOverlay and handles role & skills selections',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfessionalSettingsOverlay(
                professionalTargetBuckets: const ['M', 'F'],
                lookingFor: const ['Co-founder matching', 'Hiring talent'],
                techSkills: const ['Flutter & Dart', 'Python & Django/FastAPI'],
                company: 'Nexus Tech',
                roleType: const ['Engineer'],
                savingFields: const {},
                onSaveProfessionalField: (field, val, setter) async {},
                onLoadProfessionalProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
        expect(find.text('Professional Settings'), findsOneWidget);
      },
    );
  });
}

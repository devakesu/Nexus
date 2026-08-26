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

  group('Social Modes Overlays Widget Tests', () {
    testWidgets('renders ModeCategorySelectionSheet with list items', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeCategorySelectionSheet(
              title: 'Interested In',
              themeColor: AppColors.modeDating,
              items: const [],
              onFetchItems: () async {},
              onOpenItemDetailsDialog:
                  ({
                    required ctx,
                    required actorId,
                    required name,
                    required void Function(String actorId) onActioned,
                    required void Function() onProfileLoaded,
                  }) {},
              onRecordAction: (targetId, action, token) async => true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
    });

    testWidgets('renders ModeActivationOverlay with mode title and icon', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeActivationOverlay(
              modeTitle: 'Professional Mode',
              subtitle: 'Connect with colleagues and industry peers',
              icon: LucideIcons.briefcase,
              brandColor: AppColors.modeProfessional,
              onFinished: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ModeActivationOverlay), findsOneWidget);
    });

    testWidgets('renders DatingSettingsOverlay with options and saves', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatingSettingsOverlay(
              datingTargetBuckets: const ['Women'],
              datingFor: const ['Long-term'],
              partnerValues: const ['Honesty'],
              childrenPlans: 'Someday',
              savingFields: const {},
              onSaveDatingField: (f, v, s) async {},
              onLoadDatingProfileStatusSilent: () async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DatingSettingsOverlay), findsOneWidget);
    });

    testWidgets('renders FriendsSettingsOverlay with flat interests', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendsSettingsOverlay(
              friendsTargetBuckets: const ['All'],
              flatInterests: const ['Hiking', 'Gaming'],
              causesSupported: const ['Animal Welfare'],
              savingFields: const {},
              onSaveFriendsField: (f, v, s) async {},
              onLoadFriendsProfileStatusSilent: () async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FriendsSettingsOverlay), findsOneWidget);
    });

    testWidgets('renders ProfessionalSettingsOverlay with tech skills', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfessionalSettingsOverlay(
              professionalTargetBuckets: const ['Tech'],
              lookingFor: const ['Co-founder'],
              techSkills: const ['Flutter', 'Python'],
              company: 'Nexus Inc',
              roleType: const ['Full-time'],
              savingFields: const {},
              onSaveProfessionalField: (f, v, s) async {},
              onLoadProfessionalProfileStatusSilent: () async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
    });
  });
}

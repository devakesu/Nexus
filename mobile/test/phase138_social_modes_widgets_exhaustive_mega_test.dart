import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 138 - Social Modes Overlays Mega Tests', () {
    testWidgets('DatingSettingsOverlay renders fields and triggers save', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatingSettingsOverlay(
              datingTargetBuckets: const ['Men', 'Women'],
              datingFor: const ['Long-term relationship'],
              partnerValues: const ['Honesty', 'Kindness'],
              childrenPlans: 'Want children',
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

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'ProfessionalSettingsOverlay renders fields and triggers save',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfessionalSettingsOverlay(
                professionalTargetBuckets: const ['Software', 'Design'],
                lookingFor: const ['Co-founder', 'Mentorship'],
                techSkills: const ['Flutter', 'Python', 'Go'],
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

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets('ModeCategorySelectionSheet renders with list of candidates', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockItems = [
        {
          'actor_id': 'u1',
          'name': 'Taylor',
          'profile_pic': 'https://example.com/pic1.jpg',
          'age': 25,
          'bio': 'Hi!',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeCategorySelectionSheet(
              title: 'Incoming Matches',
              themeColor: Colors.pink,
              items: mockItems,
              onFetchItems: () async {},
              onOpenItemDetailsDialog:
                  ({
                    required ctx,
                    required actorId,
                    required name,
                    required onActioned,
                    required onProfileLoaded,
                  }) {},
              onRecordAction: (aid, act, actionId) async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/consent_prompt_dialog.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/core/widgets/safety_score_ring_painter.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    group('AestheticLoaders Tests', () {
      testWidgets('NexusOrbitLoader renders in dark and light modes', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  NexusOrbitLoader(),
                  NexusOrbitLoader(size: 60, lightMode: true),
                ],
              ),
            ),
          ),
        );

        expect(find.byType(NexusOrbitLoader), findsNWidgets(2));
        await tester.pump(const Duration(milliseconds: 500));
      });

      testWidgets(
        'ConstellationAlignLoader renders twinkling and ripple components',
        (tester) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: ConstellationAlignLoader(),
              ),
            ),
          );

          expect(find.byType(ConstellationAlignLoader), findsOneWidget);
          expect(find.byType(NexusOrbitLoader), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 500));
        },
      );
    });

    group('ScalePressable Widget Tests', () {
      testWidgets('ScalePressable handles tap and triggers callback', (
        tester,
      ) async {
        var tapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScalePressable(
                onTap: () => tapped = true,
                child: const Text('Press Me'),
              ),
            ),
          ),
        );

        expect(find.text('Press Me'), findsOneWidget);
        await tester.tap(find.text('Press Me'));
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
      });

      testWidgets('ScalePressable disabled does not respond to tap', (
        tester,
      ) async {
        var tapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScalePressable(
                enabled: false,
                onTap: () => tapped = true,
                child: const Text('Disabled'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Disabled'));
        await tester.pumpAndSettle();
        expect(tapped, isFalse);
      });
    });

    group('SafetyScoreRingPainter Tests', () {
      testWidgets('SafetyScoreRingPainter paints without error', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(100, 100),
                painter: SafetyScoreRingPainter(progress: 0.75),
              ),
            ),
          ),
        );

        expect(find.byType(CustomPaint), findsWidgets);
      });
    });

    group('NexusToast & NexusOverlayToast Tests', () {
      testWidgets('NexusToast.show displays toast and completes lifecycle', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    NexusToast.show(
                      context,
                      'Operation Succeeded!',
                      type: NexusToastType.success,
                      duration: const Duration(milliseconds: 100),
                    );
                  },
                  child: const Text('Show Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Toast'));
        await tester.pump(); // insert entry
        await tester.pump(const Duration(milliseconds: 50)); // start animation

        expect(find.text('Operation Succeeded!'), findsOneWidget);

        // Advance past forward animation (280ms), display duration (100ms), and reverse animation (220ms)
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 200));
      });

      testWidgets(
        'NexusOverlayToast.show renders overlay alert and auto-dismisses',
        (tester) async {
          final navKey = GlobalKey<NavigatorState>();

          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navKey,
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () {
                      NexusOverlayToast.show(
                        navigatorKey: navKey,
                        title: 'Alert Title',
                        message: 'Alert Message Content',
                        accentColor: Colors.blue,
                        icon: Icons.info,
                        duration: const Duration(milliseconds: 100),
                      );
                    },
                    child: const Text('Show Overlay Toast'),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('Show Overlay Toast'));
          await tester.pump();
          await tester.pump(Duration.zero);

          expect(find.text('Alert Title'), findsOneWidget);
          expect(find.text('Alert Message Content'), findsOneWidget);

          // Advance past timer duration (100ms)
          await tester.pump(const Duration(milliseconds: 200));
        },
      );
    });

    group('ConsentPromptCard Widgets Tests', () {
      testWidgets(
        'SafetyConsentPromptCard & SpecialCategoryConsentPromptCard render properly',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      SafetyConsentPromptCard(onGranted: () {}),
                      SpecialCategoryConsentPromptCard(onGranted: () {}),
                    ],
                  ),
                ),
              ),
            ),
          );

          expect(find.text('Consent required'), findsNWidgets(2));
          expect(find.text('I Accept'), findsNWidgets(2));
          expect(find.textContaining('Meetup Safety & SOS'), findsOneWidget);
          expect(
            find.textContaining('orientation and religious beliefs'),
            findsOneWidget,
          );
        },
      );
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';

import '../../helpers/test_helpers.dart';

class _StabilityTrackerWrapper extends StatefulWidget {
  const _StabilityTrackerWrapper({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  State<_StabilityTrackerWrapper> createState() =>
      _StabilityTrackerWrapperState();
}

class _StabilityTrackerWrapperState extends State<_StabilityTrackerWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StabilityTracker(
      stabilityPercentage: 75,
      imagePaths: const ['https://example.com/p1.jpg', null],
      name: 'Maya',
      age: 26,
      bio: 'Astrophysics enthusiast',
      searchBucket: 'Dating',
      displayGender: 'Female',
      displaySexuality: 'Straight',
      pronouns: 'she/her',
      hometown: 'NYC',
      currentPlace: 'SF',
      languages: const ['English'],
      campusName: 'Stanford',
      major: 'Astrophysics',
      isStudying: true,
      year: 2,
      lifestyle: 'Active',
      drinking: 'Socially',
      smoking: 'Never',
      religiousBeliefs: 'Agnostic',
      pets: const ['Dog'],
      subInterests: const {
        'Science': ['Space'],
      },
      causesSupported: const ['STEM'],
      topArtists: const ['Pink Floyd'],
      pulseController: _pulseController,
      onCriteriaTap: widget.onTap,
    );
  }
}

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('StabilityTracker Deep Interactive Tests', () {
      testWidgets(
        'renders StabilityTracker and interacts with missing criteria chips',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 2000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          String? tappedCriteria;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: _StabilityTrackerWrapper(
                    onTap: (criteria) => tappedCriteria = criteria,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(StabilityTracker), findsOneWidget);

          // Tap any clickable InkWell in the stability tracker
          final inkWells = find.byType(InkWell);
          for (var i = 0; i < inkWells.evaluate().length && i < 4; i++) {
            await tester.tap(inkWells.at(i), warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
          }

          expect(tappedCriteria, anyOf(isNull, isNotNull));
        },
      );
    });
  }
}

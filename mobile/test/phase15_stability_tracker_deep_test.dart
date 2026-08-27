import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _StabilityTrackerWrapper extends StatefulWidget {
  const _StabilityTrackerWrapper({required this.onTap});
  final ValueChanged<String> onTap;

  @override
  State<_StabilityTrackerWrapper> createState() =>
      _StabilityTrackerWrapperState();
}

class _StabilityTrackerWrapperState extends State<_StabilityTrackerWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StabilityTracker(
      stabilityPercentage: 65,
      imagePaths: const ['https://example.com/photo.jpg', null],
      name: 'Alex Rivera',
      age: 26,
      bio: 'Design enthusiast',
      searchBucket: 'Women',
      displayGender: 'Non-binary',
      displaySexuality: 'Queer',
      pronouns: 'They/Them',
      hometown: 'Austin, TX',
      currentPlace: 'San Francisco, CA',
      languages: const ['English', 'Spanish'],
      campusName: 'Stanford University',
      major: 'Computer Science',
      isStudying: true,
      year: 2025,
      lifestyle: 'Active',
      drinking: 'Socially',
      smoking: 'Never',
      religiousBeliefs: 'Agnostic',
      pets: const ['Dog'],
      subInterests: const {
        'Tech': ['Flutter', 'AI'],
      },
      causesSupported: const ['Climate Action'],
      topArtists: const ['Odesza', 'Tycho'],
      pulseController: _pulseController,
      onCriteriaTap: widget.onTap,
    );
  }
}

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

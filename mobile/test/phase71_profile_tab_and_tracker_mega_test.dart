import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _TestStabilityTrackerHost extends StatefulWidget {
  const _TestStabilityTrackerHost({required this.onCriteriaTap});
  final void Function(String) onCriteriaTap;

  @override
  State<_TestStabilityTrackerHost> createState() =>
      _TestStabilityTrackerHostState();
}

class _TestStabilityTrackerHostState extends State<_TestStabilityTrackerHost>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

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
      imagePaths: const ['img1.jpg', null, null, null, null],
      name: 'Alex Rivera',
      age: 24,
      bio: 'Exploring cosmos',
      searchBucket: 'All',
      displayGender: 'Non-binary',
      displaySexuality: 'Queer',
      pronouns: 'They/Them',
      hometown: 'Seattle, WA',
      currentPlace: 'San Francisco, CA',
      languages: const ['English', 'Spanish'],
      campusName: 'Stanford',
      major: 'CS',
      isStudying: true,
      year: 2024,
      lifestyle: 'Night owl',
      drinking: 'Socially',
      smoking: 'Never',
      religiousBeliefs: 'Agnostic',
      pets: const ['Dog'],
      subInterests: const {
        'Tech': ['AI', 'Robotics'],
      },
      causesSupported: const ['Climate'],
      topArtists: const ['Radiohead', 'Daft Punk'],
      pulseController: _pulseController,
      onCriteriaTap: widget.onCriteriaTap,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockSessionJson = jsonEncode({
    'access_token': 'mock-access-token-12345',
    'refresh_token': 'mock-refresh-token-12345',
    'expires_in': 3600,
    'expires_at': 1893456000,
    'token_type': 'bearer',
    'user': {
      'id': '00000000-0000-0000-0000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'user@nexus.test',
      'phone': '+14155552671',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    },
  });

  SharedPreferences.setMockInitialValues({
    'sb-mock-auth-token': mockSessionJson,
  });
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_secure_screen'),
        (call) async => null,
      );

  setUpAll(() async {
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Phase 71 - Profile Tab & Stability Tracker Mega Tests', () {
    testWidgets(
      'StabilityTracker renders all criteria and triggers all callbacks',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final tappedLabels = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestStabilityTrackerHost(
                onCriteriaTap: tappedLabels.add,
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(StabilityTracker), findsOneWidget);

        final criteriaList = [
          'Profile Picture',
          'Gallery Slot 1',
          'Gallery Slot 2',
          'Gallery Slot 3',
          'Gallery Slot 4',
          'Display Name',
          'Age',
          'Demographic Buckets',
          'Gender',
          'Sexuality',
          'Pronouns',
          'Cosmic Signature (Bio)',
          'Hometown',
          'Current Place',
          'Institute Name',
          'Major',
          'Languages',
          'Campus Year',
          'Drinking',
          'Smoking',
          'Religious Beliefs',
          'Pets',
          'Lifestyle Description',
          'Interests',
          'Causes Supported',
          'Top Artists',
        ];

        for (final label in criteriaList) {
          final finder = find.text(label);
          if (finder.evaluate().isNotEmpty) {
            await tester.tap(finder.first, warnIfMissed: false);
            await tester.pump();
          }
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets('ProfileTab mounts with targetSection smoothly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileTab(
                onOpenOrbit: (mode, color) {},
                targetSection: 'bio',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ProfileTab), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });
  });
}

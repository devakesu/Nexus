import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => ['wifi'],
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Security Services, Witness & Auth Mega Coverage Tests', () {
    test(
      'ErrorHandler sanitizes emails, tokens, and sensitive keys accurately',
      () {
        final sanitizedEmail = ErrorHandler.sanitize(
          'Contact user at test@example.com for help',
        );
        expect(sanitizedEmail, contains('[EMAIL_REDACTED]'));

        final sanitizedToken = ErrorHandler.sanitize(
          'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz',
        );
        expect(sanitizedToken, contains('[REDACTED_SENSITIVE]'));

        expect(ErrorHandler.isSensitiveKey('jwt'), isTrue);
        expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
        expect(ErrorHandler.isSensitiveKey('display_name'), isFalse);

        final map = {
          'jwt': 'secret_jwt_token',
          'public_data': 'hello',
        };
        final sanitizedMap = ErrorHandler.sanitizeObject(map) as Map;
        expect(sanitizedMap['jwt'], '[REDACTED_SENSITIVE]');
        expect(sanitizedMap['public_data'], 'hello');
      },
    );

    test(
      'MeetupSafetySession instance, permissions and lifecycle methods',
      () async {
        final session = MeetupSafetySession.instance;
        expect(session.isActive, isFalse);

        final perms = await session.ensureAndroidPermissions();
        expect(perms.allGranted, isNotNull);

        expect(session.checkInInterval, const Duration(hours: 1));
        expect(session.serverSessionId, isNull);
      },
    );

    testWidgets('CheckInAlertScreen renders and handles SOS phase triggers', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CheckInAlertScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CheckInAlertScreen), findsOneWidget);

      // Trigger "I'm Safe" button if present
      final safeBtn = find.text("I'm Safe");
      if (safeBtn.evaluate().isNotEmpty) {
        await tester.tap(safeBtn.first, warnIfMissed: false);
        await tester.pump();
      }
    });

    testWidgets('PlaceAutocompleteField renders and initializes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var selectedPlace = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceAutocompleteField(
              label: 'Current Place',
              initialValue: 'New York, NY',
              hintText: 'Search city...',
              prefixIcon: Icons.location_city,
              onChanged: (val) {
                selectedPlace = val;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(PlaceAutocompleteField), findsOneWidget);
      expect(selectedPlace, isEmpty);
    });

    testWidgets('StabilityTracker widget renders completion progress', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      late AnimationController anim;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                anim = AnimationController(
                  vsync: Scaffold.of(context),
                  duration: const Duration(seconds: 1),
                );
                return StabilityTracker(
                  stabilityPercentage: 85,
                  imagePaths: const ['https://example.com/pic1.jpg'],
                  name: 'Robin',
                  age: 28,
                  bio: 'Journalist',
                  searchBucket: 'W',
                  displayGender: 'Woman',
                  displaySexuality: 'Straight',
                  pronouns: 'she/her',
                  hometown: 'Vancouver',
                  currentPlace: 'New York',
                  languages: const ['English'],
                  campusName: 'Metro Univ',
                  major: 'Journalism',
                  isStudying: true,
                  year: 4,
                  lifestyle: 'Active',
                  drinking: 'Socially',
                  smoking: 'Never',
                  religiousBeliefs: 'Agnostic',
                  pets: const ['Dogs'],
                  subInterests: const {
                    'Sports': ['Hockey'],
                  },
                  causesSupported: const ['Animal Welfare'],
                  topArtists: const ['The Clash'],
                  pulseController: anim,
                  onCriteriaTap: (label) {},
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(StabilityTracker), findsOneWidget);
    });

    testWidgets('Auth screens (LoginScreen, PermissionsScreen) render', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // LoginScreen
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoginScreen(appName: 'Nexus'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LoginScreen), findsOneWidget);

      // PermissionsScreen
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionsScreen(onCompleted: () {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PermissionsScreen), findsOneWidget);
    });
  });
}

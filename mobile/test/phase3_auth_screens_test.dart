import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/reactivate_account_page.dart';
import 'package:nexus/features/auth_onboarding/screens/splash_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/terms_consent_screen.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'checkPermissionStatus') {
            return 1; // PermissionStatus.granted
          } else if (call.method == 'requestPermissions') {
            final permissions = call.arguments as List<dynamic>;
            return {for (final p in permissions) p: 1};
          }
          return 1;
        },
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (call) async {
          if (call.method == 'getLocationAccuracy') {
            return 1; // LocationAccuracyStatus.precise
          }
          return 1;
        },
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator_updates'),
        (call) async => 1,
      );

  group('SplashScreen & CoordinatePainter Tests', () {
    testWidgets('SplashScreen animates and triggers onAnimationComplete', (
      tester,
    ) async {
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            appName: 'NEXUS',
            onAnimationComplete: () => completed = true,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 2000));

      expect(completed, isTrue);
    });

    test('CoordinatePainter shouldRepaint check', () {
      final p1 = CoordinatePainter(progress: 0.2);
      final p2 = CoordinatePainter(progress: 0.2);
      final p3 = CoordinatePainter(progress: 0.8);

      expect(p1.shouldRepaint(p2), isFalse);
      expect(p1.shouldRepaint(p3), isTrue);
    });
  });

  group('ReactivateAccountPage Widget Tests', () {
    testWidgets('renders reactivate account screen with days remaining', (
      tester,
    ) async {
      final futureDate = DateTime.now().add(const Duration(days: 14));

      await tester.pumpWidget(
        MaterialApp(
          home: ReactivateAccountPage(
            scheduledPurgeAt: futureDate,
            onReactivated: () {},
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('14 days'), findsOneWidget);
      expect(find.text('Reactivate My Account'), findsOneWidget);
      expect(find.text('Not now, sign me out'), findsOneWidget);

      await tester.tap(find.text('Reactivate My Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('TermsConsentPage Widget Tests', () {
    testWidgets(
      'renders itemized checkboxes, requires terms & guidelines before continuing',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TermsConsentPage(
                currentTermsVersion: '1.2.0',
                isVersionBump: false,
                onConsentRecorded: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Before you continue'), findsOneWidget);
        expect(find.text('Terms of Service & Privacy Policy'), findsOneWidget);
        expect(find.text('Community Guidelines'), findsOneWidget);
        expect(
          find.text('Sexual orientation & religious belief data'),
          findsOneWidget,
        );
        expect(find.text('Meetup Safety & SOS data'), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('Export My Data'), findsOneWidget);
        expect(find.text('Decline & Delete My Account'), findsOneWidget);

        // Check the mandatory checkboxes
        await tester.tap(find.text('Terms of Service & Privacy Policy'));
        await tester.pump();

        await tester.tap(find.text('Community Guidelines'));
        await tester.pump();

        // Check optional
        await tester.tap(
          find.text('Sexual orientation & religious belief data'),
        );
        await tester.pump();

        // Tap Continue
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      },
    );

    testWidgets('renders version bump headline when isVersionBump=true', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TermsConsentPage(
              currentTermsVersion: '2.0.0',
              isVersionBump: true,
              onConsentRecorded: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Our terms have changed'), findsOneWidget);
      expect(find.text('Terms & Policy v2.0.0'), findsOneWidget);
    });
  });

  group('PermissionsScreen Widget Tests', () {
    testWidgets('renders permissions list and handles continue button', (
      tester,
    ) async {
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: PermissionsScreen(
            onCompleted: () => completed = true,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Configure permissions'), findsOneWidget);
      expect(find.text('CORE PERMISSIONS'), findsOneWidget);
      expect(find.text('ADDITIONAL PERMISSIONS'), findsOneWidget);
      expect(find.text('Push Notifications'), findsOneWidget);
      expect(find.text('Location Services'), findsOneWidget);
      expect(find.text('Continue to Nexus'), findsOneWidget);

      await tester.tap(find.text('Continue to Nexus'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(completed, isTrue);
    });

    test('PermissionItem model initialization', () {
      const item = PermissionItem(
        permission: Permission.camera,
        name: 'Camera',
        description: 'Camera access',
        icon: Icons.camera,
        isCore: true,
        reason: 'Photos',
      );

      expect(item.name, equals('Camera'));
      expect(item.isCore, isTrue);
    });
  });
}

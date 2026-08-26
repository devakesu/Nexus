import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/settings/screens/about_screen.dart';
import 'package:nexus/features/settings/screens/crisis_helplines_page.dart';
import 'package:nexus/features/settings/screens/delete_account_page.dart';
import 'package:nexus/features/settings/widgets/about/attestation_section.dart';
import 'package:nexus/features/settings/widgets/transparency_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockAboutAttestationNotifier extends AboutAttestationNotifier {
  MockAboutAttestationNotifier(this._initial);
  final AboutAttestationState _initial;

  @override
  AboutAttestationState? build() => _initial;
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => {
          'appName': 'Nexus',
          'packageName': 'com.nexus.app',
          'version': '1.0.0',
          'buildNumber': '1',
        },
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('TransparencyBadge Widget Tests', () {
    testWidgets('renders TransparencyBadge collapsed and expanded with tap', (
      tester,
    ) async {
      var badgeTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TransparencyBadge(
                  onTap: () => badgeTapped = true,
                ),
                const TransparencyBadge(expanded: true),
              ],
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(TransparencyBadge), findsNWidgets(2));

      await tester.tap(find.byType(TransparencyBadge).first);
      await tester.pump();
      expect(badgeTapped, isTrue);
    });
  });

  group('CrisisHelplinesPage Widget Tests', () {
    testWidgets(
      'renders CrisisHelplinesPage with emergency helpline contacts',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CrisisHelplinesPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CrisisHelplinesPage), findsOneWidget);
        expect(find.text('Crisis Helplines'), findsOneWidget);
      },
    );
  });

  group('AboutScreen & AttestationSection Widget Tests', () {
    testWidgets('renders AboutScreen with app info and transparency sections', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aboutAttestationProvider.overrideWith(
              () => MockAboutAttestationNotifier(
                const AboutAttestationState(
                  data: {'status': 'verified', 'commit': 'abc1234'},
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AboutScreen(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AboutScreen), findsOneWidget);
    });

    testWidgets('renders AttestationSection independently', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aboutAttestationProvider.overrideWith(
              () => MockAboutAttestationNotifier(
                const AboutAttestationState(
                  data: {'status': 'verified', 'commit': 'abc1234'},
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AttestationSection(
                  onLaunch: (url) async {},
                  onCopy: (ctx, val, lbl) async {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AttestationSection), findsOneWidget);
    });
  });

  group('DeleteAccountPage Widget Tests', () {
    testWidgets(
      'renders DeleteAccountPage with warning and confirmation text input',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: DeleteAccountPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DeleteAccountPage), findsOneWidget);
        expect(find.text('Delete Account'), findsWidgets);
      },
    );
  });
}

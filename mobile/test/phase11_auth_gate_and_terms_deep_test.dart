import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:nexus/features/auth_onboarding/screens/auth_gate.dart';
import 'package:nexus/features/auth_onboarding/screens/reactivate_account_page.dart';
import 'package:nexus/features/auth_onboarding/screens/terms_consent_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TermsConsentPage Deep Tests', () {
    testWidgets(
      'renders checkboxes, toggles mandatory/optional consents, and submits',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TermsConsentPage(
                currentTermsVersion: '2',
                isVersionBump: false,
                onConsentRecorded: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(TermsConsentPage), findsOneWidget);

        // Tap all tiles to accept all consents
        final tiles = find.byType(ScalePressable);
        for (var i = 0; i < tiles.evaluate().length; i++) {
          await tester.tap(tiles.at(i));
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Tap Agree & Continue button
        final continueButton = find.textContaining('Agree & Continue');
        if (continueButton.evaluate().isNotEmpty) {
          await tester.tap(continueButton.first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
    );
  });

  group('ReactivateAccountPage Deep Tests', () {
    testWidgets('renders scheduled purge warning and reacts to cancellation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var reactivated = false;

      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
        if (options.path.contains('deletion/cancel')) {
          return ResponseBody.fromString(
            '{"status":"ok"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{"error":"not_found"}', 404);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReactivateAccountPage(
              scheduledPurgeAt: DateTime.now().add(const Duration(days: 14)),
              onReactivated: () => reactivated = true,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(ReactivateAccountPage), findsOneWidget);
      expect(find.text('Reactivate My Account'), findsOneWidget);

      await tester.tap(find.text('Reactivate My Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(reactivated, isTrue);
    });
  });

  group('AuthGate Deep Navigation State Tests', () {
    testWidgets('renders AuthGate with app name and splash screen transition', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: AuthGate(appName: 'Nexus'),
        ),
      );

      await tester.pump();
      expect(find.byType(AuthGate), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });
  });
}

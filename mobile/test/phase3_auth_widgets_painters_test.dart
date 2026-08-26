import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/auth_onboarding/widgets/import_code_dialog.dart';
import 'package:nexus/features/auth_onboarding/widgets/login_painters.dart';
import 'package:nexus/features/auth_onboarding/widgets/nexus_onboarding_fields.dart';
import 'package:nexus/features/auth_onboarding/widgets/otp_verification_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('SpaceNode & Login Painters Tests', () {
    test('SpaceNode initialization and fields', () {
      final node = SpaceNode(
        position: const Offset(0.5, -0.5),
        velocity: const Offset(0.01, -0.01),
        score: 0.95,
        label: 'Cosmic Node',
        type: 0,
        targetRadius: 100,
      );

      expect(node.position, equals(const Offset(0.5, -0.5)));
      expect(node.velocity, equals(const Offset(0.01, -0.01)));
      expect(node.score, equals(0.95));
      expect(node.label, equals('Cosmic Node'));
      expect(node.type, equals(0));
      expect(node.targetRadius, equals(100.0));
    });

    testWidgets(
      'GravityFieldPainter & ChromaticBorderPainter paint correctly',
      (tester) async {
        final nodes = [
          SpaceNode(
            position: const Offset(0.2, 0.3),
            velocity: Offset.zero,
            score: 0.88,
            label: 'Dating Node',
            type: 0,
            targetRadius: 50,
          ),
          SpaceNode(
            position: const Offset(-0.4, -0.2),
            velocity: Offset.zero,
            score: 0.76,
            label: 'Friends Node',
            type: 1,
            targetRadius: 70,
          ),
          SpaceNode(
            position: const Offset(0.1, -0.5),
            velocity: Offset.zero,
            score: 0.92,
            label: 'Pro Node',
            type: 2,
            targetRadius: 90,
          ),
        ];

        final painter1 = GravityFieldPainter(
          nodes: nodes,
          touchPosition: const Offset(0.1, 0.1),
          tiltOffset: const Offset(0.05, 0.05),
          simulatedTime: 1.5,
          matrixIndex: 0,
        );

        final painter2 = GravityFieldPainter(
          nodes: nodes,
          touchPosition: const Offset(0.1, 0.1),
          tiltOffset: const Offset(0.05, 0.05),
          simulatedTime: 1.5,
          matrixIndex: 0,
        );

        expect(painter1.shouldRepaint(painter2), isFalse);

        final chromatic = ChromaticBorderPainter(borderRadius: 16);
        expect(chromatic.shouldRepaint(chromatic), isFalse);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Stack(
                  children: [
                    CustomPaint(
                      size: const Size(400, 400),
                      painter: painter1,
                    ),
                    CustomPaint(
                      size: const Size(400, 400),
                      painter: chromatic,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(CustomPaint), findsWidgets);
      },
    );
  });

  group('NexusOnboardingFields & NexusMECOnboardingFields Tests', () {
    testWidgets('Selects demographic bucket options and fires callback', (
      tester,
    ) async {
      String? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexusOnboardingFields(
              onChanged: ({required demographicBucket}) {
                selected = demographicBucket;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('DEMOGRAPHIC BUCKET'), findsOneWidget);
      expect(find.text('Men'), findsOneWidget);
      expect(find.text('Women'), findsOneWidget);
      expect(find.text('Non-Binary'), findsOneWidget);

      await tester.tap(find.text('Women'));
      await tester.pump();
      expect(selected, equals('F'));

      await tester.tap(find.text('Men'));
      await tester.pump();
      expect(selected, equals('M'));

      await tester.tap(find.text('Non-Binary'));
      await tester.pump();
      expect(selected, equals('NB'));

      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('NexusMECOnboardingFields renders properly', (tester) async {
      String? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NexusMECOnboardingFields(
              onChanged: ({required demographicBucket}) {
                selected = demographicBucket;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('DEMOGRAPHIC BUCKET'), findsOneWidget);
      await tester.tap(find.text('Men'));
      await tester.pump();
      expect(selected, equals('M'));

      await tester.pump(const Duration(milliseconds: 350));
    });
  });

  group('OtpVerificationDialog Widget Tests', () {
    testWidgets('renders OTP dialog with 6-digit textfield and handles input', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  unawaited(
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => OtpVerificationDialog(
                        phone: '+15551234567',
                        onVerificationSuccess: () {},
                      ),
                    ),
                  );
                },
                child: const Text('Open OTP Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open OTP Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Verify Phone Number'), findsOneWidget);
      expect(find.text('Sent to +15551234567'), findsOneWidget);
      expect(find.text('ENTER OTP CODE'), findsOneWidget);

      // Enter incomplete OTP
      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();

      // Enter full 6-digit OTP
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();

      expect(find.text('Verify'), findsOneWidget);

      // Close dialog via close button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    });
  });

  group('ImportCodeDialog Widget Tests', () {
    testWidgets(
      'renders import code dialog with input and handles text capitalization',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => ImportCodeDialog(
                          onImportSuccess: () {},
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Import Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Import Dialog'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('Import Profile Data'), findsOneWidget);
        expect(find.text('EXPORT CODE'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'ABC123');
        await tester.pump();

        expect(find.text('Import Now'), findsOneWidget);

        // Close dialog
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      },
    );
  });
}

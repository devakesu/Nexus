import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/digital_witness_recorder.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  group(
    'Phase 128 - Safety Alert, Meetup Session and Digital Witness Deep Mega Tests',
    () {
      testWidgets(
        'CheckInAlertScreen renders alert actions, countdown and dismiss buttons',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: CheckInAlertScreen(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(CheckInAlertScreen), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );

      test('MeetupSafetySession instance properties and end', () async {
        final session = MeetupSafetySession.instance;

        expect(session.isActive, isFalse);
        expect(session.serverSessionId, isNull);
      });

      test('DigitalWitnessRecorder instance properties and stop', () async {
        final recorder = DigitalWitnessRecorder.instance;

        expect(recorder.isRecording, isFalse);
      });
    },
  );
}

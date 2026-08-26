import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/security_signal/services/safety_contacts.dart';
import 'package:nexus/features/security_signal/services/safety_dialer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SafetyContact & Storage Tests', () {
    test('SafetyContact JSON serialization and round-trip', () async {
      final contact = SafetyContact(name: 'Jane Doe', phone: '+1234567890');
      expect(contact.name, equals('Jane Doe'));
      expect(contact.phone, equals('+1234567890'));

      final json = contact.toJson();
      final fromJson = SafetyContact.fromJson(json);
      expect(fromJson.name, equals('Jane Doe'));
      expect(fromJson.phone, equals('+1234567890'));
    });

    test(
      'loadSafetyContacts, saveSafetyContacts, and clearSafetyContacts',
      () async {
        expect(await loadSafetyContacts(), isEmpty);

        final list = [
          SafetyContact(name: 'Mom', phone: '+1112223333'),
          SafetyContact(name: 'Dad', phone: '+4445556666'),
        ];
        await saveSafetyContacts(list);

        final loaded = await loadSafetyContacts();
        expect(loaded.length, equals(2));
        expect(loaded.first.name, equals('Mom'));

        await clearSafetyContacts();
        expect(await loadSafetyContacts(), isEmpty);
      },
    );
  });

  group('SafetyAlertApi Models & Methods Tests', () {
    test('SafetyAlertResult & SafetyContactsSyncResult models', () {
      const alertResult = SafetyAlertResult(
        alertId: 'alt_123',
        contactsNotified: 2,
        contactsTotal: 3,
      );
      expect(alertResult.alertId, equals('alt_123'));
      expect(alertResult.contactsNotified, equals(2));
      expect(alertResult.contactsTotal, equals(3));

      const syncResult = SafetyContactsSyncResult(
        success: true,
        blocked: ['Blocked Contact'],
      );
      expect(syncResult.success, isTrue);
      expect(syncResult.blocked, contains('Blocked Contact'));
    });
  });

  group('MeetupSafetySession & Permissions Models Tests', () {
    test('MeetupSafetyPermissionStatus permissions state checks', () {
      const allGranted = MeetupSafetyPermissionStatus.allGranted();
      expect(allGranted.allGranted, isTrue);
      expect(allGranted.notificationsGranted, isTrue);
      expect(allGranted.exactAlarmsGranted, isTrue);
      expect(allGranted.fullScreenIntentGranted, isTrue);

      const partial = MeetupSafetyPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: false,
        fullScreenIntentGranted: true,
      );
      expect(partial.allGranted, isFalse);
    });

    test('MeetupSafetyNotificationActions action string constants', () {
      expect(MeetupSafetyNotificationActions.sos, equals('meetup_safety_sos'));
      expect(
        MeetupSafetyNotificationActions.call112,
        equals('meetup_safety_call_112'),
      );
      expect(
        MeetupSafetyNotificationActions.imSafe,
        equals('meetup_safety_im_safe'),
      );
    });
  });

  group('Safety UI & Dialog Helpers Tests', () {
    testWidgets('showSosFallbackDialog renders confirmation and buttons', (
      tester,
    ) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  unawaited(
                    showSosFallbackDialog(
                      context,
                      contacts: [
                        SafetyContact(name: 'Alice', phone: '+1234567890'),
                      ],
                      onRetryRecording: () => retried = true,
                    ),
                  );
                },
                child: const Text('Show Fallback Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Fallback Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Emergency Triggered'), findsOneWidget);
      expect(find.textContaining('Emergency SOS activated!'), findsOneWidget);
      expect(find.text('Retry Recording'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      await tester.tap(find.text('Retry Recording'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(retried, isTrue);
    });

    testWidgets('showInformContactsToast shows message and completes timer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showInformContactsToast(
                    context,
                    [SafetyContact(name: 'Bob', phone: '+9876543210')],
                  );
                },
                child: const Text('Show Inform Toast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Inform Toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Alert sent to Bob'), findsOneWidget);
      // Wait for forward animation (280ms) + display duration (3000ms) + reverse animation (220ms)
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('callEmergencyNumber handles execution gracefully', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => callEmergencyNumber(context, '112'),
                child: const Text('Call 112'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call 112'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}

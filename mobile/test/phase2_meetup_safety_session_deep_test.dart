import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('MeetupSafetySession Unit Tests', () {
    test('singleton instance initializes with default idle state', () {
      final session = MeetupSafetySession.instance;
      expect(session, isNotNull);
      expect(session.isActive, false);
      expect(session.serverSessionId, isNull);
      expect(session.nextCheckInAt, isNull);
      expect(session.hasSyncWarning, false);
    });

    test('MeetupSafetyPermissionStatus properties', () {
      const status = MeetupSafetyPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: true,
        fullScreenIntentGranted: true,
      );

      expect(status.notificationsGranted, true);
      expect(status.exactAlarmsGranted, true);
      expect(status.fullScreenIntentGranted, true);
      expect(status.allGranted, true);

      const statusPartial = MeetupSafetyPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: false,
        fullScreenIntentGranted: true,
      );
      expect(statusPartial.allGranted, false);
    });

    test('MeetupSafetyNotificationActions constant identifiers', () {
      expect(MeetupSafetyNotificationActions.sos, 'meetup_safety_sos');
      expect(MeetupSafetyNotificationActions.call112, 'meetup_safety_call_112');
      expect(
        MeetupSafetyNotificationActions.informContacts,
        'meetup_safety_inform_contacts',
      );
      expect(MeetupSafetyNotificationActions.imSafe, 'meetup_safety_im_safe');
    });
  });
}

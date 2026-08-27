import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MeetupSafetySession & Permissions Exhaustive Tests', () {
    test('MeetupSafetyPermissionStatus getters and constructors', () {
      const all = MeetupSafetyPermissionStatus.allGranted();
      expect(all.notificationsGranted, isTrue);
      expect(all.exactAlarmsGranted, isTrue);
      expect(all.fullScreenIntentGranted, isTrue);
      expect(all.allGranted, isTrue);

      const partial = MeetupSafetyPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: false,
        fullScreenIntentGranted: true,
      );
      expect(partial.notificationsGranted, isTrue);
      expect(partial.exactAlarmsGranted, isFalse);
      expect(partial.fullScreenIntentGranted, isTrue);
      expect(partial.allGranted, isFalse);
    });

    test('MeetupSafetySession singleton initial properties', () {
      final session = MeetupSafetySession.instance;
      expect(session.isActive, isFalse);
      expect(session.hasSyncWarning, isFalse);
      expect(session.nextCheckInAt, isNull);
      expect(session.checkInLabel, isEmpty);
      expect(session.serverSessionId, isNull);
      expect(session.checkInInterval, const Duration(hours: 1));
    });
  });
}

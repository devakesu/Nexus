import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/pending_evidence_upload_queue.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('MeetupSafetySession Unit Tests', () {
    test('MeetupSafetyPermissionStatus represents settings correctly', () {
      const statusGranted = MeetupSafetyPermissionStatus.allGranted();
      expect(statusGranted.notificationsGranted, isTrue);
      expect(statusGranted.exactAlarmsGranted, isTrue);
      expect(statusGranted.fullScreenIntentGranted, isTrue);

      const statusPartial = MeetupSafetyPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: false,
        fullScreenIntentGranted: true,
      );
      expect(statusPartial.exactAlarmsGranted, isFalse);
    });

    test('MeetupSafetySession singleton instance is accessible', () {
      final session = MeetupSafetySession.instance;
      expect(session, isNotNull);
    });
  });

  group('PendingEvidenceUploadQueue Unit Tests', () {
    test('PendingEvidenceUploadQueue drain runs safely', () async {
      final res = await PendingEvidenceUploadQueue.drain();
      expect(res, isTrue);
    });
  });
}

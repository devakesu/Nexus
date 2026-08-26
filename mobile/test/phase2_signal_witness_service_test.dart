import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/digital_witness_recorder.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
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
        const MethodChannel('com.devakesu.apps.nexus/safety'),
        (call) async => null,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('SignalKeyService Unit Tests', () {
    test('singleton instance exists and exposes identity flags', () {
      final service = SignalKeyService.instance;
      expect(service, isNotNull);
      expect(service.isNewLocalIdentity, isFalse);
    });
  });

  group('DigitalWitnessRecorder Unit Tests', () {
    test('singleton instance initializes with idle recording state', () {
      final recorder = DigitalWitnessRecorder.instance;
      expect(recorder, isNotNull);
      expect(recorder.isRecording, isFalse);
      expect(recorder.elapsed, Duration.zero);
      expect(recorder.controller, isNull);
    });

    test('stop returns gracefully when not recording', () async {
      final recorder = DigitalWitnessRecorder.instance;
      await recorder.stop();
      expect(recorder.isRecording, isFalse);
    });
  });
}

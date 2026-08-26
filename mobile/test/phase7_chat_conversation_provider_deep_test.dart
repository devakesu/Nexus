import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
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

  group('ChatConversation Models and Serialization Tests', () {
    test('MediaPointer serialization and deserialization', () {
      const pointer = MediaPointer(
        storagePath: 'chat_media/audio_123.m4a',
        mediaKeyBase64: 'mockMediaKey==',
        mimeType: 'audio/m4a',
        sizeBytes: 102400,
        durationMs: 4500,
      );

      final json = pointer.toJson();
      expect(json['storage_path'], 'chat_media/audio_123.m4a');
      expect(json['media_key'], 'mockMediaKey==');
      expect(json['mime_type'], 'audio/m4a');
      expect(json['size_bytes'], 102400);
      expect(json['duration_ms'], 4500);

      final fromJson = MediaPointer.fromJson(json);
      expect(fromJson.storagePath, pointer.storagePath);
      expect(fromJson.mediaKeyBase64, pointer.mediaKeyBase64);
      expect(fromJson.sizeBytes, pointer.sizeBytes);
      expect(fromJson.durationMs, pointer.durationMs);
    });

    test('LocationPointer serialization and deserialization', () {
      const location = LocationPointer(
        lat: 37.7749,
        lng: -122.4194,
        label: 'Blue Bottle Coffee',
      );

      final json = location.toJson();
      expect(json['lat'], 37.7749);
      expect(json['lng'], -122.4194);
      expect(json['label'], 'Blue Bottle Coffee');

      final fromJson = LocationPointer.fromJson(json);
      expect(fromJson.lat, location.lat);
      expect(fromJson.lng, location.lng);
      expect(fromJson.label, location.label);
    });

    test('EventPayload serialization and deserialization', () {
      const event = EventPayload(
        title: 'Dinner & Drinks',
        notes: 'Meet at 7:30 PM outside',
      );

      final json = event.toJson();
      expect(json['title'], 'Dinner & Drinks');
      expect(json['notes'], 'Meet at 7:30 PM outside');

      final fromJson = EventPayload.fromJson(json);
      expect(fromJson.title, event.title);
      expect(fromJson.notes, event.notes);
    });

    test('ChatEventInfo row parsing', () {
      final row = {
        'id': 'evt_123',
        'event_time': '2026-09-01T19:00:00.000Z',
        'location_lat': 37.7833,
        'location_lng': -122.4167,
        'location_label': 'Market St',
        'status': 'confirmed',
        'safety_enabled': true,
      };

      final info = ChatEventInfo.fromRow(row);
      expect(info.eventId, 'evt_123');
      expect(info.locationLabel, 'Market St');
      expect(info.status, 'confirmed');
      expect(info.safetyEnabled, true);
    });

    test('ChatMessageView model creation and properties', () {
      final msg = ChatMessageView(
        id: 'msg_1',
        senderId: 'user_me',
        isMine: true,
        createdAt: DateTime(2026, 8, 26, 12),
        plaintext: 'Hello there!',
        messageType: 'text',
        decryptFailed: false,
      );

      expect(msg.id, 'msg_1');
      expect(msg.isMine, true);
      expect(msg.plaintext, 'Hello there!');
      expect(msg.messageType, 'text');
      expect(msg.decryptFailed, false);
      expect(msg.readAt, isNull);
    });
  });
}

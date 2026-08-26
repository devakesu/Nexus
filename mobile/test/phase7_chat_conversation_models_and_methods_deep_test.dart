import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chat Conversation Provider Models Deep Coverage Tests', () {
    test('MediaPointer serialization and deserialization', () {
      const pointer = MediaPointer(
        storagePath: 'conv_1/user_1/voice_1.enc',
        mediaKeyBase64: 'mock_key_base64==',
        mimeType: 'audio/m4a',
        sizeBytes: 1024,
        durationMs: 3500,
      );

      expect(pointer.storagePath, 'conv_1/user_1/voice_1.enc');
      expect(pointer.mediaKeyBase64, 'mock_key_base64==');
      expect(pointer.mimeType, 'audio/m4a');
      expect(pointer.sizeBytes, 1024);
      expect(pointer.durationMs, 3500);

      final json = pointer.toJson();
      expect(json['storage_path'], 'conv_1/user_1/voice_1.enc');
      expect(json['media_key'], 'mock_key_base64==');
      expect(json['mime_type'], 'audio/m4a');
      expect(json['size_bytes'], 1024);
      expect(json['duration_ms'], 3500);

      final fromJson = MediaPointer.fromJson(json);
      expect(fromJson.storagePath, pointer.storagePath);
      expect(fromJson.mediaKeyBase64, pointer.mediaKeyBase64);
      expect(fromJson.mimeType, pointer.mimeType);
      expect(fromJson.sizeBytes, pointer.sizeBytes);
      expect(fromJson.durationMs, pointer.durationMs);

      const minimalPointer = MediaPointer(
        storagePath: 'p.enc',
        mediaKeyBase64: 'k',
        mimeType: 'img/png',
      );
      expect(minimalPointer.sizeBytes, isNull);
      expect(minimalPointer.durationMs, isNull);
      expect(minimalPointer.toJson().containsKey('size_bytes'), false);
    });

    test('LocationPointer serialization and deserialization', () {
      const location = LocationPointer(
        lat: 37.7749,
        lng: -122.4194,
        label: 'Union Square, SF',
      );

      expect(location.lat, 37.7749);
      expect(location.lng, -122.4194);
      expect(location.label, 'Union Square, SF');

      final json = location.toJson();
      expect(json['lat'], 37.7749);
      expect(json['lng'], -122.4194);
      expect(json['label'], 'Union Square, SF');

      final fromJson = LocationPointer.fromJson(json);
      expect(fromJson.lat, location.lat);
      expect(fromJson.lng, location.lng);
      expect(fromJson.label, location.label);
    });

    test('EventPayload serialization and deserialization', () {
      const payload = EventPayload(
        title: 'Boba Run & Study Session',
        notes: 'Bring laptops and notebooks',
      );

      expect(payload.title, 'Boba Run & Study Session');
      expect(payload.notes, 'Bring laptops and notebooks');

      final json = payload.toJson();
      expect(json['title'], 'Boba Run & Study Session');
      expect(json['notes'], 'Bring laptops and notebooks');

      final fromJson = EventPayload.fromJson(json);
      expect(fromJson.title, payload.title);
      expect(fromJson.notes, payload.notes);

      const minimal = EventPayload(title: 'Coffee');
      expect(minimal.notes, isNull);
      expect(minimal.toJson().containsKey('notes'), false);
    });

    test('ChatEventInfo properties, copyWith, and row parsing', () {
      final now = DateTime.now();
      final eventInfo = ChatEventInfo(
        eventId: 'evt_101',
        eventTime: now,
        locationLat: 40.7128,
        locationLng: -74.0060,
        locationLabel: 'Washington Square Park',
        status: 'proposed',
        safetyEnabled: true,
      );

      expect(eventInfo.eventId, 'evt_101');
      expect(eventInfo.status, 'proposed');
      expect(eventInfo.safetyEnabled, true);

      final row = {
        'id': 'evt_102',
        'event_time': now.toIso8601String(),
        'location_lat': 34.0522,
        'location_lng': -118.2437,
        'location_label': 'Santa Monica Pier',
        'status': 'accepted',
        'safety_enabled': false,
      };

      final fromRow = ChatEventInfo.fromRow(row);
      expect(fromRow.eventId, 'evt_102');
      expect(fromRow.status, 'accepted');
      expect(fromRow.safetyEnabled, false);
      expect(fromRow.locationLabel, 'Santa Monica Pier');

      final updated = fromRow.copyWith(
        status: 'declined',
        safetyEnabled: true,
      );
      expect(updated.status, 'declined');
      expect(updated.safetyEnabled, true);
    });

    test('ChatMessageView and ChatConversationState model operations', () {
      final now = DateTime.now();
      final msg = ChatMessageView(
        id: 'msg_99',
        senderId: 'user_other',
        isMine: false,
        createdAt: now,
        plaintext: 'Hey there! How is your day going?',
        messageType: 'text',
        decryptFailed: false,
      );

      expect(msg.id, 'msg_99');
      expect(msg.isMine, false);
      expect(msg.plaintext, 'Hey there! How is your day going?');
      expect(msg.decryptFailed, false);

      final updatedMsg = msg.copyWith(readAt: now);
      expect(updatedMsg.readAt, now);

      final state = ChatConversationState(
        messages: [msg],
        sessionReady: true,
        sending: false,
      );

      expect(state.messages.length, 1);
      expect(state.sessionReady, true);
      expect(state.sending, false);
      expect(state.hasMoreHistory, true);
      expect(state.loadingOlder, false);

      final updatedState = state.copyWith(
        sending: true,
        loadingOlder: true,
      );
      expect(updatedState.sending, true);
      expect(updatedState.loadingOlder, true);
    });
  });
}

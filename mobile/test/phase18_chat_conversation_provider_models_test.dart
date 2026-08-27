import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatConversationProvider Models & State Deep Coverage', () {
    test('MediaPointer toJson/fromJson and field verification', () {
      const media1 = MediaPointer(
        storagePath: 'chat_media/c1/u1/file.jpg',
        mediaKeyBase64: 'key123',
        mimeType: 'image/jpeg',
        sizeBytes: 2048,
        durationMs: 3000,
      );
      final json1 = media1.toJson();
      expect(json1['storage_path'], 'chat_media/c1/u1/file.jpg');
      expect(json1['media_key'], 'key123');
      expect(json1['mime_type'], 'image/jpeg');
      expect(json1['size_bytes'], 2048);
      expect(json1['duration_ms'], 3000);

      final fromJson1 = MediaPointer.fromJson(json1);
      expect(fromJson1.storagePath, media1.storagePath);
      expect(fromJson1.mediaKeyBase64, media1.mediaKeyBase64);
      expect(fromJson1.mimeType, media1.mimeType);
      expect(fromJson1.sizeBytes, media1.sizeBytes);
      expect(fromJson1.durationMs, media1.durationMs);

      // Without optional fields
      const media2 = MediaPointer(
        storagePath: 'chat_media/c2/u2/voice.m4a',
        mediaKeyBase64: 'key456',
        mimeType: 'audio/m4a',
      );
      final json2 = media2.toJson();
      expect(json2.containsKey('size_bytes'), isFalse);
      expect(json2.containsKey('duration_ms'), isFalse);

      final fromJson2 = MediaPointer.fromJson(json2);
      expect(fromJson2.sizeBytes, isNull);
      expect(fromJson2.durationMs, isNull);
    });

    test('LocationPointer toJson/fromJson and field verification', () {
      const loc1 = LocationPointer(
        lat: 37.7749,
        lng: -122.4194,
        label: 'San Francisco',
      );
      final json1 = loc1.toJson();
      expect(json1['lat'], 37.7749);
      expect(json1['lng'], -122.4194);
      expect(json1['label'], 'San Francisco');

      final fromJson1 = LocationPointer.fromJson(json1);
      expect(fromJson1.lat, loc1.lat);
      expect(fromJson1.lng, loc1.lng);
      expect(fromJson1.label, loc1.label);

      // Without label
      const loc2 = LocationPointer(lat: 40.7128, lng: -74.0060);
      final json2 = loc2.toJson();
      expect(json2.containsKey('label'), isFalse);
      final fromJson2 = LocationPointer.fromJson(json2);
      expect(fromJson2.label, isNull);
    });

    test('EventPayload toJson/fromJson and field verification', () {
      const payload1 = EventPayload(
        title: 'Coffee Meetup',
        notes: 'Bring laptops',
      );
      final json1 = payload1.toJson();
      expect(json1['title'], 'Coffee Meetup');
      expect(json1['notes'], 'Bring laptops');

      final fromJson1 = EventPayload.fromJson(json1);
      expect(fromJson1.title, payload1.title);
      expect(fromJson1.notes, payload1.notes);

      // Fallback empty title and null notes
      final fromJson2 = EventPayload.fromJson({});
      expect(fromJson2.title, '');
      expect(fromJson2.notes, isNull);
    });

    test('ChatEventInfo fromRow, copyWith and fields', () {
      final now = DateTime.now();
      final row = {
        'id': 'evt_99',
        'event_time': now.toIso8601String(),
        'location_lat': 37.7749,
        'location_lng': -122.4194,
        'location_label': 'Palace of Fine Arts',
        'status': 'confirmed',
        'safety_enabled': true,
      };

      final event = ChatEventInfo.fromRow(row);
      expect(event.eventId, 'evt_99');
      expect(event.eventTime.year, now.year);
      expect(event.locationLat, 37.7749);
      expect(event.locationLng, -122.4194);
      expect(event.locationLabel, 'Palace of Fine Arts');
      expect(event.status, 'confirmed');
      expect(event.safetyEnabled, isTrue);

      final nextDay = now.add(const Duration(days: 1));
      final updated = event.copyWith(
        status: 'cancelled',
        eventTime: nextDay,
        locationLat: 40.7128,
        locationLng: -74.0060,
        locationLabel: 'New York',
        safetyEnabled: false,
      );
      expect(updated.status, 'cancelled');
      expect(updated.eventTime, nextDay);
      expect(updated.locationLat, 40.7128);
      expect(updated.locationLng, -74.0060);
      expect(updated.locationLabel, 'New York');
      expect(updated.safetyEnabled, isFalse);

      // Default fallback values
      final defaultEvent = ChatEventInfo.fromRow({
        'id': 'evt_100',
        'event_time': now.toIso8601String(),
      });
      expect(defaultEvent.status, 'proposed');
      expect(defaultEvent.safetyEnabled, isFalse);
      expect(defaultEvent.locationLat, isNull);
    });

    test('ChatMessageView copyWith and properties', () {
      final now = DateTime.now();
      final msg = ChatMessageView(
        id: 'msg_1',
        senderId: 'user_a',
        isMine: true,
        createdAt: now,
        plaintext: 'Hello world',
        messageType: 'text',
        decryptFailed: false,
      );
      expect(msg.id, 'msg_1');
      expect(msg.senderId, 'user_a');
      expect(msg.isMine, isTrue);
      expect(msg.plaintext, 'Hello world');
      expect(msg.messageType, 'text');
      expect(msg.decryptFailed, isFalse);
      expect(msg.readAt, isNull);
      expect(msg.eventInfo, isNull);

      final readTime = now.add(const Duration(minutes: 5));
      final updatedMsg = msg.copyWith(
        plaintext: 'Updated text',
        decryptFailed: true,
        readAt: readTime,
      );
      expect(updatedMsg.plaintext, 'Updated text');
      expect(updatedMsg.decryptFailed, isTrue);
      expect(updatedMsg.readAt, readTime);
    });

    test('ChatConversationState copyWith and initial defaults', () {
      const state = ChatConversationState(
        messages: [],
        sessionReady: true,
        sending: false,
      );
      expect(state.messages, isEmpty);
      expect(state.sessionReady, isTrue);
      expect(state.sending, isFalse);
      expect(state.isNewLocalIdentity, isFalse);
      expect(state.isReducedEncryption, isFalse);
      expect(state.conversationClosed, isFalse);
      expect(state.hasMoreHistory, isTrue);
      expect(state.loadingOlder, isFalse);
      expect(state.isRevalidating, isFalse);

      final updatedState = state.copyWith(
        messages: [
          ChatMessageView(
            id: 'm1',
            senderId: 'u1',
            isMine: false,
            createdAt: DateTime.now(),
            plaintext: 'Hey',
            messageType: 'text',
            decryptFailed: false,
          ),
        ],
        sessionReady: false,
        sending: true,
        isNewLocalIdentity: true,
        isReducedEncryption: true,
        conversationClosed: true,
        hasMoreHistory: false,
        loadingOlder: true,
        isRevalidating: true,
      );

      expect(updatedState.messages.length, 1);
      expect(updatedState.sessionReady, isFalse);
      expect(updatedState.sending, isTrue);
      expect(updatedState.isNewLocalIdentity, isTrue);
      expect(updatedState.isReducedEncryption, isTrue);
      expect(updatedState.conversationClosed, isTrue);
      expect(updatedState.hasMoreHistory, isFalse);
      expect(updatedState.loadingOlder, isTrue);
      expect(updatedState.isRevalidating, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chat Conversation Provider Models Exhaustive Mega Tests', () {
    test('MediaPointer toJson and fromJson roundtrip', () {
      const ptr = MediaPointer(
        storagePath: 'media/chat/image1.jpg',
        mediaKeyBase64: 'kEy12345Base64==',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        durationMs: 5000,
      );

      final json = ptr.toJson();
      expect(json['storage_path'], 'media/chat/image1.jpg');
      expect(json['media_key'], 'kEy12345Base64==');
      expect(json['mime_type'], 'image/jpeg');
      expect(json['size_bytes'], 1024);
      expect(json['duration_ms'], 5000);

      final parsed = MediaPointer.fromJson(json);
      expect(parsed.storagePath, ptr.storagePath);
      expect(parsed.mediaKeyBase64, ptr.mediaKeyBase64);
      expect(parsed.mimeType, ptr.mimeType);
      expect(parsed.sizeBytes, ptr.sizeBytes);
      expect(parsed.durationMs, ptr.durationMs);
    });

    test('LocationPointer toJson and fromJson roundtrip', () {
      const loc = LocationPointer(
        lat: 47.6062,
        lng: -122.3321,
        label: 'Seattle Center',
      );

      final json = loc.toJson();
      expect(json['lat'], 47.6062);
      expect(json['lng'], -122.3321);
      expect(json['label'], 'Seattle Center');

      final parsed = LocationPointer.fromJson(json);
      expect(parsed.lat, loc.lat);
      expect(parsed.lng, loc.lng);
      expect(parsed.label, loc.label);
    });

    test('EventPayload toJson and fromJson roundtrip', () {
      const event = EventPayload(
        title: 'Coffee Chat',
        notes: 'Meet outside the coffee shop.',
      );

      final json = event.toJson();
      expect(json['title'], 'Coffee Chat');
      expect(json['notes'], 'Meet outside the coffee shop.');

      final parsed = EventPayload.fromJson(json);
      expect(parsed.title, event.title);
      expect(parsed.notes, event.notes);
    });

    test('ChatEventInfo fromRow and copyWith', () {
      final row = {
        'id': 'event-100',
        'event_time': '2026-03-01T18:00:00.000Z',
        'location_lat': 37.7749,
        'location_lng': -122.4194,
        'location_label': 'Market St',
        'status': 'confirmed',
        'safety_enabled': true,
      };

      final info = ChatEventInfo.fromRow(row);
      expect(info.eventId, 'event-100');
      expect(info.status, 'confirmed');
      expect(info.safetyEnabled, isTrue);
      expect(info.locationLat, 37.7749);
      expect(info.locationLng, -122.4194);
      expect(info.locationLabel, 'Market St');

      final modified = info.copyWith(
        status: 'cancelled',
        safetyEnabled: false,
      );
      expect(modified.status, 'cancelled');
      expect(modified.safetyEnabled, isFalse);
      expect(modified.eventId, 'event-100');
    });

    test('ChatMessageView copyWith', () {
      final msg = ChatMessageView(
        id: 'm1',
        senderId: 's1',
        isMine: true,
        createdAt: DateTime(2026, 2, 3),
        plaintext: 'Test',
        messageType: 'text',
        decryptFailed: false,
      );

      final modified = msg.copyWith(
        plaintext: 'Updated',
        decryptFailed: true,
        readAt: DateTime(2026, 2, 3, 12, 30),
      );

      expect(modified.plaintext, 'Updated');
      expect(modified.decryptFailed, isTrue);
      expect(modified.readAt, isNotNull);
      expect(modified.id, 'm1');
    });

    test('ChatConversationState copyWith', () {
      const state = ChatConversationState(
        messages: [],
        sessionReady: false,
        sending: false,
      );

      final modified = state.copyWith(
        sessionReady: true,
        sending: true,
        isNewLocalIdentity: true,
        isReducedEncryption: true,
        conversationClosed: true,
        hasMoreHistory: false,
        loadingOlder: true,
        isRevalidating: true,
      );

      expect(modified.sessionReady, isTrue);
      expect(modified.sending, isTrue);
      expect(modified.isNewLocalIdentity, isTrue);
      expect(modified.isReducedEncryption, isTrue);
      expect(modified.conversationClosed, isTrue);
      expect(modified.hasMoreHistory, isFalse);
      expect(modified.loadingOlder, isTrue);
      expect(modified.isRevalidating, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 68 - Chat Conversation Provider Deep Logic Mega Tests', () {
    test('MediaPointer all combinations and optional parameters', () {
      const p1 = MediaPointer(
        storagePath: 'chat_media/voice.m4a',
        mediaKeyBase64: 'media_key_abc_123',
        mimeType: 'audio/m4a',
        sizeBytes: 2048,
        durationMs: 3200,
      );

      expect(p1.storagePath, 'chat_media/voice.m4a');
      expect(p1.sizeBytes, 2048);
      expect(p1.durationMs, 3200);

      final json = p1.toJson();
      expect(json['storage_path'], 'chat_media/voice.m4a');
      expect(json['media_key'], 'media_key_abc_123');
      expect(json['size_bytes'], 2048);
      expect(json['duration_ms'], 3200);

      final reconstructed = MediaPointer.fromJson(json);
      expect(reconstructed.storagePath, p1.storagePath);
      expect(reconstructed.mediaKeyBase64, p1.mediaKeyBase64);
      expect(reconstructed.mimeType, p1.mimeType);
      expect(reconstructed.sizeBytes, p1.sizeBytes);
      expect(reconstructed.durationMs, p1.durationMs);
    });

    test('LocationPointer equality and edge cases', () {
      const loc1 = LocationPointer(lat: 0, lng: 0, label: 'Null Island');
      final json = loc1.toJson();
      expect(json['lat'], 0.0);
      expect(json['lng'], 0.0);
      expect(json['label'], 'Null Island');

      final reconstructed = LocationPointer.fromJson(json);
      expect(reconstructed.lat, 0.0);
      expect(reconstructed.lng, 0.0);
      expect(reconstructed.label, 'Null Island');
    });

    test('EventPayload empty and full notes handling', () {
      const payload1 = EventPayload(title: 'Team Sync');
      expect(payload1.title, 'Team Sync');
      expect(payload1.notes, isNull);

      final json1 = payload1.toJson();
      expect(json1['title'], 'Team Sync');
      expect(json1.containsKey('notes'), isFalse);

      final fromJson1 = EventPayload.fromJson(json1);
      expect(fromJson1.title, 'Team Sync');
      expect(fromJson1.notes, isNull);

      const payload2 = EventPayload(title: 'Lunch', notes: 'At Central Park');
      final json2 = payload2.toJson();
      expect(json2['notes'], 'At Central Park');
      final fromJson2 = EventPayload.fromJson(json2);
      expect(fromJson2.notes, 'At Central Park');
    });

    test('ChatEventInfo copyWith and fromRow full mapping', () {
      final row = {
        'id': 'event_999',
        'event_time': '2026-10-15T14:30:00Z',
        'location_lat': 51.5074,
        'location_lng': -0.1278,
        'location_label': 'Big Ben',
        'status': 'pending',
        'safety_enabled': true,
      };

      final info = ChatEventInfo.fromRow(row);
      expect(info.eventId, 'event_999');
      expect(info.locationLat, 51.5074);
      expect(info.locationLng, -0.1278);
      expect(info.locationLabel, 'Big Ben');
      expect(info.status, 'pending');
      expect(info.safetyEnabled, isTrue);

      final updated = info.copyWith(
        status: 'confirmed',
        safetyEnabled: false,
      );
      expect(updated.status, 'confirmed');
      expect(updated.safetyEnabled, isFalse);
      expect(updated.eventId, 'event_999');
    });

    test('ChatMessageView and ChatConversationState copyWith mutations', () {
      final msg = ChatMessageView(
        id: 'msg_test_1',
        senderId: 'usr_test_1',
        isMine: true,
        createdAt: DateTime(2026),
        plaintext: 'Hello World',
        messageType: 'text',
        decryptFailed: false,
      );

      final modified = msg.copyWith(
        plaintext: 'Edited text',
        decryptFailed: true,
      );
      expect(modified.plaintext, 'Edited text');
      expect(modified.decryptFailed, isTrue);
      expect(modified.id, 'msg_test_1');

      const state = ChatConversationState(
        messages: [],
        sessionReady: true,
        sending: false,
      );

      final updatedState = state.copyWith(
        messages: [msg],
        sending: true,
        isNewLocalIdentity: true,
        isReducedEncryption: true,
        conversationClosed: true,
        hasMoreHistory: false,
        loadingOlder: true,
        isRevalidating: true,
      );

      expect(updatedState.messages.length, 1);
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

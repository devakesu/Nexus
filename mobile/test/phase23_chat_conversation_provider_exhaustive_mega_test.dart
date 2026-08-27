import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_secure_screen'),
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

  group('ChatConversationProvider Models & Logic Exhaustive Mega Tests', () {
    test('MediaPointer fromJson, toJson, and field serialization', () {
      final json = {
        'storage_path': 'chat_media/img_123.enc',
        'media_key': 'bWVkaWFfa2V5XzEyMzQ1Njc4',
        'mime_type': 'image/jpeg',
        'size_bytes': 1048576,
        'duration_ms': 5400,
      };

      final pointer = MediaPointer.fromJson(json);
      expect(pointer.storagePath, 'chat_media/img_123.enc');
      expect(pointer.mediaKeyBase64, 'bWVkaWFfa2V5XzEyMzQ1Njc4');
      expect(pointer.mimeType, 'image/jpeg');
      expect(pointer.sizeBytes, 1048576);
      expect(pointer.durationMs, 5400);

      final exported = pointer.toJson();
      expect(exported['storage_path'], pointer.storagePath);
      expect(exported['media_key'], pointer.mediaKeyBase64);
      expect(exported['mime_type'], pointer.mimeType);
      expect(exported['size_bytes'], pointer.sizeBytes);
      expect(exported['duration_ms'], pointer.durationMs);

      const minimalPointer = MediaPointer(
        storagePath: 'chat_media/audio.enc',
        mediaKeyBase64: 'key123',
        mimeType: 'audio/m4a',
      );
      expect(minimalPointer.sizeBytes, isNull);
      expect(minimalPointer.durationMs, isNull);
      expect(minimalPointer.toJson().containsKey('size_bytes'), isFalse);
    });

    test('LocationPointer fromJson, toJson, and field serialization', () {
      final json = {
        'lat': 37.7749,
        'lng': -122.4194,
        'label': 'San Francisco Hub',
      };

      final pointer = LocationPointer.fromJson(json);
      expect(pointer.lat, 37.7749);
      expect(pointer.lng, -122.4194);
      expect(pointer.label, 'San Francisco Hub');

      final exported = pointer.toJson();
      expect(exported['lat'], 37.7749);
      expect(exported['lng'], -122.4194);
      expect(exported['label'], 'San Francisco Hub');

      const noLabelPointer = LocationPointer(lat: 40.7128, lng: -74.0060);
      expect(noLabelPointer.label, isNull);
      expect(noLabelPointer.toJson().containsKey('label'), isFalse);
    });

    test('EventPayload fromJson, toJson, and field serialization', () {
      final json = {
        'title': 'Coffee Meetup @ Philz',
        'notes': 'Bring project ideas!',
      };

      final payload = EventPayload.fromJson(json);
      expect(payload.title, 'Coffee Meetup @ Philz');
      expect(payload.notes, 'Bring project ideas!');

      final exported = payload.toJson();
      expect(exported['title'], 'Coffee Meetup @ Philz');
      expect(exported['notes'], 'Bring project ideas!');

      final emptyPayload = EventPayload.fromJson(const {});
      expect(emptyPayload.title, '');
      expect(emptyPayload.notes, isNull);
      expect(emptyPayload.toJson().containsKey('notes'), isFalse);
    });

    test('ChatEventInfo fromRow, copyWith, and field values', () {
      final row = {
        'id': 'evt_999',
        'event_time': '2026-09-01T15:30:00Z',
        'location_lat': 51.5074,
        'location_lng': -0.1278,
        'location_label': 'Trafalgar Square',
        'status': 'accepted',
        'safety_enabled': true,
      };

      final info = ChatEventInfo.fromRow(row);
      expect(info.eventId, 'evt_999');
      expect(info.eventTime, DateTime.parse('2026-09-01T15:30:00Z'));
      expect(info.locationLat, 51.5074);
      expect(info.locationLng, -0.1278);
      expect(info.locationLabel, 'Trafalgar Square');
      expect(info.status, 'accepted');
      expect(info.safetyEnabled, isTrue);

      final updated = info.copyWith(
        status: 'declined',
        locationLabel: 'New Location',
        safetyEnabled: false,
      );
      expect(updated.status, 'declined');
      expect(updated.locationLabel, 'New Location');
      expect(updated.safetyEnabled, isFalse);
      expect(updated.eventId, info.eventId);
    });

    test(
      'ChatMessageView and ChatConversationState copyWith and properties',
      () {
        final msg = ChatMessageView(
          id: 'msg_001',
          senderId: 'usr_001',
          isMine: true,
          createdAt: DateTime.now(),
          plaintext: 'Hello world!',
          messageType: 'text',
          decryptFailed: false,
          readAt: DateTime.now(),
        );

        expect(msg.id, 'msg_001');
        expect(msg.plaintext, 'Hello world!');
        expect(msg.decryptFailed, isFalse);

        final modifiedMsg = msg.copyWith(
          plaintext: 'Updated text',
          decryptFailed: true,
        );
        expect(modifiedMsg.plaintext, 'Updated text');
        expect(modifiedMsg.decryptFailed, isTrue);

        final state = ChatConversationState(
          messages: [msg],
          sessionReady: true,
          sending: false,
          isNewLocalIdentity: true,
          isReducedEncryption: true,
        );

        expect(state.messages.length, 1);
        expect(state.sessionReady, isTrue);

        final updatedState = state.copyWith(
          sending: true,
          conversationClosed: true,
          loadingOlder: true,
        );
        expect(updatedState.sending, isTrue);
        expect(updatedState.conversationClosed, isTrue);
        expect(updatedState.loadingOlder, isTrue);
      },
    );

    test(
      'ChatConversationController builds non-UUID peer with closed state instantly',
      () async {
        final container = ProviderContainer();
        try {
          final state = await container.read(
            chatConversationControllerProvider(
              'conv_non_uuid',
              'invalid-peer-id',
            ).future,
          );

          expect(state.conversationClosed, isTrue);
          expect(state.sessionReady, isFalse);
          expect(state.messages, isEmpty);
        } finally {
          container.dispose();
        }
      },
    );
  });
}

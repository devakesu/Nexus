import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/mock_network_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockSessionJson = jsonEncode({
    'access_token': 'mock-access-token-12345',
    'refresh_token': 'mock-refresh-token-12345',
    'expires_in': 3600,
    'expires_at': 1893456000,
    'token_type': 'bearer',
    'user': {
      'id': '00000000-0000-0000-0000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'user@nexus.test',
      'phone': '+14155552671',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    },
  });

  SharedPreferences.setMockInitialValues({
    'sb-mock-auth-token': mockSessionJson,
  });
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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
    setupGlobalMockNetwork();
  });

  group(
    'Phase 120 - Chat Conversation Provider Deep Exhaustive Mega Tests',
    () {
      test('MediaPointer full json serialization and deserialization', () {
        const mp1 = MediaPointer(
          storagePath: 'chat_media/img1.jpg',
          mediaKeyBase64: 'key123==',
          mimeType: 'image/jpeg',
          sizeBytes: 1024,
          durationMs: 5000,
        );

        final json1 = mp1.toJson();
        expect(json1['storage_path'], 'chat_media/img1.jpg');
        expect(json1['media_key'], 'key123==');
        expect(json1['mime_type'], 'image/jpeg');
        expect(json1['size_bytes'], 1024);
        expect(json1['duration_ms'], 5000);

        final fromJson1 = MediaPointer.fromJson(json1);
        expect(fromJson1.storagePath, mp1.storagePath);
        expect(fromJson1.mediaKeyBase64, mp1.mediaKeyBase64);
        expect(fromJson1.mimeType, mp1.mimeType);
        expect(fromJson1.sizeBytes, mp1.sizeBytes);
        expect(fromJson1.durationMs, mp1.durationMs);

        // Minimal without optional fields
        const mp2 = MediaPointer(
          storagePath: 'path2',
          mediaKeyBase64: 'key2',
          mimeType: 'audio/mp4',
        );
        final json2 = mp2.toJson();
        expect(json2.containsKey('size_bytes'), isFalse);
        expect(json2.containsKey('duration_ms'), isFalse);

        final fromJson2 = MediaPointer.fromJson(json2);
        expect(fromJson2.sizeBytes, isNull);
        expect(fromJson2.durationMs, isNull);
      });

      test('LocationPointer full json serialization and deserialization', () {
        const lp1 = LocationPointer(
          lat: 37.7749,
          lng: -122.4194,
          label: 'San Francisco, CA',
        );
        final json1 = lp1.toJson();
        expect(json1['lat'], 37.7749);
        expect(json1['lng'], -122.4194);
        expect(json1['label'], 'San Francisco, CA');

        final fromJson1 = LocationPointer.fromJson(json1);
        expect(fromJson1.lat, lp1.lat);
        expect(fromJson1.lng, lp1.lng);
        expect(fromJson1.label, lp1.label);

        const lp2 = LocationPointer(lat: 40.7128, lng: -74.0060);
        final json2 = lp2.toJson();
        expect(json2.containsKey('label'), isFalse);

        final fromJson2 = LocationPointer.fromJson(json2);
        expect(fromJson2.label, isNull);
      });

      test('EventPayload full json serialization and deserialization', () {
        const ep1 = EventPayload(
          title: 'Coffee Meetup',
          notes: 'Bring books',
        );
        final json1 = ep1.toJson();
        expect(json1['title'], 'Coffee Meetup');
        expect(json1['notes'], 'Bring books');

        final fromJson1 = EventPayload.fromJson(json1);
        expect(fromJson1.title, ep1.title);
        expect(fromJson1.notes, ep1.notes);

        const ep2 = EventPayload(title: 'Quick Chat');
        final json2 = ep2.toJson();
        expect(json2.containsKey('notes'), isFalse);

        final fromJson2 = EventPayload.fromJson(json2);
        expect(fromJson2.notes, isNull);
        expect(fromJson2.title, 'Quick Chat');

        final fromEmpty = EventPayload.fromJson({});
        expect(fromEmpty.title, '');
      });

      test('ChatEventInfo fromRow, copyWith, and properties', () {
        final row = {
          'id': 'evt_101',
          'event_time': '2026-09-01T18:00:00.000Z',
          'location_lat': 37.77,
          'location_lng': -122.42,
          'location_label': 'Parklet Cafe',
          'status': 'accepted',
          'safety_enabled': true,
        };

        final info = ChatEventInfo.fromRow(row);
        expect(info.eventId, 'evt_101');
        expect(info.eventTime, DateTime.parse('2026-09-01T18:00:00.000Z'));
        expect(info.locationLat, 37.77);
        expect(info.locationLng, -122.42);
        expect(info.locationLabel, 'Parklet Cafe');
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
        expect(updated.eventId, 'evt_101');

        final minimalRow = {
          'id': 'evt_min',
          'event_time': '2026-09-01T18:00:00.000Z',
        };
        final minimalInfo = ChatEventInfo.fromRow(minimalRow);
        expect(minimalInfo.locationLat, isNull);
        expect(minimalInfo.locationLng, isNull);
        expect(minimalInfo.locationLabel, isNull);
        expect(minimalInfo.status, 'proposed');
        expect(minimalInfo.safetyEnabled, isFalse);
      });

      test('ChatMessageView constructor and copyWith', () {
        final msg = ChatMessageView(
          id: 'msg_001',
          senderId: 'user_001',
          isMine: true,
          createdAt: DateTime(2026),
          plaintext: 'Hello world',
          messageType: 'text',
          decryptFailed: false,
          readAt: DateTime(2026, 1, 2),
        );

        expect(msg.id, 'msg_001');
        expect(msg.isMine, isTrue);
        expect(msg.plaintext, 'Hello world');

        final modified = msg.copyWith(
          plaintext: 'New text',
          decryptFailed: true,
        );
        expect(modified.plaintext, 'New text');
        expect(modified.decryptFailed, isTrue);
        expect(modified.id, 'msg_001');
        expect(modified.readAt, DateTime(2026, 1, 2));
      });

      test('ChatConversationState constructor and copyWith all fields', () {
        const initial = ChatConversationState(
          messages: [],
          sessionReady: false,
          sending: false,
        );

        expect(initial.messages, isEmpty);
        expect(initial.sessionReady, isFalse);
        expect(initial.isNewLocalIdentity, isFalse);
        expect(initial.isReducedEncryption, isFalse);
        expect(initial.conversationClosed, isFalse);
        expect(initial.hasMoreHistory, isTrue);
        expect(initial.loadingOlder, isFalse);
        expect(initial.isRevalidating, isFalse);

        final updated = initial.copyWith(
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
          sessionReady: true,
          sending: true,
          isNewLocalIdentity: true,
          isReducedEncryption: true,
          conversationClosed: true,
          hasMoreHistory: false,
          loadingOlder: true,
          isRevalidating: true,
        );

        expect(updated.messages.length, 1);
        expect(updated.sessionReady, isTrue);
        expect(updated.sending, isTrue);
        expect(updated.isNewLocalIdentity, isTrue);
        expect(updated.isReducedEncryption, isTrue);
        expect(updated.conversationClosed, isTrue);
        expect(updated.hasMoreHistory, isFalse);
        expect(updated.loadingOlder, isTrue);
        expect(updated.isRevalidating, isTrue);
      });

      test(
        'ChatConversationController builds with invalid and valid UUIDs',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          // Invalid UUID returns closed state
          final closedState = await container.read(
            chatConversationControllerProvider(
              'conv_1',
              'not-a-valid-uuid',
            ).future,
          );
          expect(closedState.conversationClosed, isTrue);
          expect(closedState.sessionReady, isFalse);
          expect(closedState.messages, isEmpty);

          // Valid UUID triggers bootstrap
          const validUuid = '00000000-0000-0000-0000-000000000002';
          final validState = container.read(
            chatConversationControllerProvider('c_100', validUuid),
          );

          expect(validState, isA<AsyncValue<ChatConversationState>>());
          await Future<void>.delayed(const Duration(milliseconds: 200));
        },
      );
    },
  );
}

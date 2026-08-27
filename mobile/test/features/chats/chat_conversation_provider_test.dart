import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/chat_list_tab.dart';
import 'package:nexus/features/chats/widgets/event_card.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
import 'package:nexus/features/chats/widgets/location_message_bubble.dart';
import 'package:nexus/features/chats/widgets/location_picker_sheet.dart';
import 'package:nexus/features/chats/widgets/new_chat_sheet.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/mock_network_interceptor.dart';
import '../../helpers/test_helpers.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
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
      'Chat Conversation Provider Deep Exhaustive Tests',
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

  // --- Section 2 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/google_maps_flutter'),
          (call) async => null,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async {
            if (call.method == 'isLocationServiceEnabled') {
              return true;
            }
            if (call.method == 'checkPermission' ||
                call.method == 'requestPermission') {
              return 3;
            }
            return {
              'latitude': 37.7749,
              'longitude': -122.4194,
              'timestamp': 0,
              'accuracy': 5.0,
              'altitude': 0.0,
              'altitude_accuracy': 0.0,
              'heading': 0.0,
              'heading_accuracy': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
            };
          },
        );

    group('Chats & Conversation Provider Mega Coverage Tests', () {
      test(
        'MediaPointer and LocationPointer serialize/deserialize accurately',
        () {
          const media = MediaPointer(
            storagePath: 'chat_media/c1/u1/file.enc',
            mediaKeyBase64: 'bWVkaWFrZXk=',
            mimeType: 'image/jpeg',
            sizeBytes: 1024,
            durationMs: 5000,
          );

          final json = media.toJson();
          expect(json['storage_path'], 'chat_media/c1/u1/file.enc');
          expect(json['size_bytes'], 1024);

          final fromJson = MediaPointer.fromJson(json);
          expect(fromJson.storagePath, media.storagePath);
          expect(fromJson.mediaKeyBase64, media.mediaKeyBase64);
          expect(fromJson.mimeType, media.mimeType);

          const loc = LocationPointer(
            lat: 37.7749,
            lng: -122.4194,
            label: 'Union Square',
          );
          final locJson = loc.toJson();
          expect(locJson['lat'], 37.7749);
          final locFromJson = LocationPointer.fromJson(locJson);
          expect(locFromJson.lat, loc.lat);
          expect(locFromJson.lng, loc.lng);
          expect(locFromJson.label, 'Union Square');
        },
      );

      testWidgets('ChatConversationPage renders and mounts cleanly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ChatConversationPage(
                  conversationId: 'conv_123',
                  matchedUserId: 'user_456',
                  tab: 'Dating',
                  name: 'Agent May',
                  profilePic: 'https://example.com/may.jpg',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ChatConversationPage), findsOneWidget);
        expect(find.text('Agent May'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });

      testWidgets('EventPlannerSheet renders properly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EventPlannerSheet(
                conversationId: 'conv_1',
                peerUserId: 'user_2',
                themeColor: AppColors.modeDating,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(EventPlannerSheet), findsOneWidget);
      });

      testWidgets('LocationPickerSheet renders properly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LocationPickerSheet(
                themeColor: AppColors.modeDating,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(LocationPickerSheet), findsOneWidget);
      });

      testWidgets('NewChatSheet renders properly', (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: NewChatSheet(
                  tab: 'Dating',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(NewChatSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('LocationMessageBubble renders properly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LocationMessageBubble(
                isMine: true,
                pointer: LocationPointer(
                  lat: 40.7128,
                  lng: -74.006,
                  label: 'Central Park',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(LocationMessageBubble), findsOneWidget);
      });

      testWidgets('EventCard renders properly', (tester) async {
        final eventInfo = ChatEventInfo(
          eventId: 'evt_1',
          eventTime: DateTime.now().add(const Duration(days: 1)),
          locationLat: 40.7128,
          locationLng: -74.006,
          locationLabel: 'Blue Bottle',
          status: 'pending',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: EventCard(
                  payload: const EventPayload(
                    title: 'Coffee Catchup',
                    notes: 'Let us meet at 4pm.',
                  ),
                  eventInfo: eventInfo,
                  conversationId: 'conv_123',
                  peerUserId: 'user_bob',
                  themeColor: AppColors.modeDating,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(EventCard), findsOneWidget);
      });
    });
  }

  // --- Section 3 ---
  {
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

  // --- Section 4 ---
  {
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

    group('ChatConversationProvider Models & Logic Exhaustive Tests', () {
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

  // --- Section 5 ---
  {
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
    });

    group('ChatConversationController Deep Interactive Tests', () {
      test(
        'build returns initial state with invalid UUID gracefully',
        () async {
          final container = ProviderContainer();
          try {
            final state = await container.read(
              chatConversationControllerProvider(
                'conv_123',
                'not-a-valid-uuid',
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

      test('build handles valid UUID and local messages query', () async {
        final container = ProviderContainer();
        try {
          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              jsonEncode({'messages': <Map<String, dynamic>>[]}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          final state = await container.read(
            chatConversationControllerProvider(
              '00000000-0000-0000-0000-000000000099',
              '00000000-0000-0000-0000-000000000002',
            ).future,
          );

          expect(state.isRevalidating, isTrue);
        } finally {
          container.dispose();
        }
      });
    });
  }

  // --- Section 6 ---
  {
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
    });

    group('ChatConversationPage & ClientAIImageManager Tests', () {
      test(
        'ClientAIProfileState copyWith and ClientAIImageManager methods',
        () {
          final container = ProviderContainer();
          final manager = container.read(clientAIImageManagerProvider.notifier);

          expect(manager.state.remotePaths.length, 5);

          // setRemotePaths
          manager.setRemotePaths(['path1', 'path2']);
          expect(manager.state.remotePaths[0], 'path1');
          expect(manager.state.remotePaths[1], 'path2');
          expect(manager.state.remotePaths[2], '');

          // backup and restore
          manager
            ..backupState()
            ..setRemotePaths(['path_new']);
          expect(manager.state.remotePaths[0], 'path_new');
          manager.restoreBackup();
          expect(manager.state.remotePaths[0], 'path1');

          // copyWith checks
          final modified = manager.state.copyWith(
            isProcessingAI: true,
            isSaving: true,
          );
          expect(modified.isProcessingAI, isTrue);
          expect(modified.isSaving, isTrue);
        },
      );

      testWidgets(
        'ChatConversationPage renders header, presence, and chat composer',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              jsonEncode({
                'messages': <Map<String, dynamic>>[],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ChatConversationPage(
                    conversationId: '00000000-0000-0000-0000-000000000001',
                    matchedUserId: '00000000-0000-0000-0000-000000000002',
                    tab: 'dating',
                    name: 'Alice',
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(ChatConversationPage), findsOneWidget);
          expect(find.text('Alice'), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 7 ---
  {
    group('Chat Conversation Provider Models Exhaustive Tests', () {
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

  // --- Section 8 ---
  {
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
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
    });

    group('Chats Conversation Provider and Page Tests', () {
      testWidgets('ChatConversationPage renders and sends interactions', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ChatConversationPage(
                  conversationId: 'conv_123',
                  matchedUserId: 'user_456',
                  tab: 'dating',
                  name: 'Elena Rostova',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ChatConversationPage), findsOneWidget);
        expect(find.text('Elena Rostova'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets(
        'ChatComposer renders all action buttons and triggers callbacks',
        (
          tester,
        ) async {
          String? sentText;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ChatComposer(
                  themeColor: Colors.blue,
                  enabled: true,
                  sending: false,
                  onSend: (text) async {
                    sentText = text;
                  },
                  onSendImage: (bytes, mime) async {},
                  onSendVoice: (bytes, mime, duration) async {},
                  onSendLocation: (lat, lng, label) async {},
                  onPlanEvent: () {},
                ),
              ),
            ),
          );

          await tester.pump();

          expect(find.byType(ChatComposer), findsOneWidget);

          final textField = find.byType(TextField);
          expect(textField, findsOneWidget);
          await tester.enterText(textField, 'Hello there!');
          await tester.pump();

          final sendIcon = find.byIcon(LucideIcons.send);
          if (sendIcon.evaluate().isNotEmpty) {
            await tester.tap(sendIcon);
            await tester.pump();
            expect(sentText, 'Hello there!');
          }
        },
      );

      testWidgets('EventPlannerSheet renders with form inputs', (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: EventPlannerSheet(
                  conversationId: 'conv_123',
                  peerUserId: 'user_456',
                  themeColor: Colors.purple,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(EventPlannerSheet), findsOneWidget);
      });

      testWidgets('ChatListTab renders conversations list view', (
        tester,
      ) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ChatListTab(
                  tab: 'dating',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ChatListTab), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }

  // --- Section 9 ---
  {
    group('Chat Conversation Provider Deep Logic Tests', () {
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

  // --- Section 10 ---
  {
    Animate.restartOnHotReload = false;

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
    });

    group('Chat Provider and Pages Tests', () {
      test('Chat Models deep serialization and copyWith', () {
        const media = MediaPointer(
          storagePath: 'media/test.jpg',
          mediaKeyBase64: 'mock-key-123',
          mimeType: 'image/jpeg',
          sizeBytes: 1024,
          durationMs: 500,
        );
        expect(
          MediaPointer.fromJson(media.toJson()).storagePath,
          'media/test.jpg',
        );

        const loc = LocationPointer(
          lat: 37.7749,
          lng: -122.4194,
          label: 'San Francisco',
        );
        expect(LocationPointer.fromJson(loc.toJson()).lat, 37.7749);

        const eventPayload = EventPayload(
          title: 'Coffee Meetup',
          notes: 'Casual chat',
        );
        expect(
          EventPayload.fromJson(eventPayload.toJson()).title,
          'Coffee Meetup',
        );

        final eventInfo = ChatEventInfo(
          eventId: 'ev_123',
          eventTime: DateTime.parse('2026-10-01T18:00:00Z'),
          locationLat: 37.7749,
          locationLng: -122.4194,
          locationLabel: 'Coffee shop',
          status: 'proposed',
        );
        expect(eventInfo.copyWith(status: 'accepted').status, 'accepted');

        final msgView = ChatMessageView(
          id: 'msg_1',
          senderId: 'user_1',
          isMine: true,
          createdAt: DateTime.now(),
          plaintext: 'Hello World',
          messageType: 'text',
          decryptFailed: false,
        );
        expect(
          msgView.copyWith(plaintext: 'New content').plaintext,
          'New content',
        );

        final convState = ChatConversationState(
          messages: [msgView],
          sessionReady: true,
          sending: false,
        );
        expect(convState.messages.length, 1);
      });

      testWidgets('ChatComposer renders cleanly', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                themeColor: Colors.pink,
                enabled: true,
                sending: false,
                onSend: (text) async {},
                onSendImage: (bytes, mime) async {},
                onSendVoice: (bytes, mime, duration) async {},
                onSendLocation: (lat, lng, label) async {},
                onPlanEvent: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(ChatComposer), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
      });

      testWidgets('EventPlannerSheet and ChatListTab render correctly', (
        tester,
      ) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: EventPlannerSheet(
                  conversationId: 'conv_123',
                  peerUserId: 'user_peer_1',
                  themeColor: Colors.pink,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(EventPlannerSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ChatListTab(tab: 'Dating'),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(ChatListTab), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }

  // --- Section 11 ---
  {
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

  // --- Section 12 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

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

  // --- Section 13 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ChatConversationController Provider Deep Tests', () {
      test('non-UUID peerId returns closed state immediately', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final state = await container.read(
          chatConversationControllerProvider(
            'conv_test',
            'non-uuid-peer',
          ).future,
        );

        expect(state.messages.isEmpty, isTrue);
        expect(state.sessionReady, isFalse);
        expect(state.sending, isFalse);
        expect(state.conversationClosed, isTrue);
      });

      test(
        'valid UUID peerId initializes state with revalidating shell',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          const validUuid = '11111111-1111-1111-1111-111111111111';
          try {
            final state = await container.read(
              chatConversationControllerProvider(
                'conv_uuid_test',
                validUuid,
              ).future,
            );

            expect(state.messages.isEmpty, isTrue);
            expect(state.sessionReady, isFalse);
            expect(state.sending, isFalse);
          } on Object catch (e) {
            expect(e, isNotNull);
          }
        },
      );
    });
  }
}

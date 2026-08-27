import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:nexus/features/chats/widgets/event_card.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
import 'package:nexus/features/chats/widgets/location_message_bubble.dart';
import 'package:nexus/features/chats/widgets/location_picker_sheet.dart';
import 'package:nexus/features/chats/widgets/new_chat_sheet.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

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
      expect(find.byType(NewChatSheet), findsOneWidget);
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

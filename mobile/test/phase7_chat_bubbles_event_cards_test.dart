import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/widgets/event_card.dart';
import 'package:nexus/features/chats/widgets/location_message_bubble.dart';
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

  group('LocationMessageBubble Widget Tests', () {
    testWidgets(
      'renders LocationMessageBubble with pin coordinates and label',
      (tester) async {
        const pointer = LocationPointer(
          lat: 37.7749,
          lng: -122.4194,
          label: 'Blue Bottle Coffee',
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  LocationMessageBubble(
                    pointer: pointer,
                    isMine: true,
                  ),
                  LocationMessageBubble(
                    pointer: pointer,
                    isMine: false,
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(LocationMessageBubble), findsNWidgets(2));
        expect(find.text('Blue Bottle Coffee'), findsNWidgets(2));
      },
    );
  });

  group('EventCard Widget Tests', () {
    testWidgets('renders EventCard with event title, datetime, and status', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const payload = EventPayload(
        title: 'Dinner & Astronomy Talk',
        notes: 'Meet outside the planetarium at 7pm.',
      );

      final eventInfo = ChatEventInfo(
        eventId: 'event_1',
        eventTime: DateTime(2026, 9, 15, 19),
        locationLat: 34.1184,
        locationLng: -118.3004,
        locationLabel: 'Griffith Observatory',
        status: 'pending',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: EventCard(
                    payload: payload,
                    eventInfo: eventInfo,
                    conversationId: 'conv_123',
                    peerUserId: 'user_bob',
                    themeColor: AppColors.modeDating,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EventCard), findsOneWidget);
      expect(find.text('Dinner & Astronomy Talk'), findsOneWidget);
      expect(find.text('Griffith Observatory'), findsOneWidget);
      expect(find.text('Meet outside the planetarium at 7pm.'), findsOneWidget);
    });
  });
}

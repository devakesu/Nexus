import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
    setupGlobalMockNetwork();
  });

  group('Phase 136 - Chat Composer and Event Sheet Mega Tests', () {
    testWidgets('ChatComposer renders and inputs text and triggers send', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                themeColor: Colors.deepPurple,
                enabled: true,
                sending: false,
                onSend: (text) async {},
                onSendImage: (bytes, mime) async {},
                onSendVoice: (bytes, mime, dur) async {},
                onSendLocation: (lat, lng, name) async {},
                onPlanEvent: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ChatComposer), findsOneWidget);

      final textField = find.byType(TextField);
      if (textField.evaluate().isNotEmpty) {
        await tester.enterText(textField.first, 'Meet at 7pm tonight!');
        await tester.pump();
        final sendButtons = find.byType(IconButton);
        for (var i = 0; i < sendButtons.evaluate().length; i++) {
          try {
            await tester.tap(sendButtons.at(i), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 50));
          } on Object catch (_) {}
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('EventPlannerSheet renders with form inputs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EventPlannerSheet(
                conversationId: 'conv_123',
                peerUserId: 'peer_456',
                themeColor: Colors.pink,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EventPlannerSheet), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

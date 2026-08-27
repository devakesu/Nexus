import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  group('MessageBubble Exhaustive Mega Tests', () {
    testWidgets('renders outgoing text message bubble', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final msg = ChatMessageView(
        id: 'msg-1',
        senderId: '00000000-0000-0000-0000-000000000001',
        isMine: true,
        createdAt: DateTime(2026, 1, 1, 14, 30),
        messageType: 'text',
        plaintext: 'Hello from Nexus!',
        decryptFailed: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: msg,
              themeColor: AppColors.modeDating,
              conversationId: 'conv-1',
              peerUserId: 'user-2',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MessageBubble), findsOneWidget);
      expect(find.text('Hello from Nexus!'), findsOneWidget);
      expect(find.text('2:30 PM'), findsOneWidget);
    });

    testWidgets('renders security alert bubble and triggers callback on tap', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var securityAlertTapped = false;

      final msg = ChatMessageView(
        id: 'msg-2',
        senderId: '00000000-0000-0000-0000-000000000002',
        isMine: false,
        createdAt: DateTime(2026, 1, 1, 15, 45),
        messageType: 'security_alert',
        plaintext: 'Security code changed. Tap to verify.',
        decryptFailed: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: msg,
              themeColor: AppColors.modeDating,
              conversationId: 'conv-1',
              peerUserId: 'user-2',
              onSecurityAlertTapped: () {
                securityAlertTapped = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MessageBubble), findsOneWidget);
      expect(
        find.text('Security code changed. Tap to verify.'),
        findsOneWidget,
      );

      // Tap on security alert bubble
      await tester.tap(find.text('Security code changed. Tap to verify.'));
      await tester.pump();
      expect(securityAlertTapped, isTrue);
    });
  });
}

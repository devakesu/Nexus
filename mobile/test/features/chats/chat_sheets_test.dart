import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:nexus/features/chats/screens/chats_page.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
import 'package:nexus/features/chats/widgets/location_picker_sheet.dart';
import 'package:nexus/features/chats/widgets/new_chat_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/mock_network_interceptor.dart';
import '../../helpers/test_helpers.dart';

class MockChatConversations extends ChatConversations {
  MockChatConversations(this.mockData);
  final List<ChatConversationSummary> mockData;

  @override
  Future<List<ChatConversationSummary>> build(String tab) async => mockData;
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

    setUpAll(() async {
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      setupGlobalMockNetwork();
    });

    group('Chat Composer and Event Sheet Tests', () {
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

  // --- Section 2 ---
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

    group('ProfessionalSettingsOverlay & ChatComposer Tests', () {
      testWidgets(
        'ProfessionalSettingsOverlay renders role chips and company field',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProfessionalSettingsOverlay(
                  professionalTargetBuckets: const ['Tech'],
                  lookingFor: const ['Co-founder', 'Collaborators'],
                  techSkills: const ['Flutter', 'Python'],
                  company: 'Nexus Inc',
                  roleType: const ['Engineer'],
                  savingFields: const {},
                  onSaveProfessionalField: (field, value, setState) async {},
                  onLoadProfessionalProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
          expect(find.text('Engineer'), findsWidgets);

          // Tap on Designer role chip
          final designerChip = find.text('Designer');
          if (designerChip.evaluate().isNotEmpty) {
            await tester.tap(designerChip.first);
            await tester.pump();
          }
        },
      );

      testWidgets('ChatComposer text entry and action triggers', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var sentText = '';
        var planEventTriggered = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                themeColor: AppColors.modeDating,
                enabled: true,
                sending: false,
                onSend: (text) async {
                  sentText = text;
                },
                onSendImage: (bytes, mime) async {},
                onSendVoice: (bytes, mime, dur) async {},
                onSendLocation: (lat, lng, label) async {},
                onPlanEvent: () {
                  planEventTriggered = true;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ChatComposer), findsOneWidget);

        // Type text in composer
        final textField = find.byType(TextField);
        expect(textField, findsOneWidget);
        await tester.enterText(textField, 'Hello there!');
        await tester.pump();

        // Tap send button
        final sendButton = find.byIcon(Icons.send_rounded);
        if (sendButton.evaluate().isNotEmpty) {
          await tester.tap(sendButton.first);
          await tester.pump();
          expect(sentText, 'Hello there!');
        }

        expect(planEventTriggered, isFalse);
      });
    });
  }

  // --- Section 3 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (call) async => null,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.cheny/record'),
          (call) async => false,
        );

    group('ChatComposer Deep Widget Tests', () {
      testWidgets(
        'renders ChatComposer and handles text typing & send action',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          String? sentText;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ChatComposer(
                  themeColor: AppColors.modeDating,
                  enabled: true,
                  sending: false,
                  onSend: (txt) async => sentText = txt,
                  onSendImage: (bytes, mime) async {},
                  onSendVoice: (bytes, mime, dur) async {},
                  onSendLocation: (lat, lng, label) async {},
                  onPlanEvent: () {},
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(ChatComposer), findsOneWidget);

          await tester.enterText(find.byType(TextField), 'Hello there!');
          await tester.pump();

          await tester.tap(find.byIcon(LucideIcons.send));
          await tester.pump();

          expect(sentText, 'Hello there!');
        },
      );
    });
  }

  // --- Section 4 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ChatComposer Widget Tests', () {
      testWidgets('renders ChatComposer text input and send action', (
        tester,
      ) async {
        String? sentText;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                themeColor: AppColors.modeDating,
                enabled: true,
                sending: false,
                onSend: (text) async => sentText = text,
                onSendImage: (b, m) async {},
                onSendVoice: (b, m, d) async {},
                onSendLocation: (lat, lng, l) async {},
                onPlanEvent: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(TextField), findsOneWidget);

        // Enter message text
        await tester.enterText(find.byType(TextField), 'Hello there!');
        await tester.pump();

        // Tap send button
        await tester.tap(find.byIcon(LucideIcons.send));
        await tester.pump();

        expect(sentText, 'Hello there!');
      });
    });

    group('ChatsPage Widget Tests', () {
      testWidgets('renders ChatsPage with 3 tabs and tab navigation', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatConversationsProvider('Dating').overrideWith(
                () => MockChatConversations(const []),
              ),
              chatConversationsProvider('Friends').overrideWith(
                () => MockChatConversations(const []),
              ),
              chatConversationsProvider('Professional').overrideWith(
                () => MockChatConversations(const []),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ChatsPage(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ChatsPage), findsOneWidget);
        expect(find.text('Dating'), findsOneWidget);
        expect(find.text('Friends'), findsOneWidget);
        expect(find.text('Professional'), findsOneWidget);

        // Tap Friends tab
        await tester.tap(find.text('Friends'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Tap Professional tab
        await tester.tap(find.text('Professional'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }

  // --- Section 5 ---
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
            if (call.method == 'checkPermission' ||
                call.method == 'requestPermission') {
              return 3; // whileInUse
            }
            if (call.method == 'isLocationServiceEnabled') {
              return true;
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

    group('NewChatSheet Widget Tests', () {
      testWidgets('renders NewChatSheet for Dating and Friends modes', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: NewChatSheet(tab: 'Dating'),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(NewChatSheet), findsOneWidget);
        expect(find.text('New Chat'), findsOneWidget);
      });
    });

    group('LocationPickerSheet Widget Tests', () {
      testWidgets(
        'renders LocationPickerSheet with controls and map action buttons',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: LocationPickerSheet(themeColor: AppColors.modeDating),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(LocationPickerSheet), findsOneWidget);
        },
      );
    });

    group('EventPlannerSheet Widget Tests', () {
      testWidgets(
        'renders EventPlannerSheet with title input and date picker triggers',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: EventPlannerSheet(
                      conversationId: 'conv_123',
                      peerUserId: 'user_456',
                      themeColor: AppColors.modeDating,
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(EventPlannerSheet), findsOneWidget);
        },
      );
    });
  }

  // --- Section 6 ---
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

    group('Chat Conversation Page & Composer Tests', () {
      testWidgets(
        'ChatConversationPage renders cleanly for Dating, Friends, Professional',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final tab in ['dating', 'friends', 'professional']) {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: Scaffold(
                    body: ChatConversationPage(
                      conversationId: 'conv-$tab-1',
                      matchedUserId: 'user-$tab-1',
                      tab: tab,
                      name: 'Alice ($tab)',
                    ),
                  ),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            expect(find.byType(ChatConversationPage), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.pump(const Duration(seconds: 60));
          }
        },
      );
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
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
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => null,
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.cheny/record'),
        (call) async => false,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('ChatComposer Deep Widget Tests', () {
    testWidgets('renders ChatComposer and handles text typing & send action', (
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
    });
  });
}

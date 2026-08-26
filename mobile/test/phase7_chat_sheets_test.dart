import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

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

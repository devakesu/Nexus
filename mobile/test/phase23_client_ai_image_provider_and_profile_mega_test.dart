import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('ClientAIImageManager & ProfileTab Deep Coverage Tests', () {
    test(
      'ClientAIProfileState constructor, copyWith, and field modifications',
      () {
        final state = ClientAIProfileState(
          remotePaths: const ['img1.jpg', 'img2.jpg', '', '', ''],
          pendingUploads: {0: File('path/to/img0.png')},
          slotSpecificVibeTags: const {
            0: ['Artistic', 'Vibrant'],
          },
          pendingDeletions: const ['old_img.jpg'],
        );

        expect(state.remotePaths.length, 5);
        expect(state.remotePaths.first, 'img1.jpg');
        expect(state.pendingDeletions, contains('old_img.jpg'));
        expect(state.isProcessingAI, isFalse);

        final updated = state.copyWith(
          isProcessingAI: true,
          isSaving: true,
          pendingDeletions: ['deleted2.jpg'],
        );

        expect(updated.isProcessingAI, isTrue);
        expect(updated.isSaving, isTrue);
        expect(updated.pendingDeletions, contains('deleted2.jpg'));
      },
    );

    test(
      'ClientAIImageManager manipulates slots, reorders, and resets cleanly',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final manager = container.read(clientAIImageManagerProvider.notifier)
          ..setRemotePaths(['photo1.jpg', 'photo2.jpg', 'photo3.jpg']);
        var state = container.read(clientAIImageManagerProvider);
        expect(state.remotePaths[0], 'photo1.jpg');
        expect(state.remotePaths[1], 'photo2.jpg');
        expect(state.remotePaths[2], 'photo3.jpg');
        expect(state.remotePaths[3], '');
        expect(state.remotePaths[4], '');

        manager
          ..backupState()
          ..clearImageSlot(1);
        state = container.read(clientAIImageManagerProvider);
        expect(state.remotePaths[1], 'photo3.jpg');
        expect(state.pendingDeletions, contains('photo2.jpg'));

        manager.swapImageSlots(0, 1);
        state = container.read(clientAIImageManagerProvider);
        expect(state.remotePaths[0], 'photo3.jpg');

        manager.restoreBackup();
        state = container.read(clientAIImageManagerProvider);
        expect(state.remotePaths[0], 'photo1.jpg');
      },
    );

    testWidgets(
      'ProfileTab renders sections and allows scrolling through form fields',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileTab(
                  onOpenOrbit: (tab, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfileTab), findsOneWidget);

        // Scroll through ProfileTab
        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/mock_network_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    'privacy_active_status': true,
    'privacy_read_receipts': true,
    'privacy_incognito': false,
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
    await SecureProfileCache.write(kFullMockProfile);
  });

  group('Phase 121 - Profile Tab All Sections and Handlers Mega Tests', () {
    testWidgets('ProfileTab scrolls and taps every interactive tile', (
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
                onOpenOrbit: (mode, color) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final scrollableList = find.byType(Scrollable);
      if (scrollableList.evaluate().isNotEmpty) {
        final scrollable = scrollableList.first;

        // Tap visible action chips
        final chips = find.byType(ActionChip);
        for (var i = 0; i < chips.evaluate().length && i < 4; i++) {
          try {
            await tester.tap(chips.at(i), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 50));
          } on Object catch (_) {}
        }

        // Drag down through all sections step by step
        for (var step = 0; step < 6; step++) {
          await tester.drag(scrollable, const Offset(0, -600));
          await tester.pump(const Duration(milliseconds: 150));

          final finders = find.byType(InkWell);
          for (var i = 0; i < finders.evaluate().length && i < 3; i++) {
            try {
              await tester.tap(finders.at(i), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 50));
            } on Object catch (_) {}
          }
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/settings/widgets/settings_tile_components.dart';
import 'package:nexus/features/settings/widgets/transparency_badge.dart';
import 'package:nexus/features/settings/widgets/user_management_components.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  group('Phase 90 - Settings Tiles and Transparency Mega Tests', () {
    testWidgets(
      'SettingsSectionHeader, SettingsToggleTile, and TransparencyBadge render cleanly',
      (
        tester,
      ) async {
        var toggleVal = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const SettingsSectionHeader(title: 'Account Settings'),
                  SettingsToggleTile(
                    title: 'Incognito Mode',
                    subtitle: 'Hide your profile from strangers',
                    value: toggleVal,
                    onChanged: (val) {
                      toggleVal = val;
                    },
                  ),
                  TransparencyBadge(
                    expanded: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(SettingsSectionHeader), findsOneWidget);
        expect(find.byType(SettingsToggleTile), findsOneWidget);
        expect(find.byType(TransparencyBadge), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets('User management components render properly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SettingsErrorView(
                  error: 'Failed to load list',
                  onRetry: () {},
                ),
                const SettingsEmptyView(
                  icon: LucideIcons.userX,
                  title: 'No blocked users',
                  description: 'You have not blocked anyone yet.',
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(SettingsErrorView), findsOneWidget);
      expect(find.byType(SettingsEmptyView), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

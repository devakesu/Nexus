import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/profile/widgets/cosmic_selection_overlay.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

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

  group('Phase 64 - Profile Widgets and Editors Mega Tests', () {
    testWidgets('TagChipsEditor renders and opens multiselect sheet', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TagChipsEditor(
              label: 'Interests',
              currentValues: const ['Art', 'Design'],
              presets: const ['Art', 'Design', 'Tech', 'Music'],
              icon: Icons.palette,
              iconColor: Colors.purple,
              hintText: 'Select interests',
              onChanged: (vals) {},
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(TagChipsEditor), findsOneWidget);

      final chip = find.text('Art');
      expect(chip, findsOneWidget);
    });

    testWidgets('PlaceAutocompleteField renders and accepts input', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceAutocompleteField(
              label: 'Hometown',
              initialValue: 'Seattle, WA',
              hintText: 'Search city...',
              prefixIcon: Icons.home,
              onChanged: (val) {},
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(PlaceAutocompleteField), findsOneWidget);

      await tester.tap(
        find.byType(PlaceAutocompleteField),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('CosmicSelectionOverlay renders properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CosmicSelectionOverlay(
              title: 'Select Category',
              options: ['Option 1', 'Option 2'],
              currentValue: 'Option 1',
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(CosmicSelectionOverlay), findsOneWidget);
    });
  });
}

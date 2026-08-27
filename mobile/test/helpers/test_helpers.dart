import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mock_network_interceptor.dart';

final String kMockAuthSessionJson = jsonEncode({
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

/// Standard environment mock setup for Flutter tests.
void setUpTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Animate.restartOnHotReload = false;
  GoogleFonts.config.allowRuntimeFetching = false;
  ConsentCacheManager.safetyConsentGranted = true;
  ConsentCacheManager.specialCategoryConsentGranted = true;
  SharedPreferences.setMockInitialValues({
    'sb-mock-auth-token': kMockAuthSessionJson,
  });
  FlutterSecureStorage.setMockInitialValues({});
  setupGlobalMockNetwork();

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
        const MethodChannel('flutter_secure_screen'),
        (call) async => null,
      );

  setUp(() {
    Animate.restartOnHotReload = false;
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    SharedPreferences.setMockInitialValues({
      'sb-mock-auth-token': kMockAuthSessionJson,
    });
    FlutterSecureStorage.setMockInitialValues({});
    setupGlobalMockNetwork();
  });
}

/// Initializes mock Supabase instance if not already initialized.
Future<void> initMockSupabase() async {
  try {
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      publishableKey: 'mock-anon-key',
    );
  } on Exception catch (_) {}
}

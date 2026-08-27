import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
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
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('LocalKeyVault Unit Tests', () {
    test('encrypts and decrypts byte payloads accurately', () async {
      final vault = LocalKeyVault.instance;
      final sample = Uint8List.fromList(
        utf8.encode('SecretSignalVaultData123'),
      );

      final encrypted = await vault.encryptBytes(sample);
      expect(encrypted, isNot(equals(sample)));

      final decrypted = await vault.decryptBytes(encrypted);
      expect(utf8.decode(decrypted), equals('SecretSignalVaultData123'));

      await vault.wipeKeys();
    });
  });

  group('SignalDatabase Custom Queries & Reset Tests', () {
    test('clearAllData runs without errors', () async {
      final db = SignalDatabase.instance;
      await db.clearAllData();
      expect(db.schemaVersion, equals(2));
    });
  });

  group('SignalKeyService Deep Tests', () {
    test('instance properties and wipeLocalData', () async {
      final service = SignalKeyService.instance;
      expect(service, isNotNull);
      expect(service.isNewLocalIdentity, isFalse);

      await service.wipeLocalData();
    });

    test(
      'ensureBootstrappedInBackground handles 404 and unexpected errors gracefully',
      () async {
        final service = SignalKeyService.instance;

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            '{"detail": "User not onboarded"}',
            404,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        // Does not throw
        await service.ensureBootstrappedInBackground();
      },
    );
  });
}

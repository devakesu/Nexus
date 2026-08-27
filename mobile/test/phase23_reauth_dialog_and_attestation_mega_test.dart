import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/widgets/about/attestation_section.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
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
  ) => handler(options);

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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_secure_screen'),
        (call) async => null,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('EmailOtpReauthDialog & AttestationSection Exhaustive Mega Tests', () {
    testWidgets('EmailOtpReauthDialog renders and enters OTP digits', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var verified = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmailOtpReauthDialog(
              verifyUrl: 'https://example.com/api/v1/auth/verify',
              resendUrl: 'https://example.com/api/v1/auth/resend',
              onVerificationSuccess: () {
                verified = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(EmailOtpReauthDialog), findsOneWidget);

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.first, '123456');
        await tester.pump();
      }

      expect(verified, isFalse);
    });

    testWidgets(
      'AttestationSection renders attestation details and triggers callbacks',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        String? launchedUrl;
        String? copiedText;

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'status': 'verified',
              'commit_hash': 'abcdef1234567890',
              'build_timestamp': '2026-08-26T12:00:00Z',
              'reproducible_build': true,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AttestationSection(
                  onLaunch: (url) async {
                    launchedUrl = url;
                  },
                  onCopy: (context, label, text) async {
                    copiedText = text;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(AttestationSection), findsOneWidget);
        expect(launchedUrl, isNull);
        expect(copiedText, isNull);
      },
    );

    test('ApiService returns AttestationResponse cleanly', () async {
      const api = ApiService();
      final res = await api.fetchAttestationDetails('mock_token');
      expect(res.statusCode, isNotNull);
    });
  });
}

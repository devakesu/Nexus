import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/navigation/app_router.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class _TrackingRequestHandler extends RequestInterceptorHandler {
  _TrackingRequestHandler(this.onNext);
  final VoidCallback onNext;

  @override
  void next(RequestOptions requestOptions) {
    onNext();
  }
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

  group('ErrorHandler Deep Tests', () {
    test('sanitize redacts emails, tokens, phone numbers, and keys', () {
      const input =
          'User john.doe@example.com logged in with bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.doNotLeakThis '
          'phone +14155552671 and media_key_base64: dGVzdGtleTEyMzQ1Njc4';

      final sanitized = ErrorHandler.sanitize(input);
      expect(sanitized, contains('[EMAIL_REDACTED]'));
      expect(sanitized, contains('[REDACTED_SENSITIVE]'));
      expect(sanitized, contains('[PHONE_REDACTED]'));
    });

    test('sanitize preserves support and app domain emails', () {
      const support = 'Contact support@nexus.app for assistance';
      final sanitized = ErrorHandler.sanitize(support);
      expect(sanitized, contains('support@nexus.app'));
    });

    test('isSensitiveKey identifies all sensitive credentials', () {
      expect(ErrorHandler.isSensitiveKey('bearer'), isTrue);
      expect(ErrorHandler.isSensitiveKey('token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('password'), isTrue);
      expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
      expect(ErrorHandler.isSensitiveKey('username'), isFalse);
    });

    test('sanitizeObject sanitizes nested maps and lists', () {
      final map = {
        'username': 'alice',
        'email': 'alice@example.com',
        'password': 'superSecretPassword123!',
        'details': {
          'token': 'secretJwtToken12345678',
          'phone': '+1 (555) 123-4567',
        },
        'items': ['token=secret12345678', 'normal item'],
      };

      final sanitized = ErrorHandler.sanitizeObject(map) as Map;
      expect(sanitized['password'], equals('[REDACTED_SENSITIVE]'));
      expect(
        (sanitized['details'] as Map)['token'],
        equals('[REDACTED_SENSITIVE]'),
      );
      expect(
        (sanitized['details'] as Map)['phone'],
        contains('[PHONE_REDACTED]'),
      );
      expect((sanitized['items'] as List)[0], contains('[REDACTED_SENSITIVE]'));
    });

    test(
      'getFriendlyMessage handles DioException, AuthException, and network strings',
      () {
        final dio401 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 401,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio401),
          equals('Session expired. Please sign in again.'),
        );

        final dio403 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 403,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio403),
          equals(
            'Access denied. You do not have permission to access this resource.',
          ),
        );

        final dio429 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 429,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio429),
          equals(
            'Too many requests. Please wait a moment before trying again.',
          ),
        );

        final dio500 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 500,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio500),
          equals('Server error (500). Please try again later.'),
        );

        const authOtp = AuthException('Invalid OTP code', code: 'otp_expired');
        expect(
          ErrorHandler.getFriendlyMessage(authOtp),
          contains('verification code you entered is invalid or has expired'),
        );

        const authGrant = AuthException('Bad login', code: 'invalid_grant');
        expect(
          ErrorHandler.getFriendlyMessage(authGrant),
          equals('Invalid login credentials. Please try again.'),
        );

        const authUserNotFound = AuthException(
          'Not found',
          code: 'user_not_found',
        );
        expect(
          ErrorHandler.getFriendlyMessage(authUserNotFound),
          equals('No account was found with those details.'),
        );

        final socketExp = Exception(
          'SocketException: OS Error: Connection refused',
        );
        expect(
          ErrorHandler.getFriendlyMessage(socketExp),
          contains('Network connection issue'),
        );
      },
    );

    test(
      'handleError executes for info, warning, error, and critical levels',
      () {
        ErrorHandler.handleError(
          'Info message',
          level: ErrorLevel.info,
          showUi: false,
        );

        ErrorHandler.handleError(
          'Warning message',
          level: ErrorLevel.warning,
          showUi: false,
        );

        ErrorHandler.handleError(
          Exception('Standard error'),
          showUi: false,
          stackTrace: StackTrace.current,
        );

        ErrorHandler.handleError(
          Exception('Critical crash'),
          level: ErrorLevel.critical,
          showUi: false,
        );
      },
    );
  });

  group('NetworkUtils and RateLimitInterceptor Tests', () {
    test('RateLimitInterceptor parseRetryAfter parses header with jitter', () {
      final headers = Headers.fromMap({
        'retry-after': ['10'],
      });

      final fixedRandom = Random(42);
      final duration = RateLimitInterceptor.parseRetryAfter(
        headers,
        random: fixedRandom,
      );
      expect(duration.inSeconds, greaterThanOrEqualTo(8));
      expect(duration.inSeconds, lessThanOrEqualTo(13));
    });

    test(
      'RateLimitInterceptor resetRateLimit and rateLimitedUntil getter/setter',
      () {
        RateLimitInterceptor.rateLimitedUntil = DateTime.now().add(
          const Duration(seconds: 30),
        );
        expect(RateLimitInterceptor.rateLimitedUntil, isNotNull);

        RateLimitInterceptor.resetRateLimit();
        expect(RateLimitInterceptor.rateLimitedUntil, isNull);
      },
    );

    test('CorrelationInterceptor adds X-Request-ID header', () {
      final interceptor = CorrelationInterceptor();
      final options = RequestOptions(path: '/api/v1/test');
      var nextCalled = false;

      final handler = _TrackingRequestHandler(() => nextCalled = true);
      interceptor.onRequest(options, handler);

      expect(options.headers['X-Request-ID'], isNotNull);
      expect(nextCalled, isTrue);
    });
  });

  group('AppRouter Route Definition Tests', () {
    test('goRouter defines initial routes and handles routing config', () {
      expect(goRouter, isNotNull);
      expect(goRouter.configuration.routes.isNotEmpty, isTrue);
    });
  });
}

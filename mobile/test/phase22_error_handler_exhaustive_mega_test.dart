import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ErrorHandler Exhaustive Mega Coverage Tests', () {
    test('sanitize redacts emails, tokens, phone numbers, and keys', () {
      // 1. Emails
      expect(
        ErrorHandler.sanitize('User john.doe@example.com logged in'),
        'User [EMAIL_REDACTED] logged in',
      );
      expect(
        ErrorHandler.sanitize('Contact support@nexus.app for help'),
        'Contact support@nexus.app for help',
      );

      // 2. Sensitive bearer & tokens
      expect(
        ErrorHandler.sanitize('bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'),
        'bearer: [REDACTED_SENSITIVE]',
      );
      expect(
        ErrorHandler.sanitize('token: abcdef1234567890'),
        'token: [REDACTED_SENSITIVE]',
      );
      expect(
        ErrorHandler.sanitize('password: SuperSecretPassword123'),
        'password: [REDACTED_SENSITIVE]',
      );

      // 3. JSON fields
      expect(
        ErrorHandler.sanitize('{"password": "secret_password_123"}'),
        '{"password": "[REDACTED_SENSITIVE]"}',
      );
      expect(
        ErrorHandler.sanitize('{"access_token": "token_12345678"}'),
        '{"access_token": "[REDACTED_SENSITIVE]"}',
      );

      // 4. Phone numbers
      expect(
        ErrorHandler.sanitize('Call +14155552671 or (555) 123-4567'),
        'Call [PHONE_REDACTED] or [PHONE_REDACTED]',
      );
    });

    test('isSensitiveKey identifies all sensitive parameter names', () {
      expect(ErrorHandler.isSensitiveKey('bearer'), isTrue);
      expect(ErrorHandler.isSensitiveKey('auth'), isTrue);
      expect(ErrorHandler.isSensitiveKey('token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('authorization'), isTrue);
      expect(ErrorHandler.isSensitiveKey('password'), isTrue);
      expect(ErrorHandler.isSensitiveKey('secret'), isTrue);
      expect(ErrorHandler.isSensitiveKey('jwt'), isTrue);
      expect(ErrorHandler.isSensitiveKey('access_token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('refresh_token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
      expect(ErrorHandler.isSensitiveKey('private_key'), isTrue);
      expect(ErrorHandler.isSensitiveKey('prekey'), isTrue);
      expect(ErrorHandler.isSensitiveKey('username'), isFalse);
      expect(ErrorHandler.isSensitiveKey('displayName'), isFalse);
    });

    test('sanitizeObject handles nested maps, lists, and primitives', () {
      final input = {
        'username': 'alice',
        'password': 'SuperSecretPassword123',
        'email': 'alice@domain.com',
        'items': ['token: abc12345678', 'normal_text'],
        'profile': {
          'jwt': 'secret_jwt_string_12345',
          'phone': '+14155552671',
        },
      };

      final sanitized = ErrorHandler.sanitizeObject(input) as Map;
      expect(sanitized['password'], '[REDACTED_SENSITIVE]');
      expect(sanitized['email'], '[EMAIL_REDACTED]');
      expect(sanitized['items'] is List, isTrue);
      expect((sanitized['profile'] as Map)['jwt'], '[REDACTED_SENSITIVE]');
    });

    test(
      'getFriendlyMessage handles DioExceptions, AuthExceptions, and clean strings',
      () {
        // 1. DioException status codes
        final dio401 = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 401,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio401),
          'Session expired. Please sign in again.',
        );

        final dio403 = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 403,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio403),
          'Access denied. You do not have permission to access this resource.',
        );

        final dio429 = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 429,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio429),
          'Too many requests. Please wait a moment before trying again.',
        );

        final dio500 = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 500,
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio500),
          'Server error (500). Please try again later.',
        );

        final dioDetail = DioException(
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/test'),
            statusCode: 400,
            data: {'detail': 'Custom validation failure'},
          ),
        );
        expect(
          ErrorHandler.getFriendlyMessage(dioDetail),
          'Custom validation failure',
        );

        // 2. AuthException
        const authOtp = AuthException('Token expired', code: 'otp_expired');
        expect(
          ErrorHandler.getFriendlyMessage(authOtp),
          'The verification code you entered is invalid or has expired. Please check and try again.',
        );

        const authInvalid = AuthException(
          'Invalid grant',
          code: 'invalid_grant',
        );
        expect(
          ErrorHandler.getFriendlyMessage(authInvalid),
          'Invalid login credentials. Please try again.',
        );

        const authUserNotFound = AuthException(
          'Not found',
          code: 'user_not_found',
        );
        expect(
          ErrorHandler.getFriendlyMessage(authUserNotFound),
          'No account was found with those details.',
        );

        // 3. String cleanup
        expect(
          ErrorHandler.getFriendlyMessage(
            Exception('Access denied: Profile is locked'),
          ),
          'Access denied: Profile is locked',
        );
        expect(
          ErrorHandler.getFriendlyMessage(
            null,
            'Exception: Account inactive (details)',
          ),
          'Account inactive',
        );
      },
    );

    test('ErrorHandler formats diagnostic details', () {
      final msg = ErrorHandler.getFriendlyMessage(
        Exception('Network socket error: socketexception'),
      );
      expect(
        msg,
        'Network connection issue. Please check your internet connection and try again.',
      );
    });
  });
}

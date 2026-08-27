import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/error_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ErrorHandler Exhaustive Mega Tests', () {
    test(
      'sanitize redacts emails, passwords, tokens, phone numbers, and keys',
      () {
        expect(
          ErrorHandler.sanitize('User email is test.user@example.com!'),
          contains('[EMAIL_REDACTED]'),
        );
        expect(
          ErrorHandler.sanitize('Reach out to support@nexus.test'),
          contains('support@nexus.test'),
        );

        expect(
          ErrorHandler.sanitize(
            'bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz',
          ),
          contains('[REDACTED_SENSITIVE]'),
        );

        expect(
          ErrorHandler.sanitize('{"password": "superSecretPassword123!"}'),
          contains('[REDACTED_SENSITIVE]'),
        );

        expect(
          ErrorHandler.sanitize('{"access_token": "token1234567890"}'),
          contains('[REDACTED_SENSITIVE]'),
        );

        expect(
          ErrorHandler.sanitize('Phone: +14155552671 and 9876543210'),
          contains('[PHONE_REDACTED]'),
        );
      },
    );

    test('isSensitiveKey identifies all security and auth tokens', () {
      expect(ErrorHandler.isSensitiveKey('bearer'), isTrue);
      expect(ErrorHandler.isSensitiveKey('authorization'), isTrue);
      expect(ErrorHandler.isSensitiveKey('password'), isTrue);
      expect(ErrorHandler.isSensitiveKey('secret'), isTrue);
      expect(ErrorHandler.isSensitiveKey('jwt'), isTrue);
      expect(ErrorHandler.isSensitiveKey('access_token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('refresh_token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
      expect(ErrorHandler.isSensitiveKey('aes_key'), isTrue);
      expect(ErrorHandler.isSensitiveKey('blind_index'), isTrue);
      expect(ErrorHandler.isSensitiveKey('otp_code'), isTrue);
      expect(ErrorHandler.isSensitiveKey('private_key'), isTrue);
      expect(ErrorHandler.isSensitiveKey('registration_lock'), isTrue);
      expect(ErrorHandler.isSensitiveKey('username'), isFalse);
      expect(ErrorHandler.isSensitiveKey('title'), isFalse);
    });

    test('sanitizeObject handles nested maps, lists, and sensitive values', () {
      final input = {
        'username': 'john_doe@example.com',
        'password': 'secret_password',
        'tokens': ['bearer eyJhbGciOi...', 'normal_string'],
        'meta': {
          'access_token': '1234567890abcdef',
          'nested_list': [
            {'otp_code': '123456'},
          ],
        },
      };

      final sanitized = ErrorHandler.sanitizeObject(input) as Map;
      expect(sanitized['password'], '[REDACTED_SENSITIVE]');
      expect(
        (sanitized['meta'] as Map)['access_token'],
        '[REDACTED_SENSITIVE]',
      );
      expect(sanitized['username'], contains('[EMAIL_REDACTED]'));
    });

    test('getFriendlyMessage parses Dio and custom errors correctly', () {
      final dio401 = DioException(
        requestOptions: RequestOptions(path: '/api/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/test'),
          statusCode: 401,
          data: {'detail': 'Session expired.'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(ErrorHandler.getFriendlyMessage(dio401), 'Session expired.');

      final dio500 = DioException(
        requestOptions: RequestOptions(path: '/api/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/test'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(
        ErrorHandler.getFriendlyMessage(dio500),
        contains('Server error (500)'),
      );
    });

    test(
      'handleError processes DioException, SocketException, and generic errors',
      () {
        // Generic exception
        ErrorHandler.handleError(
          Exception('Standard test exception'),
          customMessage: 'Failed during test',
          level: ErrorLevel.warning,
          showUi: false,
        );

        // Socket exception (connection error)
        const socketError = SocketException('Connection refused');
        ErrorHandler.handleError(
          socketError,
          level: ErrorLevel.info,
          showUi: false,
        );

        // DioException with 401
        final dio401 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 401,
            data: {'detail': 'Session expired'},
          ),
          type: DioExceptionType.badResponse,
        );
        ErrorHandler.handleError(dio401, showUi: false);

        // DioException with 404
        final dio404 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 404,
            data: {'detail': 'Resource not found'},
          ),
          type: DioExceptionType.badResponse,
        );
        ErrorHandler.handleError(dio404, showUi: false);

        // DioException with 500
        final dio500 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 500,
            data: {'detail': 'Internal server error'},
          ),
          type: DioExceptionType.badResponse,
        );
        ErrorHandler.handleError(dio500, showUi: false);

        // DioException connection timeout
        final dioTimeout = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          type: DioExceptionType.connectionTimeout,
        );
        ErrorHandler.handleError(dioTimeout, showUi: false);
      },
    );
  });
}

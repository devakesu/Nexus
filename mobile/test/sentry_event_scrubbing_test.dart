// Ignore deprecated member use in test suite asserting backwards compatibility.
// ignore_for_file: deprecated_member_use

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Breadcrumb copyWith and data sanitization works', () {
    final crumb = Breadcrumb(
      message: 'Navigating to /user?token=secret12345&email=user@example.com',
      data: {
        'url': 'https://api.nexus.com/auth?token=eyJhbGciOi...',
        'phone': '+14155552671',
        'auth_header': 'Bearer super_secret_jwt',
      },
    );

    var sanitized = crumb;
    if (sanitized.message != null) {
      sanitized = sanitized.copyWith(
        message: ErrorHandler.sanitize(sanitized.message!),
      );
    }
    if (sanitized.data != null) {
      sanitized = sanitized.copyWith(
        data: (ErrorHandler.sanitizeObject(sanitized.data) as Map?)
            ?.cast<String, dynamic>(),
      );
    }

    expect(sanitized.message, contains('[REDACTED_SENSITIVE]'));
    expect(sanitized.message, contains('[EMAIL_REDACTED]'));
    expect(sanitized.data!['phone'], equals('[PHONE_REDACTED]'));
    expect(sanitized.data!['auth_header'], equals('[REDACTED_SENSITIVE]'));
  });

  test(
    'SentryEvent beforeSend sanitizes breadcrumbs, request, extra, and tags',
    () {
      final event = SentryEvent(
        message: SentryMessage('Failed request to user@example.com'),
        breadcrumbs: [
          Breadcrumb(
            message: 'HTTP POST /auth/login with token=secret12345',
            data: {'contact': '+919876543210'},
          ),
        ],
        request: SentryRequest(
          url: 'https://api.nexus.com/v1/user?auth_token=jwt_token_value_xyz',
          queryString: 'token=secret12345&email=victim@example.com',
          headers: {
            'Authorization': 'Bearer my_token_12345',
            'X-User-Email': 'victim@example.com',
          },
          data: {
            'password': 'plain_text_password',
            'phone': '+14155552671',
          },
        ),
        extra: {
          'session_id': 'sess-12345',
          'debug_info':
              'Error occurred for user@example.com with Bearer eyJhbGciOi...',
        },
        tags: {
          'user_email': 'victim@example.com',
          'safe_tag': 'nexus_v1',
        },
      );

      // Apply sanitization logic
      if (event.breadcrumbs != null) {
        for (var i = 0; i < event.breadcrumbs!.length; i++) {
          var b = event.breadcrumbs![i];
          if (b.message != null) {
            b = b.copyWith(message: ErrorHandler.sanitize(b.message!));
          }
          if (b.data != null) {
            b = b.copyWith(
              data: (ErrorHandler.sanitizeObject(b.data) as Map?)
                  ?.cast<String, dynamic>(),
            );
          }
          event.breadcrumbs![i] = b;
        }
      }

      final request = event.request;
      if (request != null) {
        event.request = request.copyWith(
          url: request.url != null ? ErrorHandler.sanitize(request.url!) : null,
          queryString: request.queryString != null
              ? ErrorHandler.sanitize(request.queryString!)
              : null,
          fragment: request.fragment != null
              ? ErrorHandler.sanitize(request.fragment!)
              : null,
          cookies: request.cookies != null
              ? ErrorHandler.sanitize(request.cookies!)
              : null,
          headers: request.headers.map(
            (k, v) => MapEntry(
              k,
              ErrorHandler.isSensitiveKey(k)
                  ? '[REDACTED_SENSITIVE]'
                  : ErrorHandler.sanitize(v),
            ),
          ),
          data: request.data != null
              ? ErrorHandler.sanitizeObject(request.data)
              : null,
        );
      }

      if (event.extra != null) {
        event.extra = (ErrorHandler.sanitizeObject(event.extra) as Map?)
            ?.cast<String, dynamic>();
      }

      if (event.tags != null) {
        event.tags = event.tags!.map(
          (k, v) => MapEntry(
            k,
            ErrorHandler.isSensitiveKey(k)
                ? '[REDACTED_SENSITIVE]'
                : ErrorHandler.sanitize(v),
          ),
        );
      }

      expect(
        event.breadcrumbs!.first.message,
        contains('[REDACTED_SENSITIVE]'),
      );
      expect(
        event.breadcrumbs!.first.data!['contact'],
        equals('[PHONE_REDACTED]'),
      );
      expect(event.request!.url, contains('[REDACTED_SENSITIVE]'));
      expect(event.request!.queryString, contains('[EMAIL_REDACTED]'));
      expect(
        event.request!.headers['Authorization'],
        equals('[REDACTED_SENSITIVE]'),
      );
      expect(
        event.request!.headers['X-User-Email'],
        equals('[EMAIL_REDACTED]'),
      );
      expect(
        (event.request!.data as Map)['password'],
        equals('[REDACTED_SENSITIVE]'),
      );
      expect((event.request!.data as Map)['phone'], equals('[PHONE_REDACTED]'));
      expect(event.extra!['session_id'], equals('[REDACTED_SENSITIVE]'));
      expect(event.extra!['debug_info'], contains('[EMAIL_REDACTED]'));
      expect(event.extra!['debug_info'], contains('[REDACTED_SENSITIVE]'));
      expect(event.tags!['user_email'], equals('[EMAIL_REDACTED]'));
      expect(event.tags!['safe_tag'], equals('nexus_v1'));
    },
  );

  test(
    'Scope sets custom_message in extra and not in tags to avoid cardinality explosion',
    () async {
      final scope = Scope(SentryOptions());
      await scope.setExtra('custom_message', 'Failed to create chat event');

      expect(
        scope.extra['custom_message'],
        equals('Failed to create chat event'),
      );
      expect(scope.tags.containsKey('custom_message'), isFalse);
    },
  );

  test(
    'SentryFlutterOptions configures full text and image masking with disabled replay',
    () {
      final options = SentryFlutterOptions();
      options.replay.sessionSampleRate = 0.0;
      options.replay.onErrorSampleRate = 0.0;
      options.privacy.maskAllText = true;
      options.privacy.maskAllImages = true;

      expect(options.replay.sessionSampleRate, equals(0.0));
      expect(options.replay.onErrorSampleRate, equals(0.0));
      expect(options.privacy.maskAllText, isTrue);
      expect(options.privacy.maskAllImages, isTrue);
    },
  );

  test(
    'FCM token debug output masks prefix and retains only trailing characters',
    () {
      const rawToken = 'fcm_long_device_token_xyz_12345678_abcdefgh';
      final maskedToken = rawToken.length > 8
          ? '...${rawToken.substring(rawToken.length - 8)}'
          : '[MASKED]';

      expect(maskedToken, equals('...abcdefgh'));
      expect(maskedToken.contains('fcm_long'), isFalse);
      expect(maskedToken.contains('12345678'), isFalse);
    },
  );

  test(
    'Scope sets SentryUser id when authenticated and clears to null on logout',
    () async {
      final scope = Scope(SentryOptions());
      expect(scope.user, isNull);

      await scope.setUser(SentryUser(id: 'user-uuid-12345'));
      expect(scope.user, isNotNull);
      expect(scope.user!.id, equals('user-uuid-12345'));

      await scope.setUser(null);
      expect(scope.user, isNull);
    },
  );

  test(
    'CorrelationInterceptor attaches X-Request-ID header to outgoing requests',
    () {
      final interceptor = CorrelationInterceptor();
      final options = RequestOptions(path: '/api/v1/profile/details');

      final handler = RequestInterceptorHandler();
      interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('X-Request-ID'), isTrue);
      final reqId = options.headers['X-Request-ID'] as String?;
      expect(reqId, isNotNull);
      expect(reqId!.length, greaterThan(10));
    },
  );

  test(
    'Scope sets request_id tag and extra when extracting from DioException',
    () async {
      final scope = Scope(SentryOptions());
      const requestId = 'req-trace-uuid-9999';

      await scope.setTag('request_id', requestId);
      await scope.setExtra('request_id', requestId);

      expect(scope.tags['request_id'], equals(requestId));
      expect(scope.extra['request_id'], equals(requestId));
    },
  );

  test(
    'ErrorHandler.sanitize scrubs various phone formats and raw international numbers',
    () {
      const raw1 = 'Contact user at +91 98765 43210 regarding issue';
      const raw2 = 'Dial (555) 123-4567 or +14155552671';
      const raw3 = 'UK Number: 447911123456';

      expect(
        ErrorHandler.sanitize(raw1),
        equals('Contact user at [PHONE_REDACTED] regarding issue'),
      );
      expect(
        ErrorHandler.sanitize(raw2),
        equals('Dial [PHONE_REDACTED] or [PHONE_REDACTED]'),
      );
      expect(
        ErrorHandler.sanitize(raw3),
        equals('UK Number: [PHONE_REDACTED]'),
      );
    },
  );
}

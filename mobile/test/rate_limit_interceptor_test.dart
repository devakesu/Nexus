import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';

class _TestErrorHandler extends ErrorInterceptorHandler {
  DioException? lastError;

  @override
  void next(DioException err) {
    lastError = err;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(RateLimitInterceptor.resetRateLimit);

  tearDown(RateLimitInterceptor.resetRateLimit);

  test(
    'RateLimitInterceptor.parseRetryAfter parses Retry-After header with jitter',
    () {
      final headers = Headers.fromMap({
        'retry-after': ['10'],
      });

      final duration = RateLimitInterceptor.parseRetryAfter(headers);
      // 10 seconds with +/-20% jitter: 8.0s to 12.0s
      expect(duration.inMilliseconds, greaterThanOrEqualTo(8000));
      expect(duration.inMilliseconds, lessThanOrEqualTo(12000));
    },
  );

  test(
    'RateLimitInterceptor.parseRetryAfter falls back to default on missing/invalid header',
    () {
      final emptyHeaders = Headers();
      final duration = RateLimitInterceptor.parseRetryAfter(emptyHeaders);
      // 5 seconds default with +/-20% jitter: 4.0s to 6.0s
      expect(duration.inMilliseconds, greaterThanOrEqualTo(4000));
      expect(duration.inMilliseconds, lessThanOrEqualTo(6000));
    },
  );

  test(
    'RateLimitInterceptor.onError sets rate limit window on HTTP 429',
    () async {
      final interceptor = RateLimitInterceptor();
      final requestOptions = RequestOptions(
        path: '/api/v1/test',
        method: 'GET',
      );
      final response = Response<dynamic>(
        requestOptions: requestOptions,
        statusCode: 429,
        headers: Headers.fromMap({
          'retry-after': ['5'],
        }),
      );
      final error = DioException(
        requestOptions: requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );

      final handler = _TestErrorHandler();
      await interceptor.onError(error, handler);

      expect(handler.lastError, equals(error));
      expect(RateLimitInterceptor.rateLimitedUntil, isNotNull);
      final diff = RateLimitInterceptor.rateLimitedUntil!.difference(
        DateTime.now(),
      );
      expect(diff.inMilliseconds, greaterThan(3500));
    },
  );

  test(
    'RateLimitInterceptor.onRequest delays requests when active rate limit is set',
    () async {
      final interceptor = RateLimitInterceptor();
      final requestOptions = RequestOptions(
        path: '/api/v1/test',
        method: 'GET',
      );

      // Manually set 1 second rate limit window
      RateLimitInterceptor.rateLimitedUntil = DateTime.now().add(
        const Duration(milliseconds: 600),
      );

      final stopwatch = Stopwatch()..start();
      final handler = RequestInterceptorHandler();
      await interceptor.onRequest(requestOptions, handler);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(500));
    },
  );
}

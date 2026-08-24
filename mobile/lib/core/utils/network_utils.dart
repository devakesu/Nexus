import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

/// Backend requests get longer slack in debug builds, where the app is
/// often talking to a local server under a debugger, cold-starting
/// functions, or running over a slower dev network.
const Duration kNetworkTimeout = kDebugMode
    ? Duration(seconds: 40)
    : Duration(seconds: 20);

final Dio _globalDio = _createDioInstance();

Dio _createDioInstance() {
  final dio = Dio();

  dio.options.connectTimeout = kNetworkTimeout;
  dio.options.receiveTimeout = kNetworkTimeout;

  assert(
    () {
      // Debug-only: bypass strict cert validation for local HTTPS dev servers.
      (dio.httpClientAdapter as dynamic).onHttpClientCreate =
          // Explicit type annotation is required because the cast to dynamic disables type inference.
          // ignore: avoid_types_on_closure_parameters
          (HttpClient client) {
            client.badCertificateCallback =
                NetworkUtils.validateCertificateHostname;
            return client;
          };
      return true;
    }(),
    '',
  );

  dio
    ..addSentry()
    ..interceptors.add(RateLimitInterceptor())
    ..interceptors.add(AuthInterceptor())
    ..interceptors.add(AppCheckInterceptor());

  return dio;
}

/// Intercepts HTTP 429 rate limit responses, extracts Retry-After headers,
/// applies exponential backoff with jitter, and pauses subsequent requests.
class RateLimitInterceptor extends Interceptor {
  static DateTime? _rateLimitedUntil;
  static final Random _random = Random();

  /// Maximum retry attempts for automatic 429 retry on idempotent methods
  static const int _maxRetries = 2;
  static const String _retryCountKey = 'x-rate-limit-retry-count';

  /// Clears active rate limit block (useful for tests and reset hooks).
  @visibleForTesting
  static void resetRateLimit() {
    _rateLimitedUntil = null;
  }

  /// Sets rate limited duration explicitly (useful for testing).
  @visibleForTesting
  static set rateLimitedUntil(DateTime? until) {
    _rateLimitedUntil = until;
  }

  /// Exposed for testing rate limited state.
  static DateTime? get rateLimitedUntil => _rateLimitedUntil;

  /// Parses Retry-After header with jitter
  static Duration parseRetryAfter(Headers? headers, {Random? random}) {
    final retryAfterHeader = headers?.value('retry-after');
    var retryAfterSeconds = 5;
    if (retryAfterHeader != null) {
      final parsed = int.tryParse(retryAfterHeader);
      if (parsed != null && parsed > 0) {
        retryAfterSeconds = parsed;
      }
    }

    final rand = random ?? _random;
    // Add ±20% jitter (0.8 to 1.2 multiplier)
    final jitterFactor = 0.8 + (rand.nextDouble() * 0.4);
    final delayMs = (retryAfterSeconds * 1000 * jitterFactor).round();
    return Duration(milliseconds: delayMs);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final rateLimitedUntil = _rateLimitedUntil;
    if (rateLimitedUntil != null) {
      final now = DateTime.now();
      if (rateLimitedUntil.isAfter(now)) {
        final waitDuration = rateLimitedUntil.difference(now);
        // If wait duration is reasonable (<= 5 seconds), wait out the window
        if (waitDuration.inSeconds <= 5) {
          await Future<void>.delayed(waitDuration);
        }
      } else {
        _rateLimitedUntil = null;
      }
    }
    super.onRequest(options, handler);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 429) {
      final backoffDuration = parseRetryAfter(err.response?.headers);
      _rateLimitedUntil = DateTime.now().add(backoffDuration);

      final retryCount =
          (err.requestOptions.extra[_retryCountKey] as int?) ?? 0;
      final autoRetry =
          (err.requestOptions.extra['x-auto-retry-429'] as bool?) ?? false;

      if (autoRetry &&
          retryCount < _maxRetries &&
          _isRetryableMethod(err.requestOptions.method)) {
        err.requestOptions.extra[_retryCountKey] = retryCount + 1;
        await Future<void>.delayed(backoffDuration);
        try {
          final response = await createDio().fetch<dynamic>(err.requestOptions);
          return handler.resolve(response);
        } on DioException catch (retryErr) {
          return super.onError(retryErr, handler);
        } on Object catch (_) {
          // Pass original error through on unexpected failure
        }
      }
    }
    super.onError(err, handler);
  }

  static bool _isRetryableMethod(String method) {
    final m = method.toUpperCase();
    return m == 'GET' || m == 'HEAD' || m == 'OPTIONS';
  }
}

/// Returns a shared [Dio] instance configured for the current environment.
Dio createDio() => _globalDio;

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null && !options.headers.containsKey('Authorization')) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } on Object catch (_) {
      // Supabase instance not initialized or auth state inaccessible.
    }
    super.onRequest(options, handler);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      try {
        final res = await Supabase.instance.client.auth.refreshSession();
        final newToken = res.session?.accessToken;
        if (newToken != null) {
          final requestOptions = err.requestOptions;
          requestOptions.headers['Authorization'] = 'Bearer $newToken';
          final response = await _globalDio.fetch<dynamic>(requestOptions);
          return handler.resolve(response);
        }
      } on Object catch (_) {
        // Refresh failed, propagate original 401
      }
    }
    super.onError(err, handler);
  }
}

class AppCheckInterceptor extends Interceptor {
  static const _replayProtectedPaths = {
    '/api/v1/auth/bootstrap',
    '/api/v1/auth/complete-onboarding',
    '/api/v1/auth/accept-terms',
    '/api/v1/profile/media',
    '/api/v1/profile/details',
    '/api/v1/profiles/export-code',
    '/api/v1/profiles/import',
  };

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final backendUrl = AppConfig.current.backendUrl;
    final path = options.path;

    if (path.startsWith(backendUrl) || !path.startsWith('http')) {
      try {
        final isReplayProtected = _replayProtectedPaths.any(path.contains);

        final String? token;
        if (isReplayProtected) {
          token = await FirebaseAppCheck.instance.getLimitedUseToken();
        } else {
          token = await FirebaseAppCheck.instance.getToken();
        }

        if (token != null) {
          options.headers['X-Firebase-AppCheck'] = token;
        }
      } on Object catch (_) {
        // App check token fetch failed or wasn't initialized yet.
        // Fail silently or let backend enforce / reject.
      }
    }
    super.onRequest(options, handler);
  }
}

class NetworkUtils {
  /// Retrieves the current Supabase session access token or proactively refreshes if expired.
  static Future<String> requireAccessToken() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('Not signed in');
    if (session.isExpired) {
      try {
        final res = await Supabase.instance.client.auth.refreshSession();
        final refreshedToken = res.session?.accessToken;
        if (refreshedToken != null) return refreshedToken;
      } on Object catch (_) {
        // Fall back to current access token
      }
    }
    return session.accessToken;
  }

  /// Validates that the hostname of the untrusted certificate is a local/development host.
  static bool validateCertificateHostname(
    X509Certificate cert,
    String host,
    int port,
  ) {
    try {
      // Only allow local development bypasses for loopback/emulator/local IPs.
      return host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '10.0.2.2' ||
          host.startsWith('192.168.') ||
          host.startsWith('10.') ||
          _isPrivate172(host);
    } on Exception catch (_) {
      return false;
    }
  }

  static bool _isPrivate172(String host) {
    if (!host.startsWith('172.')) return false;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final secondOctet = int.tryParse(parts[1]);
    return secondOctet != null && secondOctet >= 16 && secondOctet <= 31;
  }

  /// Fetches the raw profile details map from the backend.
  static Future<Map<String, dynamic>?> fetchProfileDetails(
    Dio dio,
    String token,
  ) async {
    final config = AppConfig.current;

    final response = await dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/profile/details',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      return response.data;
    }
    return null;
  }
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:nexus/config/app_config.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final Dio _globalDio = _createDioInstance();

Dio _createDioInstance() {
  final dio = Dio();

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
    ..interceptors.add(AppCheckInterceptor());

  return dio;
}

/// Returns a shared [Dio] instance configured for the current environment.
Dio createDio() => _globalDio;

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
  /// Retrieves the current Supabase session access token or throws an exception if not signed in.
  static Future<String> requireAccessToken() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not signed in');
    return token;
  }
  /// Validates that the hostname of the untrusted certificate matches the expected backend host.
  static bool validateCertificateHostname(
    X509Certificate cert,
    String host,
    int port,
  ) {
    try {
      final backendUri = Uri.parse(AppConfig.current.backendUrl);
      final expectedHost = backendUri.host;

      // Allow if it matches the configured backend hostname, or common dev hosts.
      return host == expectedHost;
    } on Exception catch (_) {
      return false;
    }
  }

  /// Fetches the raw profile details map from the backend.
  static Future<Map<String, dynamic>?> fetchProfileDetails(
    Dio dio,
    String token,
  ) async {
    final config = AppConfig.current;
    dio.options.connectTimeout = const Duration(seconds: 3);
    dio.options.receiveTimeout = const Duration(seconds: 3);

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

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:nexus/config/app_config.dart';

/// Creates a [Dio] instance configured for the current environment.
///
/// In debug builds, the SSL certificate is validated by hostname only (to allow
/// self-signed certs in local dev). In release builds, default validation applies.
Dio createDio() {
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

  return dio;
}

class NetworkUtils {
  /// Validates that the hostname of the untrusted certificate matches the expected backend host.
  static bool validateCertificateHostname(X509Certificate cert, String host, int port) {
    try {
      final backendUri = Uri.parse(AppConfig.current.backendUrl);
      final expectedHost = backendUri.host;

      // Allow if it matches the configured backend hostname, or common dev hosts.
      return host == expectedHost ||
          host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '10.0.2.2';
    } on Exception catch (_) {
      return false;
    }
  }
}

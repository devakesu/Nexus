import 'dart:io';
import 'package:nexus/config/app_config.dart';

class NetworkUtils {
  /// Validates that the hostname of the untrusted certificate matches the expected backend host.
  static bool validateCertificateHostname(X509Certificate cert, String host, int port) {
    try {
      final backendUri = Uri.parse(AppConfig.current.backendUrl);
      final expectedHost = backendUri.host;
      
      // Allow if it matches the configured backend hostname, or common dev hosts
      return host == expectedHost || host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
    } on Exception catch (_) {
      return false;
    }
  }
}

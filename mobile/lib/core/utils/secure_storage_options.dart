import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Centralized, hardened secure storage configuration for the application.
class AppSecureStorage {
  AppSecureStorage._();

  static const IOSOptions iOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static const AndroidOptions aOptions = AndroidOptions.defaultOptions;

  /// Shared singleton instance with consistent security policies across all features.
  static const FlutterSecureStorage instance = FlutterSecureStorage(
    iOptions: iOptions,
  );
}

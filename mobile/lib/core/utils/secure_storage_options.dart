import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Centralized, hardened secure storage configuration for the application.
///
/// NOTE on iOS Keychain Accessibility:
/// - [iOptions] uses [KeychainAccessibility.first_unlock_this_device], allowing background
///   isolates (FCM push notification decrypter, WorkManager prekey replenish, evidence
///   upload retry) to access session tokens and DB keys when the app is backgrounded
///   following the initial device unlock.
/// - [strictIOptions] uses [KeychainAccessibility.unlocked_this_device] for high-security
///   foreground-only credentials that must never be accessible while the device is locked.
class AppSecureStorage {
  AppSecureStorage._();

  static const IOSOptions iOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static const IOSOptions strictIOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  static const AndroidOptions aOptions = AndroidOptions.defaultOptions;

  /// Shared singleton instance with consistent security policies across all features.
  static const FlutterSecureStorage instance = FlutterSecureStorage(
    iOptions: iOptions,
  );

  /// Strict singleton instance for foreground-only credentials.
  static const FlutterSecureStorage strictInstance = FlutterSecureStorage(
    iOptions: strictIOptions,
  );
}

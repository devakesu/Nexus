import 'package:nexus/core/utils/local_timed_cache.dart';

// AES-256 encrypted cache of the last-known /api/v1/profile/details
// response, backed by Android Keystore / iOS Keychain.

abstract final class SecureProfileCache {
  static const _cache = LocalTimedCache<Map<String, dynamic>>(
    storageKey: 'nexus_profile_cache',
    toJson: _identity,
    fromJson: _identity,
  );

  static Map<String, dynamic> _identity(Map<String, dynamic> val) => val;

  static Future<void> write(Map<String, dynamic> json) => _cache.write(json);

  static Future<Map<String, dynamic>?> read() => _cache.read();

  static Future<void> clear() => _cache.delete();
}

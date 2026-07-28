import 'package:nexus/core/utils/local_timed_cache.dart';

// AES-256 encrypted cache of the last-known discovery-hub snapshot
// (profile status + likes + matches) per mode, backed by Android Keystore /
// iOS Keychain - same protection level as secure_profile_cache.dart.

abstract final class DiscoveryHubCache {
  static String _key(String mode) => 'nexus_discovery_hub_cache_$mode';

  static LocalTimedCache<Map<String, dynamic>> _cacheFor(String mode) =>
      LocalTimedCache<Map<String, dynamic>>(
        storageKey: _key(mode),
        toJson: (map) => map,
        fromJson: (map) => map,
      );

  static Future<void> write(String mode, Map<String, dynamic> json) =>
      _cacheFor(mode).write(json);

  static Future<Map<String, dynamic>?> read(String mode) =>
      _cacheFor(mode).read();

  static Future<void> clear(String mode) => _cacheFor(mode).delete();

  static Future<void> clearAll() async {
    for (final mode in const ['dating', 'friends', 'professional']) {
      await clear(mode);
    }
  }
}

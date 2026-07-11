import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// AES-256 encrypted cache of the last-known discovery-hub snapshot
// (profile status + likes + matches) per mode, backed by Android Keystore /
// iOS Keychain - same protection level as secure_profile_cache.dart, since
// this data reveals social-graph info in the same sensitivity class as
// profile PII. Enables each discovery hub tab to render instantly from
// cache while DiscoveryHubController revalidates in the background.

const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

abstract final class DiscoveryHubCache {
  static String _key(String mode) => 'nexus_discovery_hub_cache_$mode';

  static Future<void> write(String mode, Map<String, dynamic> json) =>
      _secureStorage.write(key: _key(mode), value: jsonEncode(json));

  static Future<Map<String, dynamic>?> read(String mode) async {
    final raw = await _secureStorage.read(key: _key(mode));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      // Corrupted or stale-shape cache - fail safe as "no cache".
      return null;
    }
  }

  static Future<void> clear(String mode) =>
      _secureStorage.delete(key: _key(mode));

  static Future<void> clearAll() async {
    for (final mode in const ['dating', 'friends', 'professional']) {
      await clear(mode);
    }
  }
}

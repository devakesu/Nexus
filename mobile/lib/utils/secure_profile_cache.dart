import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// AES-256 encrypted cache of the last-known /api/v1/profile/details
// response, backed by Android Keystore / iOS Keychain - same protection
// level as secure_session_storage.dart, since profile data (name, bio,
// hometown, interests, etc.) is PII in the same sensitivity class as the
// auth session. Enables the profile page to render instantly from cache
// while it revalidates against the network in the background.

const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

abstract final class SecureProfileCache {
  static const _key = 'nexus_profile_cache';

  static Future<void> write(Map<String, dynamic> json) =>
      _secureStorage.write(key: _key, value: jsonEncode(json));

  static Future<Map<String, dynamic>?> read() async {
    final raw = await _secureStorage.read(key: _key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      // Corrupted or stale-shape cache (e.g. after an app update changed
      // fields) - fail safe as "no cache" rather than crashing.
      return null;
    }
  }

  static Future<void> clear() => _secureStorage.delete(key: _key);
}

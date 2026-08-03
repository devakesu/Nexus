import 'package:nexus/core/utils/local_timed_cache.dart';

// AES-256 encrypted cache of the last-known chats list per tab,
// backed by Android Keystore / iOS Keychain.

abstract final class ChatsCache {
  static String _key(String tab) => 'nexus_chats_cache_$tab';

  static final Map<String, LocalTimedCache<List<Map<String, dynamic>>>>
  _instances = {};

  static LocalTimedCache<List<Map<String, dynamic>>> _cacheFor(String tab) =>
      _instances.putIfAbsent(
        tab,
        () => LocalTimedCache<List<Map<String, dynamic>>>(
          storageKey: _key(tab),
          maxAge: const Duration(hours: 24),
          toJson: (list) => {'conversations': list},
          fromJson: (json) =>
              List<Map<String, dynamic>>.from(json['conversations'] as List),
        ),
      );

  static Future<void> write(String tab, List<Map<String, dynamic>> list) =>
      _cacheFor(tab).write(list);

  static Future<List<Map<String, dynamic>>?> read(String tab) =>
      _cacheFor(tab).read();

  static Future<void> clear(String tab) => _cacheFor(tab).delete();

  static Future<void> clearAll() async {
    for (final tab in const ['Dating', 'Friends', 'Professional']) {
      await clear(tab);
    }
  }
}

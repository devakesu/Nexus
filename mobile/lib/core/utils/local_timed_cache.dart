import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nexus/core/utils/secure_storage_options.dart';

const FlutterSecureStorage _secureStorage = AppSecureStorage.instance;

/// Generic AES-256 encrypted local cache utility for type-safe JSON caching.
class LocalTimedCache<T> {
  const LocalTimedCache({
    required this.storageKey,
    required this.toJson,
    required this.fromJson,
    this.maxAge,
  });

  final String storageKey;
  final Map<String, dynamic> Function(T value) toJson;
  final T Function(Map<String, dynamic> json) fromJson;
  final Duration? maxAge;

  Future<void> write(T value) async {
    final envelope = <String, dynamic>{
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': toJson(value),
    };
    final encoded = jsonEncode(envelope);
    await _secureStorage.write(key: storageKey, value: encoded);
  }

  Future<T?> read() async {
    final raw = await _secureStorage.read(key: storageKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map.containsKey('timestamp') && map.containsKey('data')) {
        final timestamp = map['timestamp'] as int?;
        if (maxAge != null && timestamp != null) {
          final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
          if (DateTime.now().difference(cachedTime) > maxAge!) {
            await delete();
            return null;
          }
        }
        final dataJson = map['data'] as Map<String, dynamic>;
        return fromJson(dataJson);
      }
      // Backward compatibility for raw json entries without envelope
      return fromJson(map);
    } on FormatException {
      return null;
    }
  }

  Future<void> delete() async {
    await _secureStorage.delete(key: storageKey);
  }
}

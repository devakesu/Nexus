import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Generic AES-256 encrypted local cache utility for type-safe JSON caching.
class LocalTimedCache<T> {
  const LocalTimedCache({
    required this.storageKey,
    required this.toJson,
    required this.fromJson,
  });

  final String storageKey;
  final Map<String, dynamic> Function(T value) toJson;
  final T Function(Map<String, dynamic> json) fromJson;

  Future<void> write(T value) async {
    final encoded = jsonEncode(toJson(value));
    await _secureStorage.write(key: storageKey, value: encoded);
  }

  Future<T?> read() async {
    final raw = await _secureStorage.read(key: storageKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return fromJson(map);
    } on FormatException {
      return null;
    }
  }

  Future<void> delete() async {
    await _secureStorage.delete(key: storageKey);
  }
}

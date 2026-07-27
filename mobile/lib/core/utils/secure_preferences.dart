import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A secure hardware-backed alternative to SharedPreferences using FlutterSecureStorage.
class SecurePreferences {
  SecurePreferences._();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static final SecurePreferences _instance = SecurePreferences._();

  /// Gets the singleton instance of SecurePreferences, matching the SharedPreferences API pattern.
  static Future<SecurePreferences> getInstance() async {
    return _instance;
  }

  /// Reads a String value from secure storage.
  Future<String?> getString(String key) async {
    return _storage.read(key: key);
  }

  /// Writes a String value to secure storage.
  Future<void> setString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// Reads a boolean value from secure storage.
  Future<bool?> getBool(String key) async {
    final val = await _storage.read(key: key);
    if (val == null) return null;
    return val == 'true';
  }

  /// Writes a boolean value to secure storage.
  Future<void> setBool(String key, {required bool value}) async {
    await _storage.write(key: key, value: value.toString());
  }

  /// Reads an integer value from secure storage.
  Future<int?> getInt(String key) async {
    final val = await _storage.read(key: key);
    if (val == null) return null;
    return int.tryParse(val);
  }

  /// Writes an integer value to secure storage.
  Future<void> setInt(String key, int value) async {
    await _storage.write(key: key, value: value.toString());
  }

  /// Reads a list of Strings from secure storage.
  Future<List<String>?> getStringList(String key) async {
    final val = await _storage.read(key: key);
    if (val == null) return null;
    try {
      final list = jsonDecode(val) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } on Object catch (_) {
      return null;
    }
  }

  /// Writes a list of Strings to secure storage.
  Future<void> setStringList(String key, List<String> value) async {
    await _storage.write(key: key, value: jsonEncode(value));
  }

  /// Removes a key from secure storage.
  Future<void> remove(String key) async {
    await _storage.delete(key: key);
  }

  /// Clears all keys from secure storage.
  Future<void> clear() async {
    await _storage.deleteAll();
  }
}

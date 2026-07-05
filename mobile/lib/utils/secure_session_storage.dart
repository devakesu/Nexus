import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// AES-256 encrypted session storage backed by Android Keystore / iOS Keychain.
// Replaces the default SharedPreferences-based storage used by supabase_flutter.

const _secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

class SecureLocalStorage extends LocalStorage {
  const SecureLocalStorage();

  static const _sessionKey = 'nexus_supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    final val = await _secureStorage.read(key: _sessionKey);
    return val != null;
  }

  @override
  Future<String?> accessToken() => _secureStorage.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() =>
      _secureStorage.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secureStorage.write(key: _sessionKey, value: persistSessionString);
}

// Secure async storage for PKCE code verifier (used when authFlowType = pkce).
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  const SecureGotrueAsyncStorage();

  static const _prefix = 'nexus_gotrue_';

  @override
  Future<String?> getItem({required String key}) =>
      _secureStorage.read(key: '$_prefix$key');

  @override
  Future<void> removeItem({required String key}) =>
      _secureStorage.delete(key: '$_prefix$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _secureStorage.write(key: '$_prefix$key', value: value);
}

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/app_refresh_notifier.dart';
import 'package:nexus/core/utils/chats_cache.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/encrypted_string.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/local_timed_cache.dart';
import 'package:nexus/core/utils/secure_preferences.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/core/utils/secure_session_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ConsentCacheManager.clear();
  });

  group('EncryptedString Tests', () {
    test('EncryptedString encrypts in RAM and decrypts during use', () async {
      final enc = await EncryptedString.create('secret_plain_text');
      expect(enc.isWiped, isFalse);

      final result = await enc.use((plain) {
        expect(plain, equals('secret_plain_text'));
        return 'success';
      });
      expect(result, equals('success'));

      enc.wipe();
      expect(enc.isWiped, isTrue);
      expect(() => enc.use((_) => 'should_fail'), throwsStateError);
    });
  });

  group('SecurePreferences Tests', () {
    test('SecurePreferences CRUD operations', () async {
      final prefs = await SecurePreferences.getInstance();

      // String
      expect(await prefs.getString('str_key'), isNull);
      await prefs.setString('str_key', 'hello_world');
      expect(await prefs.getString('str_key'), equals('hello_world'));

      // Bool
      expect(await prefs.getBool('bool_key'), isNull);
      await prefs.setBool('bool_key', value: true);
      expect(await prefs.getBool('bool_key'), isTrue);

      // Int
      expect(await prefs.getInt('int_key'), isNull);
      await prefs.setInt('int_key', 42);
      expect(await prefs.getInt('int_key'), equals(42));

      // StringList
      expect(await prefs.getStringList('list_key'), isNull);
      await prefs.setStringList('list_key', ['a', 'b', 'c']);
      expect(await prefs.getStringList('list_key'), equals(['a', 'b', 'c']));

      // Remove & Clear
      await prefs.remove('str_key');
      expect(await prefs.getString('str_key'), isNull);

      await prefs.clear();
      expect(await prefs.getBool('bool_key'), isNull);
      expect(await prefs.getInt('int_key'), isNull);
      expect(await prefs.getStringList('list_key'), isNull);
    });
  });

  group('LocalTimedCache Tests', () {
    test('LocalTimedCache writes and reads with envelope', () async {
      final cache = LocalTimedCache<Map<String, dynamic>>(
        storageKey: 'test_timed_cache_key',
        maxAge: const Duration(hours: 1),
        toJson: (v) => v,
        fromJson: (j) => j,
      );

      expect(await cache.read(), isNull);
      await cache.write({'status': 'active', 'count': 5});

      final readData = await cache.read();
      expect(readData, isNotNull);
      expect(readData!['status'], equals('active'));
      expect(readData['count'], equals(5));

      await cache.delete();
      expect(await cache.read(), isNull);
    });

    test('LocalTimedCache expires old cache entry', () async {
      final cache = LocalTimedCache<Map<String, dynamic>>(
        storageKey: 'test_expired_key',
        maxAge: const Duration(milliseconds: 1),
        toJson: (v) => v,
        fromJson: (j) => j,
      );

      await cache.write({'data': 'old'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await cache.read(), isNull);
    });
  });

  group('ChatsCache & DiscoveryHubCache & SecureProfileCache Tests', () {
    test('ChatsCache writes, reads, clears per tab and clearAll', () async {
      final testChatList = [
        {'id': 'conv_1', 'name': 'User One'},
        {'id': 'conv_2', 'name': 'User Two'},
      ];

      expect(await ChatsCache.read('Dating'), isNull);
      await ChatsCache.write('Dating', testChatList);
      final readChats = await ChatsCache.read('Dating');
      expect(readChats, isNotNull);
      expect(readChats!.length, equals(2));

      await ChatsCache.clear('Dating');
      expect(await ChatsCache.read('Dating'), isNull);

      await ChatsCache.write('Friends', testChatList);
      await ChatsCache.clearAll();
      expect(await ChatsCache.read('Friends'), isNull);
    });

    test(
      'DiscoveryHubCache writes, reads, clears per mode and clearAll',
      () async {
        final testData = <String, dynamic>{
          'likes_count': 10,
          'matches': <dynamic>[],
        };
        expect(await DiscoveryHubCache.read('dating'), isNull);
        await DiscoveryHubCache.write('dating', testData);
        final readData = await DiscoveryHubCache.read('dating');
        expect(readData, isNotNull);
        expect(readData!['likes_count'], equals(10));

        await DiscoveryHubCache.clear('dating');
        expect(await DiscoveryHubCache.read('dating'), isNull);

        await DiscoveryHubCache.write('friends', testData);
        await DiscoveryHubCache.clearAll();
        expect(await DiscoveryHubCache.read('friends'), isNull);
      },
    );

    test('SecureProfileCache writes, reads, and clears', () async {
      final profile = {'id': 'usr_123', 'name': 'Alice'};
      expect(await SecureProfileCache.read(), isNull);
      await SecureProfileCache.write(profile);
      expect(await SecureProfileCache.read(), isNotNull);
      await SecureProfileCache.clear();
      expect(await SecureProfileCache.read(), isNull);
    });
  });

  group('ConsentCacheManager Tests', () {
    test('ConsentCacheManager manages flags and clear', () {
      expect(ConsentCacheManager.safetyConsentGranted, isFalse);
      expect(ConsentCacheManager.specialCategoryConsentGranted, isFalse);

      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      expect(ConsentCacheManager.safetyConsentGranted, isTrue);
      expect(ConsentCacheManager.specialCategoryConsentGranted, isTrue);

      ConsentCacheManager.clear();
      expect(ConsentCacheManager.safetyConsentGranted, isFalse);
      expect(ConsentCacheManager.specialCategoryConsentGranted, isFalse);
    });
  });

  group('SecureSessionStorage Tests', () {
    test('SecureLocalStorage session handling', () async {
      const storage = SecureLocalStorage();
      await storage.initialize();
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);

      await storage.persistSession('sample_session_jwt');
      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), equals('sample_session_jwt'));

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
    });

    test('SecureGotrueAsyncStorage key-value operations', () async {
      const gotrueStorage = SecureGotrueAsyncStorage();
      expect(await gotrueStorage.getItem(key: 'pkce_verifier'), isNull);

      await gotrueStorage.setItem(key: 'pkce_verifier', value: 'verifier_xyz');
      expect(
        await gotrueStorage.getItem(key: 'pkce_verifier'),
        equals('verifier_xyz'),
      );

      await gotrueStorage.removeItem(key: 'pkce_verifier');
      expect(await gotrueStorage.getItem(key: 'pkce_verifier'), isNull);
    });
  });

  group('AppRefreshNotifier Tests', () {
    test(
      'AppRefreshNotifier and compatibility aliases broadcast events',
      () async {
        final orbitEvents = <bool>[];
        var profileEventsCount = 0;

        final orbitSub = AppRefreshNotifier.orbitStream.listen(orbitEvents.add);
        final profileSub = AppRefreshNotifier.profileStream.listen((_) {
          profileEventsCount++;
        });

        OrbitRefreshNotifier.notifyActivated();
        OrbitRefreshNotifier.notifyDeactivated();
        ProfileRefreshNotifier.notifyChanged();

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(orbitEvents, equals([true, false]));
        expect(profileEventsCount, equals(1));

        await orbitSub.cancel();
        await profileSub.cancel();
      },
    );
  });

  group('ErrorHandler Tests', () {
    test('sanitize redacts emails, tokens, and passwords', () {
      const raw =
          'User email is test.user@example.com and bearer token: abcdef1234567890 password: superSecretPassword';
      final sanitized = ErrorHandler.sanitize(raw);
      expect(sanitized, contains('[EMAIL_REDACTED]'));
      expect(sanitized, isNot(contains('test.user@example.com')));
      expect(sanitized, contains('[REDACTED_SENSITIVE]'));
      expect(sanitized, isNot(contains('superSecretPassword')));
    });

    test('sanitize preserves support@ emails and non-sensitive text', () {
      const text = 'Please contact support@devakesu.me for assistance.';
      final sanitized = ErrorHandler.sanitize(text);
      expect(sanitized, contains('support@devakesu.me'));
    });

    test('isSensitiveKey matches security keys', () {
      expect(ErrorHandler.isSensitiveKey('access_token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('refresh_token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('jwt'), isTrue);
      expect(ErrorHandler.isSensitiveKey('user_id'), isFalse);
      expect(ErrorHandler.isSensitiveKey('theme_mode'), isFalse);
    });

    test('sanitizeObject sanitizes maps, lists, and primitives', () {
      final input = <String, dynamic>{
        'username': 'alice',
        'password': 'secretPassword123',
        'tokens': ['bearer xyz12345678', 'public_info'],
        'nested': {
          'email': 'secret@domain.com',
          'access_token': 'top_secret',
        },
      };

      final sanitized = ErrorHandler.sanitizeObject(input) as Map;
      expect(sanitized['username'], equals('alice'));
      expect(sanitized['password'], equals('[REDACTED_SENSITIVE]'));
      expect((sanitized['nested'] as Map)['email'], equals('[EMAIL_REDACTED]'));
      expect(
        (sanitized['nested'] as Map)['access_token'],
        equals('[REDACTED_SENSITIVE]'),
      );
    });

    test('getFriendlyMessage returns meaningful error explanations', () {
      // Dio 401
      final dio401 = DioException(
        requestOptions: RequestOptions(path: '/api'),
        response: Response(
          requestOptions: RequestOptions(path: '/api'),
          statusCode: 401,
        ),
      );
      expect(
        ErrorHandler.getFriendlyMessage(dio401),
        contains('Session expired'),
      );

      // Dio 429
      final dio429 = DioException(
        requestOptions: RequestOptions(path: '/api'),
        response: Response(
          requestOptions: RequestOptions(path: '/api'),
          statusCode: 429,
        ),
      );
      expect(
        ErrorHandler.getFriendlyMessage(dio429),
        contains('Too many requests'),
      );

      // Dio 500
      final dio500 = DioException(
        requestOptions: RequestOptions(path: '/api'),
        response: Response(
          requestOptions: RequestOptions(path: '/api'),
          statusCode: 500,
        ),
      );
      expect(ErrorHandler.getFriendlyMessage(dio500), contains('Server error'));

      // AuthException
      const authOtpExpired = AuthException(
        'OTP code expired',
        code: 'otp_expired',
      );
      expect(
        ErrorHandler.getFriendlyMessage(authOtpExpired),
        contains('invalid or has expired'),
      );

      const authInvalidGrant = AuthException(
        'Invalid grant',
        code: 'invalid_grant',
      );
      expect(
        ErrorHandler.getFriendlyMessage(authInvalidGrant),
        contains('Invalid login credentials'),
      );
    });

    test('handleError executes without throwing', () {
      expect(
        () => ErrorHandler.handleError(
          Exception('Test non-fatal exception'),
          level: ErrorLevel.warning,
          showUi: false,
        ),
        returnsNormally,
      );
    });
  });
}

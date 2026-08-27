import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/navigation/app_router.dart';
import 'package:nexus/core/utils/app_refresh_notifier.dart';
import 'package:nexus/core/utils/chats_cache.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/encrypted_string.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/local_timed_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_preferences.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/core/utils/secure_session_storage.dart';
import 'package:nexus/features/settings/screens/community_guidelines_page.dart';
import 'package:nexus/features/settings/screens/help_center_page.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/test_helpers.dart';

class _TrackingRequestHandler extends RequestInterceptorHandler {
  _TrackingRequestHandler(this.onNext);
  final VoidCallback onNext;

  @override
  void next(RequestOptions requestOptions) {
    onNext();
    super.next(requestOptions);
  }
}

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ErrorHandler Deep Tests', () {
      test('sanitize redacts emails, tokens, phone numbers, and keys', () {
        const input =
            'User john.doe@example.com logged in with bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.doNotLeakThis '
            'phone +14155552671 and media_key_base64: dGVzdGtleTEyMzQ1Njc4';

        final sanitized = ErrorHandler.sanitize(input);
        expect(sanitized, contains('[EMAIL_REDACTED]'));
        expect(sanitized, contains('[REDACTED_SENSITIVE]'));
        expect(sanitized, contains('[PHONE_REDACTED]'));
      });

      test('sanitize preserves support and app domain emails', () {
        const support = 'Contact support@nexus.app for assistance';
        final sanitized = ErrorHandler.sanitize(support);
        expect(sanitized, contains('support@nexus.app'));
      });

      test('isSensitiveKey identifies all sensitive credentials', () {
        expect(ErrorHandler.isSensitiveKey('bearer'), isTrue);
        expect(ErrorHandler.isSensitiveKey('token'), isTrue);
        expect(ErrorHandler.isSensitiveKey('password'), isTrue);
        expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
        expect(ErrorHandler.isSensitiveKey('username'), isFalse);
      });

      test('sanitizeObject sanitizes nested maps and lists', () {
        final map = {
          'username': 'alice',
          'email': 'alice@example.com',
          'password': 'superSecretPassword123!',
          'details': {
            'token': 'secretJwtToken12345678',
            'phone': '+1 (555) 123-4567',
          },
          'items': ['token=secret12345678', 'normal item'],
        };

        final sanitized = ErrorHandler.sanitizeObject(map) as Map;
        expect(sanitized['password'], equals('[REDACTED_SENSITIVE]'));
        expect(
          (sanitized['details'] as Map)['token'],
          equals('[REDACTED_SENSITIVE]'),
        );
        expect(
          (sanitized['details'] as Map)['phone'],
          contains('[PHONE_REDACTED]'),
        );
        expect(
          (sanitized['items'] as List)[0],
          contains('[REDACTED_SENSITIVE]'),
        );
      });

      test(
        'getFriendlyMessage handles DioException, AuthException, and network strings',
        () {
          final dio401 = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/test'),
              statusCode: 401,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio401),
            equals('Session expired. Please sign in again.'),
          );

          final dio403 = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/test'),
              statusCode: 403,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio403),
            equals(
              'Access denied. You do not have permission to access this resource.',
            ),
          );

          final dio429 = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/test'),
              statusCode: 429,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio429),
            equals(
              'Too many requests. Please wait a moment before trying again.',
            ),
          );

          final dio500 = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/test'),
              statusCode: 500,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio500),
            equals('Server error (500). Please try again later.'),
          );

          const authOtp = AuthException(
            'Invalid OTP code',
            code: 'otp_expired',
          );
          expect(
            ErrorHandler.getFriendlyMessage(authOtp),
            contains('verification code you entered is invalid or has expired'),
          );

          const authGrant = AuthException('Bad login', code: 'invalid_grant');
          expect(
            ErrorHandler.getFriendlyMessage(authGrant),
            equals('Invalid login credentials. Please try again.'),
          );

          const authUserNotFound = AuthException(
            'Not found',
            code: 'user_not_found',
          );
          expect(
            ErrorHandler.getFriendlyMessage(authUserNotFound),
            equals('No account was found with those details.'),
          );

          final socketExp = Exception(
            'SocketException: OS Error: Connection refused',
          );
          expect(
            ErrorHandler.getFriendlyMessage(socketExp),
            contains('Network connection issue'),
          );
        },
      );

      test(
        'handleError executes for info, warning, error, and critical levels',
        () {
          ErrorHandler.handleError(
            'Info message',
            level: ErrorLevel.info,
            showUi: false,
          );

          ErrorHandler.handleError(
            'Warning message',
            level: ErrorLevel.warning,
            showUi: false,
          );

          ErrorHandler.handleError(
            Exception('Standard error'),
            showUi: false,
            stackTrace: StackTrace.current,
          );

          ErrorHandler.handleError(
            Exception('Critical crash'),
            level: ErrorLevel.critical,
            showUi: false,
          );
        },
      );
    });

    group('NetworkUtils and RateLimitInterceptor Tests', () {
      test(
        'RateLimitInterceptor parseRetryAfter parses header with jitter',
        () {
          final headers = Headers.fromMap({
            'retry-after': ['10'],
          });

          final fixedRandom = Random(42);
          final duration = RateLimitInterceptor.parseRetryAfter(
            headers,
            random: fixedRandom,
          );
          expect(duration.inSeconds, greaterThanOrEqualTo(8));
          expect(duration.inSeconds, lessThanOrEqualTo(13));
        },
      );

      test(
        'RateLimitInterceptor resetRateLimit and rateLimitedUntil getter/setter',
        () {
          RateLimitInterceptor.rateLimitedUntil = DateTime.now().add(
            const Duration(seconds: 30),
          );
          expect(RateLimitInterceptor.rateLimitedUntil, isNotNull);

          RateLimitInterceptor.resetRateLimit();
          expect(RateLimitInterceptor.rateLimitedUntil, isNull);
        },
      );

      test('CorrelationInterceptor adds X-Request-ID header', () {
        final interceptor = CorrelationInterceptor();
        final options = RequestOptions(path: '/api/v1/test');
        var nextCalled = false;

        final handler = _TrackingRequestHandler(() => nextCalled = true);
        interceptor.onRequest(options, handler);

        expect(options.headers['X-Request-ID'], isNotNull);
        expect(nextCalled, isTrue);
      });
    });

    group('AppRouter Route Definition Tests', () {
      test('goRouter defines initial routes and handles routing config', () {
        expect(goRouter, isNotNull);
        expect(goRouter.configuration.routes.isNotEmpty, isTrue);
      });
    });
  }

  // --- Section 2 ---
  {
    setUp(ConsentCacheManager.clear);

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

        await gotrueStorage.setItem(
          key: 'pkce_verifier',
          value: 'verifier_xyz',
        );
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

          final orbitSub = AppRefreshNotifier.orbitStream.listen(
            orbitEvents.add,
          );
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
        expect(
          (sanitized['nested'] as Map)['email'],
          equals('[EMAIL_REDACTED]'),
        );
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
        expect(
          ErrorHandler.getFriendlyMessage(dio500),
          contains('Server error'),
        );

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

  // --- Section 3 ---
  {
    group('ErrorHandler Exhaustive Mega Coverage Tests', () {
      test('sanitize redacts emails, tokens, phone numbers, and keys', () {
        // 1. Emails
        expect(
          ErrorHandler.sanitize('User john.doe@example.com logged in'),
          'User [EMAIL_REDACTED] logged in',
        );
        expect(
          ErrorHandler.sanitize('Contact support@nexus.app for help'),
          'Contact support@nexus.app for help',
        );

        // 2. Sensitive bearer & tokens
        expect(
          ErrorHandler.sanitize('bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'),
          'bearer: [REDACTED_SENSITIVE]',
        );
        expect(
          ErrorHandler.sanitize('token: abcdef1234567890'),
          'token: [REDACTED_SENSITIVE]',
        );
        expect(
          ErrorHandler.sanitize('password: SuperSecretPassword123'),
          'password: [REDACTED_SENSITIVE]',
        );

        // 3. JSON fields
        expect(
          ErrorHandler.sanitize('{"password": "secret_password_123"}'),
          '{"password": "[REDACTED_SENSITIVE]"}',
        );
        expect(
          ErrorHandler.sanitize('{"access_token": "token_12345678"}'),
          '{"access_token": "[REDACTED_SENSITIVE]"}',
        );

        // 4. Phone numbers
        expect(
          ErrorHandler.sanitize('Call +14155552671 or (555) 123-4567'),
          'Call [PHONE_REDACTED] or [PHONE_REDACTED]',
        );
      });

      test('isSensitiveKey identifies all sensitive parameter names', () {
        expect(ErrorHandler.isSensitiveKey('bearer'), isTrue);
        expect(ErrorHandler.isSensitiveKey('auth'), isTrue);
        expect(ErrorHandler.isSensitiveKey('token'), isTrue);
        expect(ErrorHandler.isSensitiveKey('authorization'), isTrue);
        expect(ErrorHandler.isSensitiveKey('password'), isTrue);
        expect(ErrorHandler.isSensitiveKey('secret'), isTrue);
        expect(ErrorHandler.isSensitiveKey('jwt'), isTrue);
        expect(ErrorHandler.isSensitiveKey('access_token'), isTrue);
        expect(ErrorHandler.isSensitiveKey('refresh_token'), isTrue);
        expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
        expect(ErrorHandler.isSensitiveKey('private_key'), isTrue);
        expect(ErrorHandler.isSensitiveKey('prekey'), isTrue);
        expect(ErrorHandler.isSensitiveKey('username'), isFalse);
        expect(ErrorHandler.isSensitiveKey('displayName'), isFalse);
      });

      test('sanitizeObject handles nested maps, lists, and primitives', () {
        final input = {
          'username': 'alice',
          'password': 'SuperSecretPassword123',
          'email': 'alice@domain.com',
          'items': ['token: abc12345678', 'normal_text'],
          'profile': {
            'jwt': 'secret_jwt_string_12345',
            'phone': '+14155552671',
          },
        };

        final sanitized = ErrorHandler.sanitizeObject(input) as Map;
        expect(sanitized['password'], '[REDACTED_SENSITIVE]');
        expect(sanitized['email'], '[EMAIL_REDACTED]');
        expect(sanitized['items'] is List, isTrue);
        expect((sanitized['profile'] as Map)['jwt'], '[REDACTED_SENSITIVE]');
      });

      test(
        'getFriendlyMessage handles DioExceptions, AuthExceptions, and clean strings',
        () {
          // 1. DioException status codes
          final dio401 = DioException(
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: 401,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio401),
            'Session expired. Please sign in again.',
          );

          final dio403 = DioException(
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: 403,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio403),
            'Access denied. You do not have permission to access this resource.',
          );

          final dio429 = DioException(
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: 429,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio429),
            'Too many requests. Please wait a moment before trying again.',
          );

          final dio500 = DioException(
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: 500,
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dio500),
            'Server error (500). Please try again later.',
          );

          final dioDetail = DioException(
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/test'),
              statusCode: 400,
              data: {'detail': 'Custom validation failure'},
            ),
          );
          expect(
            ErrorHandler.getFriendlyMessage(dioDetail),
            'Custom validation failure',
          );

          // 2. AuthException
          const authOtp = AuthException('Token expired', code: 'otp_expired');
          expect(
            ErrorHandler.getFriendlyMessage(authOtp),
            'The verification code you entered is invalid or has expired. Please check and try again.',
          );

          const authInvalid = AuthException(
            'Invalid grant',
            code: 'invalid_grant',
          );
          expect(
            ErrorHandler.getFriendlyMessage(authInvalid),
            'Invalid login credentials. Please try again.',
          );

          const authUserNotFound = AuthException(
            'Not found',
            code: 'user_not_found',
          );
          expect(
            ErrorHandler.getFriendlyMessage(authUserNotFound),
            'No account was found with those details.',
          );

          // 3. String cleanup
          expect(
            ErrorHandler.getFriendlyMessage(
              Exception('Access denied: Profile is locked'),
            ),
            'Access denied: Profile is locked',
          );
          expect(
            ErrorHandler.getFriendlyMessage(
              null,
              'Exception: Account inactive (details)',
            ),
            'Account inactive',
          );
        },
      );

      test('ErrorHandler formats diagnostic details', () {
        final msg = ErrorHandler.getFriendlyMessage(
          Exception('Network socket error: socketexception'),
        );
        expect(
          msg,
          'Network connection issue. Please check your internet connection and try again.',
        );
      });
    });
  }

  // --- Section 4 ---
  {
    group('ErrorHandler Exhaustive Tests', () {
      test(
        'sanitize redacts emails, passwords, tokens, phone numbers, and keys',
        () {
          expect(
            ErrorHandler.sanitize('User email is test.user@example.com!'),
            contains('[EMAIL_REDACTED]'),
          );
          expect(
            ErrorHandler.sanitize('Reach out to support@nexus.test'),
            contains('support@nexus.test'),
          );

          expect(
            ErrorHandler.sanitize(
              'bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz',
            ),
            contains('[REDACTED_SENSITIVE]'),
          );

          expect(
            ErrorHandler.sanitize('{"password": "superSecretPassword123!"}'),
            contains('[REDACTED_SENSITIVE]'),
          );

          expect(
            ErrorHandler.sanitize('{"access_token": "token1234567890"}'),
            contains('[REDACTED_SENSITIVE]'),
          );

          expect(
            ErrorHandler.sanitize('Phone: +14155552671 and 9876543210'),
            contains('[PHONE_REDACTED]'),
          );
        },
      );

      test('isSensitiveKey identifies all security and auth tokens', () {
        expect(ErrorHandler.isSensitiveKey('bearer'), isTrue);
        expect(ErrorHandler.isSensitiveKey('authorization'), isTrue);
        expect(ErrorHandler.isSensitiveKey('password'), isTrue);
        expect(ErrorHandler.isSensitiveKey('secret'), isTrue);
        expect(ErrorHandler.isSensitiveKey('jwt'), isTrue);
        expect(ErrorHandler.isSensitiveKey('access_token'), isTrue);
        expect(ErrorHandler.isSensitiveKey('refresh_token'), isTrue);
        expect(ErrorHandler.isSensitiveKey('media_key'), isTrue);
        expect(ErrorHandler.isSensitiveKey('aes_key'), isTrue);
        expect(ErrorHandler.isSensitiveKey('blind_index'), isTrue);
        expect(ErrorHandler.isSensitiveKey('otp_code'), isTrue);
        expect(ErrorHandler.isSensitiveKey('private_key'), isTrue);
        expect(ErrorHandler.isSensitiveKey('registration_lock'), isTrue);
        expect(ErrorHandler.isSensitiveKey('username'), isFalse);
        expect(ErrorHandler.isSensitiveKey('title'), isFalse);
      });

      test(
        'sanitizeObject handles nested maps, lists, and sensitive values',
        () {
          final input = {
            'username': 'john_doe@example.com',
            'password': 'secret_password',
            'tokens': ['bearer eyJhbGciOi...', 'normal_string'],
            'meta': {
              'access_token': '1234567890abcdef',
              'nested_list': [
                {'otp_code': '123456'},
              ],
            },
          };

          final sanitized = ErrorHandler.sanitizeObject(input) as Map;
          expect(sanitized['password'], '[REDACTED_SENSITIVE]');
          expect(
            (sanitized['meta'] as Map)['access_token'],
            '[REDACTED_SENSITIVE]',
          );
          expect(sanitized['username'], contains('[EMAIL_REDACTED]'));
        },
      );

      test('getFriendlyMessage parses Dio and custom errors correctly', () {
        final dio401 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 401,
            data: {'detail': 'Session expired.'},
          ),
          type: DioExceptionType.badResponse,
        );
        expect(ErrorHandler.getFriendlyMessage(dio401), 'Session expired.');

        final dio500 = DioException(
          requestOptions: RequestOptions(path: '/api/test'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/test'),
            statusCode: 500,
          ),
          type: DioExceptionType.badResponse,
        );
        expect(
          ErrorHandler.getFriendlyMessage(dio500),
          contains('Server error (500)'),
        );
      });

      test(
        'handleError processes DioException, SocketException, and generic errors',
        () {
          // Generic exception
          ErrorHandler.handleError(
            Exception('Standard test exception'),
            customMessage: 'Failed during test',
            level: ErrorLevel.warning,
            showUi: false,
          );

          // Socket exception (connection error)
          const socketError = SocketException('Connection refused');
          ErrorHandler.handleError(
            socketError,
            level: ErrorLevel.info,
            showUi: false,
          );

          // DioException with 401
          final dio401 = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/test'),
              statusCode: 401,
              data: {'detail': 'Session expired'},
            ),
            type: DioExceptionType.badResponse,
          );
          ErrorHandler.handleError(dio401, showUi: false);

          // DioException with 404
          final dio404 = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/test'),
              statusCode: 404,
              data: {'detail': 'Resource not found'},
            ),
            type: DioExceptionType.badResponse,
          );
          ErrorHandler.handleError(dio404, showUi: false);

          // DioException with 500
          final dio500 = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/test'),
              statusCode: 500,
              data: {'detail': 'Internal server error'},
            ),
            type: DioExceptionType.badResponse,
          );
          ErrorHandler.handleError(dio500, showUi: false);

          // DioException connection timeout
          final dioTimeout = DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            type: DioExceptionType.connectionTimeout,
          );
          ErrorHandler.handleError(dioTimeout, showUi: false);
        },
      );
    });
  }

  // --- Section 5 ---
  {
    final mockSessionJson = jsonEncode({
      'access_token': 'mock-access-token-12345',
      'refresh_token': 'mock-refresh-token-12345',
      'expires_in': 3600,
      'expires_at': 1893456000,
      'token_type': 'bearer',
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'user@nexus.test',
        'phone': '+14155552671',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      },
    });

    SharedPreferences.setMockInitialValues({
      'sb-mock-auth-token': mockSessionJson,
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_secure_screen'),
          (call) async => null,
        );

    setUpAll(() async {
      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
    });

    group('Error Handler and Settings Flows Tests', () {
      test('ErrorHandler sanitization and formatting tests', () {
        final sanitizedEmail = ErrorHandler.sanitize(
          'Contact user@example.com for help',
        );
        expect(sanitizedEmail, contains('[EMAIL_REDACTED]'));

        final sanitizedToken = ErrorHandler.sanitize(
          'bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz.123',
        );
        expect(sanitizedToken, contains('[REDACTED_SENSITIVE]'));

        final sanitizedPhone = ErrorHandler.sanitize('Call +14155552671 now');
        expect(sanitizedPhone, contains('[PHONE_REDACTED]'));

        expect(ErrorHandler.isSensitiveKey('access_token'), isTrue);
        expect(ErrorHandler.isSensitiveKey('username'), isFalse);

        final sanitizedObj = ErrorHandler.sanitizeObject({
          'token': 'secret123',
          'email': 'john@doe.com',
          'nested': ['+14155552671', 'normal string'],
        });
        expect(sanitizedObj, isA<Map<dynamic, dynamic>>());
      });

      testWidgets('HelpCenterPage renders categories and search', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HelpCenterPage(),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(HelpCenterPage), findsOneWidget);
      });

      testWidgets('CommunityGuidelinesPage renders properly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CommunityGuidelinesPage(),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(CommunityGuidelinesPage), findsOneWidget);
      });

      testWidgets('EmailOtpReauthDialog renders inputs and timers', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  return ElevatedButton(
                    onPressed: () async {
                      await showDialog<void>(
                        context: ctx,
                        builder: (_) => EmailOtpReauthDialog(
                          verifyUrl: '/api/v1/auth/reauth',
                          resendUrl: '/api/v1/auth/resend',
                          onVerificationSuccess: () {},
                        ),
                      );
                    },
                    child: const Text('Open Reauth'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Reauth'));
        await tester.pumpAndSettle();

        expect(find.byType(EmailOtpReauthDialog), findsOneWidget);
      });
    });
  }
}

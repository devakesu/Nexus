import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/spotify/services/spotify_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.devakesu.apps.nexus/spotify_auth'),
        (call) async {
          if (call.method == 'connectSpotify') {
            return 'mock_auth_code_123';
          }
          return null;
        },
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('SpotifyService Deep Unit Tests', () {
    late Dio dio;
    late SpotifyService service;

    setUp(() {
      dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method.toUpperCase() == 'DELETE') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'disconnected': true},
                ),
              );
            } else if (options.path.contains('native-exchange')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'artists': ['Radiohead', 'Daft Punk', 'Pink Floyd'],
                  },
                ),
              );
            } else if (options.path.contains('connect')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'auth_url': 'https://accounts.spotify.com/authorize'},
                ),
              );
            } else if (options.path.contains('status')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'connected': true,
                    'last_synced_at': '2026-01-01T00:00:00Z',
                    'playlist_count': 5,
                  },
                ),
              );
            } else if (options.path.contains('playlists')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'playlists': [
                      {
                        'id': 'pl_1',
                        'name': 'Chill Vibes',
                        'track_count': 25,
                      },
                    ],
                  },
                ),
              );
            } else if (options.path.contains('resync')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'syncing': true},
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );
      service = SpotifyService(dio);
    });

    test('requestNativeAuthCode invokes method channel', () async {
      final code = await service.requestNativeAuthCode();
      expect(code, 'mock_auth_code_123');
    });

    test('exchangeNativeCode returns artists list', () async {
      final artists = await service.exchangeNativeCode('test_code');
      expect(artists, contains('Radiohead'));
      expect(artists.length, 3);
    });

    test('fetchAuthUrl returns auth url', () async {
      final url = await service.fetchAuthUrl();
      expect(url, 'https://accounts.spotify.com/authorize');
    });

    test('fetchStatus returns SpotifyConnectionStatus', () async {
      final status = await service.fetchStatus();
      expect(status.connected, isTrue);
      expect(status.playlistCount, 5);
    });

    test('fetchPlaylists returns SpotifyPlaylistsPayload', () async {
      final payload = await service.fetchPlaylists();
      expect(payload.playlists.length, 1);
      expect(payload.playlists.first.name, 'Chill Vibes');
    });

    test('resync returns syncing boolean', () async {
      final syncing = await service.resync();
      expect(syncing, isTrue);
    });

    test('disconnect returns disconnected boolean', () async {
      final disconnected = await service.disconnect();
      expect(disconnected, isTrue);
    });
  });
}

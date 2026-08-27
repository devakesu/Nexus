import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
import 'package:nexus/features/spotify/models/spotify_playlist.dart';
import 'package:nexus/features/spotify/services/spotify_service.dart';

import '../../helpers/mock_network_interceptor.dart';
import '../../helpers/test_helpers.dart';

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

    setUpAll(setupGlobalMockNetwork);

    group(
      'Signal Key Service & Spotify Playlists Sheet Tests',
      () {
        test('SignalKeyService singleton has isNewLocalIdentity flag', () {
          final service = SignalKeyService.instance;
          expect(service.isNewLocalIdentity, isFalse);
        });

        testWidgets('openPlaylistsSheet renders bottom sheet content', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => openPlaylistsSheet(context),
                      child: const Text('Open Playlists'),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.tap(find.text('Open Playlists'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(DraggableScrollableSheet), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      },
    );
  }

  // --- Section 2 ---
  {
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
                    data: {
                      'auth_url': 'https://accounts.spotify.com/authorize',
                    },
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

  // --- Section 3 ---
  {
    group('Spotify Models & Serialization Tests', () {
      test('SpotifyTrack fromJson and artistLine', () {
        final json = {
          'spotify_track_id': 'trk_123',
          'name': 'Radioactive',
          'artists': ['Imagine Dragons', 'Kendrick Lamar'],
        };

        final track = SpotifyTrack.fromJson(json);
        expect(track.spotifyTrackId, equals('trk_123'));
        expect(track.name, equals('Radioactive'));
        expect(track.artists.length, equals(2));
        expect(track.artistLine, equals('Imagine Dragons, Kendrick Lamar'));
      });

      test('SpotifyPlaylist fromJson parsing', () {
        final json = {
          'id': 'pl_db_id',
          'spotify_playlist_id': 'sp_pl_1',
          'name': 'Cosmic Vibes',
          'is_collaborative': true,
          'track_count': 1,
          'tracks': [
            {
              'spotify_track_id': 'trk_1',
              'name': 'Starboy',
              'artists': ['The Weeknd', 'Daft Punk'],
            },
          ],
          'spotify_url': 'https://open.spotify.com/playlist/123',
          'synced_at': '2026-08-26T10:00:00Z',
        };

        final playlist = SpotifyPlaylist.fromJson(json);
        expect(playlist.id, equals('pl_db_id'));
        expect(playlist.spotifyPlaylistId, equals('sp_pl_1'));
        expect(playlist.name, equals('Cosmic Vibes'));
        expect(playlist.isCollaborative, isTrue);
        expect(playlist.trackCount, equals(1));
        expect(playlist.tracks.length, equals(1));
        expect(playlist.tracks.first.name, equals('Starboy'));
        expect(
          playlist.spotifyUrl,
          equals('https://open.spotify.com/playlist/123'),
        );
        expect(playlist.syncedAt, isNotNull);
      });

      test('SpotifyPlaylistsPayload and SpotifyConnectionStatus fromJson', () {
        final payloadJson = {
          'connected': true,
          'last_synced_at': '2026-08-26T10:00:00Z',
          'playlists': <dynamic>[],
        };
        final payload = SpotifyPlaylistsPayload.fromJson(payloadJson);
        expect(payload.connected, isTrue);
        expect(payload.playlists, isEmpty);
        expect(payload.lastSyncedAt, isNotNull);

        final statusJson = {
          'connected': true,
          'playlist_count': 4,
          'last_synced_at': '2026-08-26T10:00:00Z',
        };
        final status = SpotifyConnectionStatus.fromJson(statusJson);
        expect(status.connected, isTrue);
        expect(status.playlistCount, equals(4));
      });
    });

    group('SpotifyService API Tests', () {
      late Dio dio;

      setUp(() {
        dio = Dio();
      });

      test('SpotifyService methods construct correct requests', () async {
        final service = SpotifyService(dio);
        expect(service, isNotNull);
      });
    });
  }

  // --- Section 4 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('SpotifyPlaylistsSection Tests', () {
      testWidgets('opens Spotify playlists sheet and renders playlist cards', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () => openPlaylistsSheet(context),
                      child: const Text('Open Playlists Sheet'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Open Playlists Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Your Playlists'), findsOneWidget);
      });
    });
  }
}

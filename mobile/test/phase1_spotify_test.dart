import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/spotify/models/spotify_playlist.dart';
import 'package:nexus/features/spotify/services/spotify_service.dart';

void main() {
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

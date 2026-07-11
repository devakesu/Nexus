import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/features/spotify/models/spotify_playlist.dart';

/// Wraps every backend/native call for the Spotify integration.
///
/// Moved out of profile_tab.dart's previously-inline `_connectSpotify*`
/// methods now that the feature spans connect, status, playlists, resync,
/// and disconnect. UI orchestration (setState, toasts, fallback dialogs)
/// stays in profile_tab.dart / the Playlists section - this class only
/// does the network/native plumbing and throws on failure.
class SpotifyService {
  SpotifyService(this._dio);

  final Dio _dio;

  static const _nativeAuthChannel = MethodChannel(
    'com.devakesu.apps.nexus/spotify_auth',
  );

  /// Invokes the native Spotify Android Auth Library SSO flow and returns
  /// the authorization code, or null if the user cancelled.
  ///
  /// Throws [PlatformException] on native auth failure - callers should
  /// fall back to [fetchAuthUrl] when `e.message == 'AUTHENTICATION_SERVICE_UNAVAILABLE'`.
  Future<String?> requestNativeAuthCode() {
    final config = AppConfig.current;
    return _nativeAuthChannel.invokeMethod<String>('connectSpotify', {
      'clientId': config.spotifyClientId,
      'redirectUri': config.spotifyNativeRedirectUri,
    });
  }

  /// Exchanges a native auth code for a persistent connection + a fast
  /// native-only top-artists seed. Playlist sync continues in the
  /// background on the server; call [fetchStatus] afterward to see when it
  /// completes.
  Future<List<String>> exchangeNativeCode(String code) async {
    final config = AppConfig.current;
    final response = await _dio.post<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/spotify/native-exchange',
      data: {
        'code': code,
        'redirect_uri': config.spotifyNativeRedirectUri,
      },
    );
    final data = response.data;
    if (data == null || !data.containsKey('artists')) {
      throw const FormatException('Invalid or empty response from server.');
    }
    final raw = data['artists'];
    if (raw is! List) {
      throw const FormatException('Expected artists list in response.');
    }
    return raw.map((e) => e.toString()).toList();
  }

  /// Requests a browser OAuth authorization URL for the current user
  /// (non-Android fallback / native-unavailable fallback).
  Future<String?> fetchAuthUrl() async {
    final config = AppConfig.current;
    final response = await _dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/spotify/connect',
    );
    return response.data?['auth_url'] as String?;
  }

  /// Cheap connected/last-synced/playlist-count summary, used to decide
  /// Connect-vs-Manage button state without pulling the full playlist payload.
  Future<SpotifyConnectionStatus> fetchStatus() async {
    final config = AppConfig.current;
    final response = await _dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/spotify/status',
    );
    if (response.data == null) return SpotifyConnectionStatus.disconnected;
    return SpotifyConnectionStatus.fromJson(response.data!);
  }

  /// Full decrypted playlist + track payload. Owner-only, private - never
  /// call this on behalf of another user.
  Future<SpotifyPlaylistsPayload> fetchPlaylists() async {
    final config = AppConfig.current;
    final response = await _dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/spotify/playlists',
    );
    if (response.data == null) return SpotifyPlaylistsPayload.empty;
    return SpotifyPlaylistsPayload.fromJson(response.data!);
  }

  /// Triggers a background resync using the server's stored refresh token -
  /// no re-auth needed. Returns true if a sync was queued.
  Future<bool> resync() async {
    final config = AppConfig.current;
    final response = await _dio.post<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/spotify/resync',
    );
    return response.data?['syncing'] as bool? ?? false;
  }

  /// Fully revokes the connection: deletes the stored refresh token and all
  /// synced playlists, and clears top_artists from the public profile.
  Future<bool> disconnect() async {
    final config = AppConfig.current;
    final response = await _dio.delete<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/spotify/connection',
    );
    return response.data?['disconnected'] as bool? ?? false;
  }
}

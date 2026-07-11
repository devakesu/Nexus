/// Dart models for the private, owner-only Spotify playlist detail surface.
///
/// These mirror app/models.py's SpotifyTrackOut/SpotifyPlaylistOut/
/// SpotifyPlaylistsResponse/SpotifyStatusResponse. Unlike top_artists
/// (a plain `List` of `String` used throughout the rest of the app),
/// playlist data is structured enough to warrant real models rather than
/// raw maps.
class SpotifyTrack {
  const SpotifyTrack({
    required this.name,
    required this.artists,
    this.spotifyTrackId,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    return SpotifyTrack(
      spotifyTrackId: json['spotify_track_id'] as String?,
      name: json['name'] as String? ?? '',
      artists: (json['artists'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  final String? spotifyTrackId;
  final String name;
  final List<String> artists;

  String get artistLine => artists.join(', ');
}

class SpotifyPlaylist {
  const SpotifyPlaylist({
    required this.id,
    required this.spotifyPlaylistId,
    required this.name,
    required this.isCollaborative,
    required this.trackCount,
    required this.tracks,
    required this.spotifyUrl,
    this.syncedAt,
  });

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    return SpotifyPlaylist(
      id: json['id'] as String? ?? '',
      spotifyPlaylistId: json['spotify_playlist_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isCollaborative: json['is_collaborative'] as bool? ?? false,
      trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
      tracks: (json['tracks'] as List<dynamic>? ?? [])
          .map((e) => SpotifyTrack.fromJson(e as Map<String, dynamic>))
          .toList(),
      spotifyUrl: json['spotify_url'] as String? ?? '',
      syncedAt: json['synced_at'] != null
          ? DateTime.tryParse(json['synced_at'] as String)
          : null,
    );
  }

  final String id;
  final String spotifyPlaylistId;
  final String name;
  final bool isCollaborative;
  final int trackCount;
  final List<SpotifyTrack> tracks;
  final String spotifyUrl;
  final DateTime? syncedAt;
}

class SpotifyPlaylistsPayload {
  const SpotifyPlaylistsPayload({
    required this.connected,
    required this.playlists,
    this.lastSyncedAt,
  });

  factory SpotifyPlaylistsPayload.fromJson(Map<String, dynamic> json) {
    return SpotifyPlaylistsPayload(
      connected: json['connected'] as bool? ?? false,
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.tryParse(json['last_synced_at'] as String)
          : null,
      playlists: (json['playlists'] as List<dynamic>? ?? [])
          .map((e) => SpotifyPlaylist.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final bool connected;
  final DateTime? lastSyncedAt;
  final List<SpotifyPlaylist> playlists;

  static const empty = SpotifyPlaylistsPayload(connected: false, playlists: []);
}

class SpotifyConnectionStatus {
  const SpotifyConnectionStatus({
    required this.connected,
    required this.playlistCount,
    this.lastSyncedAt,
  });

  factory SpotifyConnectionStatus.fromJson(Map<String, dynamic> json) {
    return SpotifyConnectionStatus(
      connected: json['connected'] as bool? ?? false,
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.tryParse(json['last_synced_at'] as String)
          : null,
      playlistCount: (json['playlist_count'] as num?)?.toInt() ?? 0,
    );
  }

  final bool connected;
  final DateTime? lastSyncedAt;
  final int playlistCount;

  static const disconnected = SpotifyConnectionStatus(
    connected: false,
    playlistCount: 0,
  );
}

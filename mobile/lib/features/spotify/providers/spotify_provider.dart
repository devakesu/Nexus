import 'package:nexus/features/spotify/models/spotify_playlist.dart';
import 'package:nexus/features/spotify/services/spotify_service.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'spotify_provider.g.dart';

@riverpod
SpotifyService spotifyService(Ref ref) => SpotifyService(createDio());

/// Cheap connected/last-synced/playlist-count summary - prefetched on
/// Profile tab load to decide Connect-vs-Manage button state. Not keepAlive:
/// it's fine for this to refetch each time it's watched, since it's a
/// single-row status query.
@riverpod
Future<SpotifyConnectionStatus> spotifyStatus(Ref ref) {
  return ref.watch(spotifyServiceProvider).fetchStatus();
}

/// Full playlist + track payload. Deliberately NOT keepAlive and NOT
/// disk-cached (unlike the rest of the profile's SecureProfileCache) - this
/// is a large, sensitive, frequently-changing payload that should only ever
/// live in memory, fetched fresh each time the owner opens the Playlists
/// sheet, and discarded when it's closed.
@riverpod
class SpotifyPlaylistsController extends _$SpotifyPlaylistsController {
  @override
  Future<SpotifyPlaylistsPayload> build() {
    return ref.watch(spotifyServiceProvider).fetchPlaylists();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<SpotifyPlaylistsPayload>();
    state = await AsyncValue.guard(
      () => ref.read(spotifyServiceProvider).fetchPlaylists(),
    );
  }
}

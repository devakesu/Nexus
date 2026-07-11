// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'spotify_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(spotifyService)
final spotifyServiceProvider = SpotifyServiceProvider._();

final class SpotifyServiceProvider
    extends $FunctionalProvider<SpotifyService, SpotifyService, SpotifyService>
    with $Provider<SpotifyService> {
  SpotifyServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'spotifyServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$spotifyServiceHash();

  @$internal
  @override
  $ProviderElement<SpotifyService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SpotifyService create(Ref ref) {
    return spotifyService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SpotifyService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SpotifyService>(value),
    );
  }
}

String _$spotifyServiceHash() => r'3a7487d9bed5ce7ee37ac5cad483df4ce42744b7';

/// Cheap connected/last-synced/playlist-count summary - prefetched on
/// Profile tab load to decide Connect-vs-Manage button state. Not keepAlive:
/// it's fine for this to refetch each time it's watched, since it's a
/// single-row status query.

@ProviderFor(spotifyStatus)
final spotifyStatusProvider = SpotifyStatusProvider._();

/// Cheap connected/last-synced/playlist-count summary - prefetched on
/// Profile tab load to decide Connect-vs-Manage button state. Not keepAlive:
/// it's fine for this to refetch each time it's watched, since it's a
/// single-row status query.

final class SpotifyStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<SpotifyConnectionStatus>,
          SpotifyConnectionStatus,
          FutureOr<SpotifyConnectionStatus>
        >
    with
        $FutureModifier<SpotifyConnectionStatus>,
        $FutureProvider<SpotifyConnectionStatus> {
  /// Cheap connected/last-synced/playlist-count summary - prefetched on
  /// Profile tab load to decide Connect-vs-Manage button state. Not keepAlive:
  /// it's fine for this to refetch each time it's watched, since it's a
  /// single-row status query.
  SpotifyStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'spotifyStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$spotifyStatusHash();

  @$internal
  @override
  $FutureProviderElement<SpotifyConnectionStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SpotifyConnectionStatus> create(Ref ref) {
    return spotifyStatus(ref);
  }
}

String _$spotifyStatusHash() => r'e53c61eadd343a0d224671206d3cd6f25d749fc7';

/// Full playlist + track payload. Deliberately NOT keepAlive and NOT
/// disk-cached (unlike the rest of the profile's SecureProfileCache) - this
/// is a large, sensitive, frequently-changing payload that should only ever
/// live in memory, fetched fresh each time the owner opens the Playlists
/// sheet, and discarded when it's closed.

@ProviderFor(SpotifyPlaylistsController)
final spotifyPlaylistsControllerProvider =
    SpotifyPlaylistsControllerProvider._();

/// Full playlist + track payload. Deliberately NOT keepAlive and NOT
/// disk-cached (unlike the rest of the profile's SecureProfileCache) - this
/// is a large, sensitive, frequently-changing payload that should only ever
/// live in memory, fetched fresh each time the owner opens the Playlists
/// sheet, and discarded when it's closed.
final class SpotifyPlaylistsControllerProvider
    extends
        $AsyncNotifierProvider<
          SpotifyPlaylistsController,
          SpotifyPlaylistsPayload
        > {
  /// Full playlist + track payload. Deliberately NOT keepAlive and NOT
  /// disk-cached (unlike the rest of the profile's SecureProfileCache) - this
  /// is a large, sensitive, frequently-changing payload that should only ever
  /// live in memory, fetched fresh each time the owner opens the Playlists
  /// sheet, and discarded when it's closed.
  SpotifyPlaylistsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'spotifyPlaylistsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$spotifyPlaylistsControllerHash();

  @$internal
  @override
  SpotifyPlaylistsController create() => SpotifyPlaylistsController();
}

String _$spotifyPlaylistsControllerHash() =>
    r'61cae37a46382311fe8aa75b9cc883c06bd02775';

/// Full playlist + track payload. Deliberately NOT keepAlive and NOT
/// disk-cached (unlike the rest of the profile's SecureProfileCache) - this
/// is a large, sensitive, frequently-changing payload that should only ever
/// live in memory, fetched fresh each time the owner opens the Playlists
/// sheet, and discarded when it's closed.

abstract class _$SpotifyPlaylistsController
    extends $AsyncNotifier<SpotifyPlaylistsPayload> {
  FutureOr<SpotifyPlaylistsPayload> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<SpotifyPlaylistsPayload>,
              SpotifyPlaylistsPayload
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SpotifyPlaylistsPayload>,
                SpotifyPlaylistsPayload
              >,
              AsyncValue<SpotifyPlaylistsPayload>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

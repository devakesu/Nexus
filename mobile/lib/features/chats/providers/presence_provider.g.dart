// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presence_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Polls a peer's presence every 30s while something is watching this
/// provider (e.g. the chat conversation page's app bar). Polling rather
/// than a dedicated realtime channel keeps this "nice to have" signal off
/// the Postgres-changes path entirely.

@ProviderFor(PeerPresence)
final peerPresenceProvider = PeerPresenceFamily._();

/// Polls a peer's presence every 30s while something is watching this
/// provider (e.g. the chat conversation page's app bar). Polling rather
/// than a dedicated realtime channel keeps this "nice to have" signal off
/// the Postgres-changes path entirely.
final class PeerPresenceProvider
    extends $AsyncNotifierProvider<PeerPresence, PresenceInfo> {
  /// Polls a peer's presence every 30s while something is watching this
  /// provider (e.g. the chat conversation page's app bar). Polling rather
  /// than a dedicated realtime channel keeps this "nice to have" signal off
  /// the Postgres-changes path entirely.
  PeerPresenceProvider._({
    required PeerPresenceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'peerPresenceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$peerPresenceHash();

  @override
  String toString() {
    return r'peerPresenceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PeerPresence create() => PeerPresence();

  @override
  bool operator ==(Object other) {
    return other is PeerPresenceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$peerPresenceHash() => r'3d2da733d9526e2f9b12a4069e40ec7c1f778181';

/// Polls a peer's presence every 30s while something is watching this
/// provider (e.g. the chat conversation page's app bar). Polling rather
/// than a dedicated realtime channel keeps this "nice to have" signal off
/// the Postgres-changes path entirely.

final class PeerPresenceFamily extends $Family
    with
        $ClassFamilyOverride<
          PeerPresence,
          AsyncValue<PresenceInfo>,
          PresenceInfo,
          FutureOr<PresenceInfo>,
          String
        > {
  PeerPresenceFamily._()
    : super(
        retry: null,
        name: r'peerPresenceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Polls a peer's presence every 30s while something is watching this
  /// provider (e.g. the chat conversation page's app bar). Polling rather
  /// than a dedicated realtime channel keeps this "nice to have" signal off
  /// the Postgres-changes path entirely.

  PeerPresenceProvider call(String peerUserId) =>
      PeerPresenceProvider._(argument: peerUserId, from: this);

  @override
  String toString() => r'peerPresenceProvider';
}

/// Polls a peer's presence every 30s while something is watching this
/// provider (e.g. the chat conversation page's app bar). Polling rather
/// than a dedicated realtime channel keeps this "nice to have" signal off
/// the Postgres-changes path entirely.

abstract class _$PeerPresence extends $AsyncNotifier<PresenceInfo> {
  late final _$args = ref.$arg as String;
  String get peerUserId => _$args;

  FutureOr<PresenceInfo> build(String peerUserId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<PresenceInfo>, PresenceInfo>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PresenceInfo>, PresenceInfo>,
              AsyncValue<PresenceInfo>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

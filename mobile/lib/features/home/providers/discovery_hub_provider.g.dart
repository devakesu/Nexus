// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery_hub_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns fetching + secure-storage caching + stale-while-revalidate
/// reconciliation for a discovery hub tab's profile status, likes inbox,
/// and matches list - shared by DatingTab/FriendsTab/ProfessionalTab
/// (`mode` is `'dating'|'friends'|'professional'`) instead of each tab
/// independently duplicating the same three fetches. Per-mode business
/// logic (field saves, orbit toggle, overlays, record-actions) stays in
/// each tab, applied to this provider's raw JSON via their existing
/// parsing methods.

@ProviderFor(DiscoveryHubController)
final discoveryHubControllerProvider = DiscoveryHubControllerFamily._();

/// Owns fetching + secure-storage caching + stale-while-revalidate
/// reconciliation for a discovery hub tab's profile status, likes inbox,
/// and matches list - shared by DatingTab/FriendsTab/ProfessionalTab
/// (`mode` is `'dating'|'friends'|'professional'`) instead of each tab
/// independently duplicating the same three fetches. Per-mode business
/// logic (field saves, orbit toggle, overlays, record-actions) stays in
/// each tab, applied to this provider's raw JSON via their existing
/// parsing methods.
final class DiscoveryHubControllerProvider
    extends $AsyncNotifierProvider<DiscoveryHubController, DiscoveryHubState> {
  /// Owns fetching + secure-storage caching + stale-while-revalidate
  /// reconciliation for a discovery hub tab's profile status, likes inbox,
  /// and matches list - shared by DatingTab/FriendsTab/ProfessionalTab
  /// (`mode` is `'dating'|'friends'|'professional'`) instead of each tab
  /// independently duplicating the same three fetches. Per-mode business
  /// logic (field saves, orbit toggle, overlays, record-actions) stays in
  /// each tab, applied to this provider's raw JSON via their existing
  /// parsing methods.
  DiscoveryHubControllerProvider._({
    required DiscoveryHubControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'discoveryHubControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$discoveryHubControllerHash();

  @override
  String toString() {
    return r'discoveryHubControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  DiscoveryHubController create() => DiscoveryHubController();

  @override
  bool operator ==(Object other) {
    return other is DiscoveryHubControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$discoveryHubControllerHash() =>
    r'54ec338dad6ffde93ceecb6a3a1ee4d78c1fe077';

/// Owns fetching + secure-storage caching + stale-while-revalidate
/// reconciliation for a discovery hub tab's profile status, likes inbox,
/// and matches list - shared by DatingTab/FriendsTab/ProfessionalTab
/// (`mode` is `'dating'|'friends'|'professional'`) instead of each tab
/// independently duplicating the same three fetches. Per-mode business
/// logic (field saves, orbit toggle, overlays, record-actions) stays in
/// each tab, applied to this provider's raw JSON via their existing
/// parsing methods.

final class DiscoveryHubControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          DiscoveryHubController,
          AsyncValue<DiscoveryHubState>,
          DiscoveryHubState,
          FutureOr<DiscoveryHubState>,
          String
        > {
  DiscoveryHubControllerFamily._()
    : super(
        retry: null,
        name: r'discoveryHubControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Owns fetching + secure-storage caching + stale-while-revalidate
  /// reconciliation for a discovery hub tab's profile status, likes inbox,
  /// and matches list - shared by DatingTab/FriendsTab/ProfessionalTab
  /// (`mode` is `'dating'|'friends'|'professional'`) instead of each tab
  /// independently duplicating the same three fetches. Per-mode business
  /// logic (field saves, orbit toggle, overlays, record-actions) stays in
  /// each tab, applied to this provider's raw JSON via their existing
  /// parsing methods.

  DiscoveryHubControllerProvider call(String mode) =>
      DiscoveryHubControllerProvider._(argument: mode, from: this);

  @override
  String toString() => r'discoveryHubControllerProvider';
}

/// Owns fetching + secure-storage caching + stale-while-revalidate
/// reconciliation for a discovery hub tab's profile status, likes inbox,
/// and matches list - shared by DatingTab/FriendsTab/ProfessionalTab
/// (`mode` is `'dating'|'friends'|'professional'`) instead of each tab
/// independently duplicating the same three fetches. Per-mode business
/// logic (field saves, orbit toggle, overlays, record-actions) stays in
/// each tab, applied to this provider's raw JSON via their existing
/// parsing methods.

abstract class _$DiscoveryHubController
    extends $AsyncNotifier<DiscoveryHubState> {
  late final _$args = ref.$arg as String;
  String get mode => _$args;

  FutureOr<DiscoveryHubState> build(String mode);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<DiscoveryHubState>, DiscoveryHubState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<DiscoveryHubState>, DiscoveryHubState>,
              AsyncValue<DiscoveryHubState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

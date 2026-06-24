// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_ai_image_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ClientAIImageManager)
final clientAIImageManagerProvider = ClientAIImageManagerProvider._();

final class ClientAIImageManagerProvider
    extends $NotifierProvider<ClientAIImageManager, ClientAIProfileState> {
  ClientAIImageManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clientAIImageManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clientAIImageManagerHash();

  @$internal
  @override
  ClientAIImageManager create() => ClientAIImageManager();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClientAIProfileState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClientAIProfileState>(value),
    );
  }
}

String _$clientAIImageManagerHash() =>
    r'cc6df745f7725ffd733b29f4e46a820f1b5aec40';

abstract class _$ClientAIImageManager extends $Notifier<ClientAIProfileState> {
  ClientAIProfileState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClientAIProfileState, ClientAIProfileState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClientAIProfileState, ClientAIProfileState>,
              ClientAIProfileState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

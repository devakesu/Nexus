// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_conversation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ChatConversationController)
final chatConversationControllerProvider = ChatConversationControllerFamily._();

final class ChatConversationControllerProvider
    extends
        $AsyncNotifierProvider<
          ChatConversationController,
          ChatConversationState
        > {
  ChatConversationControllerProvider._({
    required ChatConversationControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'chatConversationControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatConversationControllerHash();

  @override
  String toString() {
    return r'chatConversationControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ChatConversationController create() => ChatConversationController();

  @override
  bool operator ==(Object other) {
    return other is ChatConversationControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatConversationControllerHash() =>
    r'fdaaee66765cafb1903f3722a5f9a9f9abe6f034';

final class ChatConversationControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ChatConversationController,
          AsyncValue<ChatConversationState>,
          ChatConversationState,
          FutureOr<ChatConversationState>,
          (String, String)
        > {
  ChatConversationControllerFamily._()
    : super(
        retry: null,
        name: r'chatConversationControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ChatConversationControllerProvider call(
    String conversationId,
    String peerUserId,
  ) => ChatConversationControllerProvider._(
    argument: (conversationId, peerUserId),
    from: this,
  );

  @override
  String toString() => r'chatConversationControllerProvider';
}

abstract class _$ChatConversationController
    extends $AsyncNotifier<ChatConversationState> {
  late final _$args = ref.$arg as (String, String);
  String get conversationId => _$args.$1;
  String get peerUserId => _$args.$2;

  FutureOr<ChatConversationState> build(
    String conversationId,
    String peerUserId,
  );
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ChatConversationState>, ChatConversationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ChatConversationState>,
                ChatConversationState
              >,
              AsyncValue<ChatConversationState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

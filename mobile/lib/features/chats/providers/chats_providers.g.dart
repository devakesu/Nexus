// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chats_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ChatConversations)
final chatConversationsProvider = ChatConversationsFamily._();

final class ChatConversationsProvider
    extends
        $AsyncNotifierProvider<
          ChatConversations,
          List<ChatConversationSummary>
        > {
  ChatConversationsProvider._({
    required ChatConversationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'chatConversationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatConversationsHash();

  @override
  String toString() {
    return r'chatConversationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ChatConversations create() => ChatConversations();

  @override
  bool operator ==(Object other) {
    return other is ChatConversationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatConversationsHash() => r'6ead6aadcbf919b4a4393f35febefe3a2cfe6082';

final class ChatConversationsFamily extends $Family
    with
        $ClassFamilyOverride<
          ChatConversations,
          AsyncValue<List<ChatConversationSummary>>,
          List<ChatConversationSummary>,
          FutureOr<List<ChatConversationSummary>>,
          String
        > {
  ChatConversationsFamily._()
    : super(
        retry: null,
        name: r'chatConversationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ChatConversationsProvider call(String tab) =>
      ChatConversationsProvider._(argument: tab, from: this);

  @override
  String toString() => r'chatConversationsProvider';
}

abstract class _$ChatConversations
    extends $AsyncNotifier<List<ChatConversationSummary>> {
  late final _$args = ref.$arg as String;
  String get tab => _$args;

  FutureOr<List<ChatConversationSummary>> build(String tab);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<ChatConversationSummary>>,
              List<ChatConversationSummary>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<ChatConversationSummary>>,
                List<ChatConversationSummary>
              >,
              AsyncValue<List<ChatConversationSummary>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(newChatCandidates)
final newChatCandidatesProvider = NewChatCandidatesFamily._();

final class NewChatCandidatesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ChatCandidate>>,
          List<ChatCandidate>,
          FutureOr<List<ChatCandidate>>
        >
    with
        $FutureModifier<List<ChatCandidate>>,
        $FutureProvider<List<ChatCandidate>> {
  NewChatCandidatesProvider._({
    required NewChatCandidatesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'newChatCandidatesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$newChatCandidatesHash();

  @override
  String toString() {
    return r'newChatCandidatesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ChatCandidate>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ChatCandidate>> create(Ref ref) {
    final argument = this.argument as String;
    return newChatCandidates(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is NewChatCandidatesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$newChatCandidatesHash() => r'5e840298ad795da6859f9aafe411eb046767a271';

final class NewChatCandidatesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ChatCandidate>>, String> {
  NewChatCandidatesFamily._()
    : super(
        retry: null,
        name: r'newChatCandidatesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NewChatCandidatesProvider call(String tab) =>
      NewChatCandidatesProvider._(argument: tab, from: this);

  @override
  String toString() => r'newChatCandidatesProvider';
}

@ProviderFor(hasUnreadMessages)
final hasUnreadMessagesProvider = HasUnreadMessagesProvider._();

final class HasUnreadMessagesProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  HasUnreadMessagesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hasUnreadMessagesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hasUnreadMessagesHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return hasUnreadMessages(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$hasUnreadMessagesHash() => r'd19f0997b60e01ce63e3a24dbbdda34ec4a998fc';

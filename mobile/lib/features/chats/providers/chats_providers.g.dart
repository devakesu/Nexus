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

String _$chatConversationsHash() => r'8aa62f7dc3f9c718f76c65e699a043759fada5ca';

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

String _$newChatCandidatesHash() => r'693a3c04b96089ac0417207eb8f3ca3c97cb7e05';

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

@ProviderFor(HasUnreadMessages)
final hasUnreadMessagesProvider = HasUnreadMessagesProvider._();

final class HasUnreadMessagesProvider
    extends $AsyncNotifierProvider<HasUnreadMessages, bool> {
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
  HasUnreadMessages create() => HasUnreadMessages();
}

String _$hasUnreadMessagesHash() => r'687c729957c036a43ec97e06f10bd2df543da26f';

abstract class _$HasUnreadMessages extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

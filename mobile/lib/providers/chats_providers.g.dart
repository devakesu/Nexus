// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chats_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatConversations)
final chatConversationsProvider = ChatConversationsFamily._();

final class ChatConversationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ChatConversationSummary>>,
          List<ChatConversationSummary>,
          FutureOr<List<ChatConversationSummary>>
        >
    with
        $FutureModifier<List<ChatConversationSummary>>,
        $FutureProvider<List<ChatConversationSummary>> {
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
  $FutureProviderElement<List<ChatConversationSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ChatConversationSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return chatConversations(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatConversationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatConversationsHash() => r'f4356979c768bf5bbbe962864f4c7af1e19acce7';

final class ChatConversationsFamily extends $Family
    with
        $FunctionalFamilyOverride<
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

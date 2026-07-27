import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'discovery_hub_provider.g.dart';

const _tabParam = {
  'dating': 'Dating',
  'friends': 'Friends',
  'professional': 'Professional',
};

/// Raw JSON snapshot of a discovery hub's profile status, likes inbox, and
/// matches list. Deliberately untyped/unparsed per-mode - each tab keeps
/// applying its own existing `_parseProfileData`/item-parsing logic to
/// these fields, so mode-specific business logic never has to move into
/// this shared provider.
class DiscoveryHubState {
  const DiscoveryHubState({
    required this.profileDetails,
    required this.profileError,
    required this.likes,
    required this.unseenCount,
    required this.matches,
    this.isRevalidating = false,
  });

  factory DiscoveryHubState.fromCache(Map<String, dynamic> json) {
    final rawLikes = json['likes'];
    final rawMatches = json['matches'];
    return DiscoveryHubState(
      profileDetails: json['profileDetails'] as Map<String, dynamic>?,
      profileError: null,
      likes: rawLikes is List
          ? List<Map<String, dynamic>>.from(
              rawLikes.cast<Map<String, dynamic>>(),
            )
          : [],
      unseenCount: (json['unseenCount'] as num?)?.toInt() ?? 0,
      matches: rawMatches is List
          ? List<Map<String, dynamic>>.from(
              rawMatches.cast<Map<String, dynamic>>(),
            )
          : [],
    );
  }

  /// The full `/api/v1/profile/details` response, or null if it's never
  /// been fetched successfully.
  final Map<String, dynamic>? profileDetails;

  /// Set only when the profile-details fetch itself failed - mirrors the
  /// granular resilience the tabs already have today, where a likes/matches
  /// hiccup is silently tolerated but a profile-status failure blocks the
  /// tab behind an error screen.
  final String? profileError;

  final List<Map<String, dynamic>> likes;
  final int unseenCount;
  final List<Map<String, dynamic>> matches;

  /// True while a cached snapshot is being reconciled with a fresh fetch
  /// in the background.
  final bool isRevalidating;

  DiscoveryHubState copyWith({bool? isRevalidating}) => DiscoveryHubState(
    profileDetails: profileDetails,
    profileError: profileError,
    likes: likes,
    unseenCount: unseenCount,
    matches: matches,
    isRevalidating: isRevalidating ?? this.isRevalidating,
  );

  Map<String, dynamic> toCache() => {
    'profileDetails': profileDetails,
    'likes': likes,
    'unseenCount': unseenCount,
    'matches': matches,
  };
}

/// Owns fetching + secure-storage caching + stale-while-revalidate
/// reconciliation for a discovery hub tab's profile status, likes inbox,
/// and matches list - shared by DatingTab/FriendsTab/ProfessionalTab
/// (`mode` is `'dating'|'friends'|'professional'`) instead of each tab
/// independently duplicating the same three fetches. Per-mode business
/// logic (field saves, orbit toggle, overlays, record-actions) stays in
/// each tab, applied to this provider's raw JSON via their existing
/// parsing methods.
@riverpod
class DiscoveryHubController extends _$DiscoveryHubController {
  final Dio _dio = createDio();
  bool _disposed = false;

  @override
  Future<DiscoveryHubState> build(String mode) async {
    ref.onDispose(() => _disposed = true);

    final cached = await DiscoveryHubCache.read(mode);
    if (cached != null) {
      unawaited(
        _fetchFresh().then((fresh) {
          if (_disposed) return;
          state = AsyncData(fresh);
        }),
      );
      return DiscoveryHubState.fromCache(cached).copyWith(
        isRevalidating: true,
      );
    }

    return _fetchFresh();
  }

  /// Re-fetches immediately and applies the result once it lands - used
  /// after a mutation (save, orbit toggle, match action) so the cache and
  /// any other tab instance stay in sync, and by overlays' own pull-to-
  /// refresh callbacks. Callers keep their own optimistic local state, so
  /// this is safe to leave un-awaited when its result isn't otherwise needed.
  Future<void> refresh() async {
    final fresh = await _fetchFresh();
    if (_disposed) return;
    state = AsyncData(fresh);
  }

  Future<DiscoveryHubState> _fetchFresh() async {
    final tab = _tabParam[mode]!;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return const DiscoveryHubState(
        profileDetails: null,
        profileError: 'Not signed in.',
        likes: [],
        unseenCount: 0,
        matches: [],
      );
    }

    final config = AppConfig.current;
    // All three start immediately (Dart futures run eagerly on creation) -
    // awaited below in the order each result is needed, not the order
    // that determines concurrency.
    final profileFuture = _dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/profile/details',
    );
    final likesFuture = _dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/likes',
      queryParameters: {'tab': tab},
    );
    final matchesFuture = _dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/matches',
      queryParameters: {'tab': tab},
    );

    Map<String, dynamic>? profileDetails;
    String? profileError;
    try {
      final response = await profileFuture;
      if (response.statusCode == 200 && response.data != null) {
        profileDetails = response.data;
      } else {
        profileError = 'Failed to fetch profile status.';
      }
    } on Exception catch (e) {
      profileError = e.toString();
    }

    var likes = <Map<String, dynamic>>[];
    var unseenCount = 0;
    try {
      final response = await likesFuture;
      if (response.statusCode == 200 && response.data != null) {
        final rawLikes = response.data!['likes'];
        likes = rawLikes is List
            ? List<Map<String, dynamic>>.from(
                rawLikes.cast<Map<String, dynamic>>(),
              )
            : [];
        unseenCount = (response.data!['unseen_count'] as num?)?.toInt() ?? 0;
      }
    } on Exception {
      // Best-effort, matches the tabs' existing silent-fail-and-continue
      // behavior for likes - only profile-status failures block the tab.
    }

    var matches = <Map<String, dynamic>>[];
    try {
      final response = await matchesFuture;
      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data!['matches'];
        matches = raw is List ? raw.cast<Map<String, dynamic>>() : [];
      }
    } on Exception {
      // Best-effort, same as likes above.
    }

    final fresh = DiscoveryHubState(
      profileDetails: profileDetails,
      profileError: profileError,
      likes: likes,
      unseenCount: unseenCount,
      matches: matches,
    );
    // Only cache a snapshot whose profile status actually loaded - never
    // let a transient profile-fetch failure overwrite a previously-good
    // cache with a null profileDetails.
    if (profileError == null) {
      unawaited(DiscoveryHubCache.write(mode, fresh.toCache()));
    }
    return fresh;
  }
}

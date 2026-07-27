import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'presence_provider.g.dart';

class PresenceInfo {
  const PresenceInfo({required this.isOnline, required this.lastActiveAt});

  /// Both null means: no active match, the peer's Active Status is off, or
  /// they've never been active - deliberately indistinguishable so a
  /// client can't infer the privacy setting.
  final bool? isOnline;
  final DateTime? lastActiveAt;
}

/// Polls a peer's presence every 30s while something is watching this
/// provider (e.g. the chat conversation page's app bar). Polling rather
/// than a dedicated realtime channel keeps this "nice to have" signal off
/// the Postgres-changes path entirely.
@riverpod
class PeerPresence extends _$PeerPresence {
  Timer? _timer;
  late final Dio _dio;

  @override
  Future<PresenceInfo> build(String peerUserId) async {
    _dio = createDio();
    ref.onDispose(() {
      _timer?.cancel();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    return _fetch();
  }

  Future<void> refresh() async {
    final info = await _fetch();
    state = AsyncData(info);
  }

  Future<PresenceInfo> _fetch() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      return const PresenceInfo(isOnline: null, lastActiveAt: null);
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/chat/presence/$peerUserId',
      );
      final data = response.data;
      final rawLastActive = data?['last_active_at'] as String?;
      return PresenceInfo(
        isOnline: data?['is_online'] as bool?,
        lastActiveAt: rawLastActive != null
            ? DateTime.parse(rawLastActive)
            : null,
      );
    } on Exception {
      return const PresenceInfo(isOnline: null, lastActiveAt: null);
    }
  }
}

/// Sends this device's own presence heartbeat. Call `beat()` every ~60s
/// while a chat screen is foregrounded, and `goOffline()` on
/// background/dispose.
mixin PresenceHeartbeat {
  // A single Dio instance reused for the app's lifetime - `beat()` is called
  // repeatedly (every ~60s while a chat screen is foregrounded) outside any
  // widget/provider lifecycle, so there's no natural dispose hook to close
  // a per-call instance with.
  static final Dio _dio = createDio();

  static Future<void> beat({bool isOnline = true}) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;
    try {
      await _dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/chat/presence/heartbeat',
        data: {'is_online': isOnline},
      );
    } on Exception {
      // Best-effort - a missed heartbeat just means presence looks stale
      // for up to 90s, not a user-visible failure.
    }
  }
}

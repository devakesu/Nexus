// The background messaging isolate entry point causes the analyzer to
// misidentify this file as an executable entry point.

import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/navigation/app_router.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level background message handler - must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

const _kDenialDialogShownKey = 'fcm_denial_dialog_shown';

class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static StreamSubscription<RemoteMessage>? _foregroundSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Register the FCM background handler. Call once in main() after Firebase init.
  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// Initialise after the user authenticates. Safe to call multiple times -
  /// subsequent calls only re-register the device token.
  static Future<void> initialize() async {
    if (_initialized) {
      await _getAndRegisterToken();
      return;
    }
    _initialized = true;

    await _requestAndHandlePermission();

    final token = await _getAndRegisterToken();
    if (kDebugMode) debugPrint('[FCM] Token: $token');

    _tokenRefreshSub = _messaging.onTokenRefresh.listen(_registerToken);
    _foregroundSub = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial.data);

    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _handleNotificationTap(message.data),
    );
  }

  /// Returns the current system permission status without requesting anything.
  static Future<AuthorizationStatus> getPermissionStatus() async {
    final s = await _messaging.getNotificationSettings();
    return s.authorizationStatus;
  }

  /// Opens the OS notification settings for this app.
  /// Android → notification channels page; iOS → app settings.
  static Future<void> openNotificationSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  /// Deactivates the FCM token on the server. Call before sign-out.
  static Future<void> unregisterToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;
      final dio = createDio();
      await dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/devices/unregister',
        data: {'fcm_token': token},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
    } on Object catch (e) {
      debugPrint('[FCM] Failed to unregister token: $e');
    }
  }

  static Future<void> dispose() async {
    _initialized = false;
    await _foregroundSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _tokenRefreshSub = null;
  }

  // ---------------------------------------------------------------------------
  // Permission flow
  // ---------------------------------------------------------------------------

  static Future<void> _requestAndHandlePermission() async {
    final result = await _messaging.requestPermission();
    final status = result.authorizationStatus;
    if (kDebugMode) debugPrint('[FCM] Permission: $status');

    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      // Clear any stale "dialog shown" flag so it can re-show if ever revoked.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kDenialDialogShownKey);
      return;
    }

    if (status == AuthorizationStatus.denied) {
      // Only show our dialog once per denial sequence - the OS dialog already
      // ran during this or a prior call; avoid nagging on every restart.
      final prefs = await SharedPreferences.getInstance();
      final alreadyShown = prefs.getBool(_kDenialDialogShownKey) ?? false;
      if (alreadyShown) return;

      final context = ErrorHandler.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      // Show first - no async gap between the mounted-check and this call.
      // Flag is written only after the dialog has actually been displayed.
      await showPermissionDeniedDialog(context);
      await prefs.setBool(_kDenialDialogShownKey, true);
    }
  }

  /// Show the "enable notifications" dialog. Exposed so the settings page can
  /// call it when the user taps the tile while permission is denied.
  static Future<void> showPermissionDeniedDialog(BuildContext context) async {
    if (!context.mounted) return;
    final navigator =
        Navigator.maybeOf(context) ?? ErrorHandler.navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push<void>(
      DialogRoute<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: _PermissionDeniedDialog(
            onOpenSettings: () async {
              Navigator.of(ctx).pop();
              await openNotificationSettings();
            },
            onDismiss: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Token registration
  // ---------------------------------------------------------------------------

  static Future<String?> _getAndRegisterToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _registerToken(token);
      return token;
    } on Object catch (e) {
      debugPrint('[FCM] Failed to get token: $e');
      return null;
    }
  }

  static Future<void> _registerToken(String token) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;
      final dio = createDio();
      await dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/devices/register',
        data: {
          'fcm_token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
    } on Object catch (e) {
      debugPrint('[FCM] Failed to register token: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Message handling
  // ---------------------------------------------------------------------------

  static void _handleForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    _showInAppToast(
      title: n.title ?? '',
      body: n.body ?? '',
      type: (message.data['type'] as String?) ?? '',
      data: message.data,
    );
  }

  static void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (kDebugMode) debugPrint('[FCM] Tapped: type=$type');

    if (type == 'chat_message') {
      final conversationId = data['conversation_id'] as String?;
      final actorId = data['actor_id'] as String?;
      if (conversationId == null || actorId == null) return;

      unawaited(
        goRouter.push(
          '/chat-conversation',
          extra: {
            'conversationId': conversationId,
            'matchedUserId': actorId,
            'tab': (data['tab'] as String?) ?? 'Dating',
            'name': (data['name'] as String?) ?? 'Nexus user',
            'profilePic': null,
          },
        ),
      );
      return;
    }

    if (type == 'meetup_safety_reminder') {
      // The event's title is E2E encrypted and this push never carried it -
      // land in the conversation itself, where the event card (already
      // decrypted client-side) has the "Set up a safety check-in" shortcut.
      final conversationId = data['conversation_id'] as String?;
      final peerId = data['peer_id'] as String?;
      if (conversationId == null || peerId == null) return;

      unawaited(
        goRouter.push(
          '/chat-conversation',
          extra: {
            'conversationId': conversationId,
            'matchedUserId': peerId,
            'tab': (data['tab'] as String?) ?? 'Dating',
            'name': 'Nexus user',
            'profilePic': null,
          },
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // In-app foreground toast
  // ---------------------------------------------------------------------------

  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void _showInAppToast({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) {
    final state = ErrorHandler.navigatorKey.currentState;
    if (state == null) return;

    _dismissTimer?.cancel();
    _activeEntry?.remove();
    _activeEntry = null;

    final overlayState = state.overlay;
    if (overlayState == null) return;

    final (IconData icon, Color accent) = switch (type) {
      'superlike' => (Icons.star_rounded, const Color(0xFFFACC15)),
      'match' => (Icons.favorite_rounded, AppColors.pulsarPink),
      _ => (Icons.favorite_border_rounded, AppColors.primaryTeal),
    };

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 12,
        left: 16,
        right: 16,
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                entry?.remove();
                _dismissTimer?.cancel();
                _activeEntry = null;
                _handleNotificationTap(data);
              },
              child:
                  Container(
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF161B26,
                          ).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, color: accent, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (title.isNotEmpty)
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      body,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                entry?.remove();
                                _dismissTimer?.cancel();
                                _activeEntry = null;
                              },
                              child: const Icon(
                                Icons.close,
                                color: Colors.white38,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .slideY(
                        begin: -0.5,
                        end: 0,
                        duration: 300.ms,
                        curve: Curves.easeOutBack,
                      )
                      .fadeIn(duration: 250.ms),
            ),
          ),
        ),
      ),
    );

    _activeEntry = entry;
    overlayState.insert(entry);
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      try {
        entry?.remove();
      } on Object catch (_) {}
      _activeEntry = null;
    });
  }
}

// ---------------------------------------------------------------------------
// Permission denied dialog widget
// ---------------------------------------------------------------------------

const List<String> _kNotificationDependentFeatures = [
  'Triggering Emergency SOS during a meetup - it fires from a live notification',
  'Meetup & event reminders',
  'Safety check-in prompts',
];

class _PermissionDeniedDialog extends StatelessWidget {
  const _PermissionDeniedDialog({
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.primaryTeal;

    return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: accent,
                    size: 32,
                  ),
                ).animate().scale(
                  begin: const Offset(0.7, 0.7),
                  duration: 400.ms,
                  curve: Curves.elasticOut,
                ),
                const SizedBox(height: 20),
                Text(
                  'Enable Notifications',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "Stay in the loop when someone likes you, super likes you, gets a new match, or sends you a message. You won't miss a connection.",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    height: 1.55,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFD97706),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Also required for',
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._kNotificationDependentFeatures.map(
                        (feature) => Padding(
                          padding: const EdgeInsets.only(bottom: 4, left: 26),
                          child: Text(
                            '•  $feature',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: const Color(0xFF92400E),
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onOpenSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Open Settings',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Not Now',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .scale(
          begin: const Offset(0.92, 0.92),
          duration: 250.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 200.ms);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/secure_preferences.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

const _kOngoingNotificationId = 9001;
const _kDueNotificationId = 9002;
const _kOngoingChannelId = 'meetup_safety_ongoing';
const _kDueChannelId = 'meetup_safety_checkin';
const _kOngoingPayload = 'meetup_safety_ongoing';
const _kDuePayload = 'meetup_safety_checkin_due';

const String kSessionEndRetryTaskName = 'com.devakesu.nexus.sessionEndRetry';
const String _kSessionEndRetryUniqueName = 'session-end-retry';
const _kPrefPendingSessionCleanups = 'meetup_safety_pending_session_cleanups';

const _kPrefActive = 'meetup_safety_active';
const _kPrefIntervalSeconds = 'meetup_safety_interval_seconds';
const _kPrefNextCheckInEpochMs = 'meetup_safety_next_checkin_epoch_ms';
const _kPrefLabel = 'meetup_safety_label';
const _kPrefServerSessionId = 'meetup_safety_server_session_id';
const _kPrefMirrorStartPending = 'meetup_safety_mirror_start_pending';

/// Notification action ids, shared between the ongoing ambient notification
/// and the check-in-due full-screen notification.
///
/// Tapping any of these currently just brings the app forward to the
/// relevant screen - wiring real SOS/call/inform side effects from a
/// background isolate (without opening the app) is a later phase.
abstract final class MeetupSafetyNotificationActions {
  static const sos = 'meetup_safety_sos';
  static const call112 = 'meetup_safety_call_112';
  static const informContacts = 'meetup_safety_inform_contacts';
  static const imSafe = 'meetup_safety_im_safe';
}

/// Result of [MeetupSafetySession.ensureAndroidPermissions] - which of the
/// Android settings-gated permissions the check-in-due alert depends on are
/// actually granted. `false` doesn't necessarily mean the user just denied
/// it: `requestExactAlarmsPermission`/`requestFullScreenIntentPermission`
/// open a system Settings screen and don't wait for the user to come back,
/// so it can also mean "not yet granted, user was just sent to Settings".
/// Either way, callers should warn rather than block on an incomplete
/// result - the ongoing notification and local exact-alarm loop still work
/// best-effort regardless.
class MeetupSafetyPermissionStatus {
  const MeetupSafetyPermissionStatus({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
    required this.fullScreenIntentGranted,
  });

  const MeetupSafetyPermissionStatus.allGranted()
    : notificationsGranted = true,
      exactAlarmsGranted = true,
      fullScreenIntentGranted = true;

  final bool notificationsGranted;
  final bool exactAlarmsGranted;
  final bool fullScreenIntentGranted;

  bool get allGranted =>
      notificationsGranted && exactAlarmsGranted && fullScreenIntentGranted;
}

/// Owns the recurring Meetup Safety check-in loop: start once, check in
/// repeatedly at a fixed interval, until stopped. State is persisted so a
/// relaunch mid-session restores correctly, and the check-in deadline is
/// backed by an OS-scheduled exact alarm (not just an in-Dart timer) so it
/// survives the app process being killed by Android.
class MeetupSafetySession extends ChangeNotifier {
  MeetupSafetySession._();

  static final MeetupSafetySession instance = MeetupSafetySession._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  bool _initialized = false;
  bool _alertScreenShowing = false;
  Timer? _dueTimer;

  bool isActive = false;
  Duration checkInInterval = const Duration(hours: 1);
  DateTime? nextCheckInAt;
  String checkInLabel = '';

  /// Server-side mirror of this session (app/db/safety.py's safety_sessions
  /// table), used by the dead-man's-switch escalation job. Null if the
  /// mirror call failed - the local exact-alarm loop is unaffected either
  /// way, this is purely an additional safety net.
  String? _serverSessionId;

  /// Exposed so SOS/inform alerts can be tagged with the session they
  /// happened during (see SafetyAlertApi.sendAlert's sessionId param) - that
  /// link is what lets the Milestone E trusted-contact portal show a
  /// session's location/evidence.
  String? get serverSessionId => _serverSessionId;

  /// Bumped on every start()/end() so a slow-to-resolve _mirrorStart() from
  /// an earlier start() can tell it's been superseded (e.g. the user tapped
  /// End almost immediately after Start) and clean up the server-side row it
  /// just created instead of leaving (or writing over current state with)
  /// an orphaned "active" session the dead-man's-switch would later escalate.
  int _sessionGeneration = 0;

  /// Sets up notification channels and restores any session that was active
  /// before the app was last closed. Call once from main() after Firebase/
  /// Supabase init, before the app's first frame.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tz_data.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } on Exception {
      // Falls back to the timezone package's default (UTC) - exact-alarm
      // scheduling still works, just anchored to UTC wall-clock if the
      // device's real zone couldn't be resolved.
    }

    const androidInit = AndroidInitializationSettings(
      'ic_notification_silhouette',
    );
    // Not const: DarwinNotificationAction.plain(...) is a non-const factory,
    // so this whole tree can't be a compile-time constant.
    final darwinInit = DarwinInitializationSettings(
      // Also attempts the Critical Alert interruption level; inert unless
      // Apple ever grants that entitlement for this app (a business-side
      // request, not a code change) - Time-Sensitive is what actually ships.
      requestCriticalPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          _kDueChannelId,
          actions: [
            DarwinNotificationAction.plain(
              MeetupSafetyNotificationActions.imSafe,
              "I'm Safe",
            ),
            DarwinNotificationAction.plain(
              MeetupSafetyNotificationActions.sos,
              'SOS',
            ),
          ],
        ),
      ],
    );

    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: androidInit,
          iOS: darwinInit,
        ),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
    } on Object catch (e) {
      debugPrint(
        '[Safety] Failed to initialize with ic_notification, falling back: $e',
      );
      const fallbackInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: InitializationSettings(
          android: fallbackInit,
          iOS: darwinInit,
        ),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
    }

    // Peek at whether a check-in was left active from a prior session -
    // `_restore()` below reads the same pref, so this doesn't add a real
    // extra read (SharedPreferences caches in memory after first access).
    final prefs = await SecurePreferences.getInstance();
    final hasActiveSession = await prefs.getBool(_kPrefActive) ?? false;

    if (Platform.isAndroid && hasActiveSession) {
      // A check-in is already active, so `_restore()` below is about to
      // (re)post its notifications - the channels must exist before that
      // happens, so this stays on the blocking startup path.
      await _createAndroidChannels();
    }

    await _restore();

    if (Platform.isAndroid && !hasActiveSession) {
      // Common case: no active check-in, so nothing needs these channels
      // yet. Defer past first frame, same pattern as
      // handleAppLaunchFromNotification() in main.dart.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_createAndroidChannels());
      });
    }
  }

  Future<void> _createAndroidChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannelGroup(
      const AndroidNotificationChannelGroup(
        'safety',
        'Meetup Safety',
        description: 'Meetup Safety notifications',
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kOngoingChannelId,
        'Meetup Safety (active)',
        description:
            'The persistent alert panel shown while a Meetup Safety '
            'check-in is active.',
        importance: Importance.low,
        playSound: false,
        groupId: 'safety',
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kDueChannelId,
        'Meetup Safety check-in',
        description:
            "Alerts you when it's time to check in during Meetup Safety.",
        importance: Importance.max,
        groupId: 'safety',
      ),
    );
  }

  /// Call once at startup, after the navigator is ready, to handle a cold
  /// launch caused by tapping (or Android auto-launching over the lock
  /// screen) the check-in-due notification.
  Future<void> handleAppLaunchFromNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      final payload = details!.notificationResponse?.payload;
      if (payload == _kDuePayload) _showAlertScreenIfNeeded();
    }
  }

  Future<void> _restore() async {
    final prefs = await SecurePreferences.getInstance();
    final active = await prefs.getBool(_kPrefActive) ?? false;
    if (!active) return;

    final intervalSeconds = await prefs.getInt(_kPrefIntervalSeconds);
    final nextEpochMs = await prefs.getInt(_kPrefNextCheckInEpochMs);
    if (intervalSeconds == null || nextEpochMs == null) return;

    isActive = true;
    checkInInterval = Duration(seconds: intervalSeconds);
    nextCheckInAt = DateTime.fromMillisecondsSinceEpoch(nextEpochMs);
    checkInLabel = await prefs.getString(_kPrefLabel) ?? '';
    _serverSessionId = await prefs.getString(_kPrefServerSessionId);
    final mirrorStartPending =
        await prefs.getBool(_kPrefMirrorStartPending) ?? false;
    final isOverdue = nextCheckInAt!.isBefore(DateTime.now());

    await _showOngoingNotification();
    if (isOverdue) {
      // Overdue session: immediately trigger the check-in due screen and await user confirmation
      _armDueTimer();
    } else {
      await _scheduleDueNotification();
      _armDueTimer();
    }
    notifyListeners();

    if (_serverSessionId == null || mirrorStartPending) {
      unawaited(_mirrorStart(++_sessionGeneration));
    }
  }

  Future<void> _persist() async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setBool(_kPrefActive, value: isActive);
    if (!isActive) {
      await prefs.remove(_kPrefIntervalSeconds);
      await prefs.remove(_kPrefNextCheckInEpochMs);
      await prefs.remove(_kPrefLabel);
      await prefs.remove(_kPrefServerSessionId);
      await prefs.remove(_kPrefMirrorStartPending);
      return;
    }
    await prefs.setInt(_kPrefIntervalSeconds, checkInInterval.inSeconds);
    await prefs.setInt(
      _kPrefNextCheckInEpochMs,
      nextCheckInAt!.millisecondsSinceEpoch,
    );
    await prefs.setString(_kPrefLabel, checkInLabel);
    if (_serverSessionId != null) {
      await prefs.setString(_kPrefServerSessionId, _serverSessionId!);
      await prefs.remove(_kPrefMirrorStartPending);
    } else {
      await prefs.setBool(_kPrefMirrorStartPending, value: true);
    }
  }

  /// Best-effort battery percentage + connection type, for the heartbeat
  /// payload that lets the server-side dead-man's-switch tell "phone likely
  /// died" from "something happened while the phone was fine". Either half
  /// can come back null if the platform call fails - the session mirror
  /// calls tolerate missing values.
  Future<(int?, String?)> _gatherDeviceState() async {
    int? batteryPercent;
    try {
      batteryPercent = await _battery.batteryLevel;
    } on Exception {
      batteryPercent = null;
    }

    String? connectionType;
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        connectionType = 'wifi';
      } else if (results.contains(ConnectivityResult.mobile)) {
        connectionType = 'cellular';
      } else {
        connectionType = 'offline';
      }
    } on Exception {
      connectionType = null;
    }

    return (batteryPercent, connectionType);
  }

  static Future<List<String>> _readPendingCleanups() async {
    final prefs = await SecurePreferences.getInstance();
    final raw = await prefs.getString(_kPrefPendingSessionCleanups);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } on Exception {
      return [];
    }
  }

  static Future<void> _writePendingCleanups(List<String> sessionIds) async {
    final prefs = await SecurePreferences.getInstance();
    if (sessionIds.isEmpty) {
      await prefs.remove(_kPrefPendingSessionCleanups);
      return;
    }
    await prefs.setString(
      _kPrefPendingSessionCleanups,
      jsonEncode(sessionIds.toSet().toList()),
    );
  }

  static Future<void> _enqueueSessionCleanup(String sessionId) async {
    final existing = await _readPendingCleanups();
    if (!existing.contains(sessionId)) {
      existing.add(sessionId);
      await _writePendingCleanups(existing);
    }
  }

  static Future<void> _dequeueSessionCleanup(String sessionId) async {
    final existing = await _readPendingCleanups();
    existing.remove(sessionId);
    await _writePendingCleanups(existing);
  }

  static Future<void> _scheduleSessionEndRetry() async {
    try {
      await Workmanager().registerOneOffTask(
        _kSessionEndRetryUniqueName,
        kSessionEndRetryTaskName,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } on Exception catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        level: ErrorLevel.warning,
        showUi: false,
        customMessage: 'Failed to schedule Workmanager session-end retry',
      );
    }
  }

  /// Attempts to end all pending orphaned sessions.
  static Future<bool> drainPendingEndSessions() async {
    final pending = await _readPendingCleanups();
    if (pending.isEmpty) return true;

    final remaining = <String>[];
    for (final sessionId in pending) {
      try {
        await SafetyAlertApi.endSession(sessionId);
      } on Exception catch (e, stackTrace) {
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          level: ErrorLevel.warning,
          showUi: false,
          customMessage:
              'Failed to clean up orphaned safety session $sessionId',
        );
        remaining.add(sessionId);
      }
    }

    await _writePendingCleanups(remaining);
    return remaining.isEmpty;
  }

  /// Mirrors a freshly-started session server-side. Fire-and-forget from
  /// start() - the local exact-alarm loop is what actually keeps the check-in
  /// loop working, this just widens the safety net to cover the device going
  /// unreachable entirely.
  Future<void> _mirrorStart(int generation) async {
    final at = nextCheckInAt;
    if (at == null) return;
    final (batteryPercent, connectionType) = await _gatherDeviceState();
    final sessionId = await SafetyAlertApi.startSession(
      intervalSeconds: checkInInterval.inSeconds,
      label: checkInLabel,
      nextCheckInAt: at,
      batteryPercent: batteryPercent,
      connectionType: connectionType,
    );
    if (sessionId == null) return;
    if (generation != _sessionGeneration) {
      // Superseded by a later start()/end() while this request was in
      // flight - the server already created a row for it, so clean that up
      // reliably with persistent retry rather than leaving an orphaned active session behind.
      await _enqueueSessionCleanup(sessionId);
      try {
        await SafetyAlertApi.endSession(sessionId);
        await _dequeueSessionCleanup(sessionId);
      } on Exception {
        await _scheduleSessionEndRetry();
      }
      return;
    }
    _serverSessionId = sessionId;
    final prefs = await SecurePreferences.getInstance();
    await prefs.setString(_kPrefServerSessionId, sessionId);
    await prefs.remove(_kPrefMirrorStartPending);
  }

  /// Heartbeats the server mirror on a successful check-in (or an extend,
  /// which is really just a reschedule) - resets its escalation counter the
  /// same way the local reschedule resets the exact alarm.
  Future<void> _mirrorCheckin() async {
    final sessionId = _serverSessionId;
    final at = nextCheckInAt;
    if (sessionId == null || at == null) return;
    final (batteryPercent, connectionType) = await _gatherDeviceState();
    await SafetyAlertApi.checkinSession(
      sessionId: sessionId,
      nextCheckInAt: at,
      batteryPercent: batteryPercent,
      connectionType: connectionType,
    );
  }

  Future<void> _mirrorEnd() async {
    final sessionId = _serverSessionId;
    _serverSessionId = null;
    final prefs = await SecurePreferences.getInstance();
    await prefs.remove(_kPrefServerSessionId);
    await prefs.remove(_kPrefMirrorStartPending);
    if (sessionId == null) return;
    await _enqueueSessionCleanup(sessionId);
    try {
      await SafetyAlertApi.endSession(sessionId);
      await _dequeueSessionCleanup(sessionId);
    } on Exception {
      await _scheduleSessionEndRetry();
    }
  }

  /// Requests the two Android 14+ settings-gated permissions this feature
  /// needs, plus the Android 13+ notification permission, and reports which
  /// were actually granted (see [MeetupSafetyPermissionStatus] for caveats
  /// on what a `false` here means). Call this explicitly wherever the user
  /// opts into check-ins (Safety Center's "Start Check-In" via [start], and
  /// the in-chat event planner's check-in toggle) so a denial can be
  /// surfaced right away rather than failing silently later when the alert
  /// is actually due.
  Future<MeetupSafetyPermissionStatus> ensureAndroidPermissions() async {
    if (!Platform.isAndroid) {
      return const MeetupSafetyPermissionStatus.allGranted();
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final notificationsGranted =
        await android?.requestNotificationsPermission() ?? false;
    final exactAlarmsGranted =
        await android?.requestExactAlarmsPermission() ?? false;
    final fullScreenIntentGranted =
        await android?.requestFullScreenIntentPermission() ?? false;
    return MeetupSafetyPermissionStatus(
      notificationsGranted: notificationsGranted,
      exactAlarmsGranted: exactAlarmsGranted,
      fullScreenIntentGranted: fullScreenIntentGranted,
    );
  }

  /// Starts a recurring Meetup Safety check-in session.
  ///
  /// Requests required Android 13+/14+ permissions (notifications, exact alarms,
  /// full-screen intents) and returns [MeetupSafetyPermissionStatus]. Callers
  /// should inspect `permissionStatus.allGranted` to display appropriate user
  /// guidance or warning toasts if OS settings prevent full alert delivery.
  Future<MeetupSafetyPermissionStatus> start({
    required Duration interval,
    required String label,
  }) async {
    final permissionStatus = await ensureAndroidPermissions();
    final generation = ++_sessionGeneration;
    isActive = true;
    checkInInterval = interval;
    checkInLabel = label;
    nextCheckInAt = DateTime.now().add(interval);
    await _persist();
    await _showOngoingNotification();
    await _scheduleDueNotification();
    _armDueTimer();
    notifyListeners();
    unawaited(_mirrorStart(generation));
    return permissionStatus;
  }

  Future<void> checkInSafely() async {
    if (!isActive) return;
    nextCheckInAt = DateTime.now().add(checkInInterval);
    await _persist();
    await _showOngoingNotification();
    await _scheduleDueNotification();
    _armDueTimer();
    notifyListeners();
    unawaited(_mirrorCheckin());
  }

  Future<void> extend(Duration extra) async {
    if (!isActive || nextCheckInAt == null) return;
    nextCheckInAt = nextCheckInAt!.add(extra);
    await _persist();
    await _showOngoingNotification();
    await _scheduleDueNotification();
    _armDueTimer();
    notifyListeners();
    unawaited(_mirrorCheckin());
  }

  Future<void> end() async {
    ++_sessionGeneration;
    isActive = false;
    nextCheckInAt = null;
    checkInLabel = '';
    _dueTimer?.cancel();
    _dueTimer = null;
    await _persist();
    await _plugin.cancel(id: _kOngoingNotificationId);
    await _plugin.cancel(id: _kDueNotificationId);
    notifyListeners();
    unawaited(_mirrorEnd());
  }

  void _armDueTimer() {
    _dueTimer?.cancel();
    final at = nextCheckInAt;
    if (at == null) return;
    final delay = at.difference(DateTime.now());
    _dueTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _showAlertScreenIfNeeded,
    );
  }

  /// Pushes the full-screen check-in alert if a session is active and it
  /// isn't already showing. Safe to call redundantly - both the in-app timer
  /// and a tapped/auto-launched notification can each trigger this for the
  /// same deadline, only the first call actually navigates.
  void _showAlertScreenIfNeeded() {
    if (!isActive || _alertScreenShowing) return;
    final navigator = ErrorHandler.navigatorKey.currentState;
    if (navigator == null) return;
    _alertScreenShowing = true;

    if (Platform.isAndroid) {
      unawaited(
        const MethodChannel('com.devakesu.apps.nexus/safety')
            .invokeMethod<void>('setShowWhenLocked', {'show': true})
            .catchError((_) {}),
      );
    }

    unawaited(
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const CheckInAlertScreen(),
            ),
          )
          .then((_) {
            _alertScreenShowing = false;
            if (Platform.isAndroid) {
              unawaited(
                const MethodChannel('com.devakesu.apps.nexus/safety')
                    .invokeMethod<void>('setShowWhenLocked', {'show': false})
                    .catchError((_) {}),
              );
            }
          }),
    );
  }

  Future<void> _showOngoingNotification() async {
    final at = nextCheckInAt;
    if (at == null) return;
    final androidDetails = AndroidNotificationDetails(
      _kOngoingChannelId,
      'Meetup Safety (active)',
      channelDescription:
          'The persistent alert panel shown while a Meetup Safety check-in '
          'is active.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      usesChronometer: true,
      chronometerCountDown: true,
      when: at.millisecondsSinceEpoch,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.status,
      actions: const [
        AndroidNotificationAction(
          MeetupSafetyNotificationActions.sos,
          'SOS',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          MeetupSafetyNotificationActions.call112,
          'Call 112',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          MeetupSafetyNotificationActions.informContacts,
          'Inform Contacts',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );
    await _plugin.show(
      id: _kOngoingNotificationId,
      title: 'Meetup Safety active',
      body: checkInLabel.isEmpty
          ? 'Checking in periodically to keep you safe.'
          : checkInLabel,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: _kOngoingPayload,
    );
  }

  Future<void> _scheduleDueNotification() async {
    await _plugin.cancel(id: _kDueNotificationId);
    final at = nextCheckInAt;
    if (at == null) return;

    const androidDetails = AndroidNotificationDetails(
      _kDueChannelId,
      'Meetup Safety check-in',
      channelDescription:
          "Alerts you when it's time to check in during Meetup Safety.",
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      actions: [
        AndroidNotificationAction(
          MeetupSafetyNotificationActions.imSafe,
          "I'm Safe",
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          MeetupSafetyNotificationActions.sos,
          'SOS',
          showsUserInterface: true,
        ),
      ],
    );
    const darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: _kDueChannelId,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.zonedSchedule(
      id: _kDueNotificationId,
      title: 'Time to check in',
      body: checkInLabel.isEmpty
          ? "Let us know you're safe."
          : 'Check in for "$checkInLabel"',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: _kDuePayload,
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.payload == _kDuePayload ||
        response.actionId == MeetupSafetyNotificationActions.imSafe) {
      _showAlertScreenIfNeeded();
      return;
    }
    // SOS / Call 112 / Inform Contacts tapped from the ongoing notification:
    // for now this just foregrounds the app to the alert screen, where the
    // same buttons are available - see the class doc comment above.
    if (response.actionId == MeetupSafetyNotificationActions.sos ||
        response.actionId == MeetupSafetyNotificationActions.call112 ||
        response.actionId == MeetupSafetyNotificationActions.informContacts) {
      _showAlertScreenIfNeeded();
    }
  }

  @override
  void dispose() {
    _dueTimer?.cancel();
    super.dispose();
  }
}

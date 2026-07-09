import 'dart:async';
import 'dart:io' show Platform;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:nexus/screens/settings/checkin_alert_screen.dart';
import 'package:nexus/services/safety_alert_api.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _kOngoingNotificationId = 9001;
const _kDueNotificationId = 9002;
const _kOngoingChannelId = 'meetup_safety_ongoing';
const _kDueChannelId = 'meetup_safety_checkin';
const _kOngoingPayload = 'meetup_safety_ongoing';
const _kDuePayload = 'meetup_safety_checkin_due';

const _kPrefActive = 'meetup_safety_active';
const _kPrefIntervalSeconds = 'meetup_safety_interval_seconds';
const _kPrefNextCheckInEpochMs = 'meetup_safety_next_checkin_epoch_ms';
const _kPrefLabel = 'meetup_safety_label';
const _kPrefServerSessionId = 'meetup_safety_server_session_id';

/// Notification action ids, shared between the ongoing ambient notification
/// and the check-in-due full-screen notification.
///
/// Tapping any of these currently just brings the app forward to the
/// relevant screen — wiring real SOS/call/inform side effects from a
/// background isolate (without opening the app) is a later phase.
abstract final class MeetupSafetyNotificationActions {
  static const sos = 'meetup_safety_sos';
  static const call112 = 'meetup_safety_call_112';
  static const informContacts = 'meetup_safety_inform_contacts';
  static const imSafe = 'meetup_safety_im_safe';
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
  /// mirror call failed — the local exact-alarm loop is unaffected either
  /// way, this is purely an additional safety net.
  String? _serverSessionId;

  /// Exposed so SOS/inform alerts can be tagged with the session they
  /// happened during (see SafetyAlertApi.sendAlert's sessionId param) — that
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
      // Falls back to the timezone package's default (UTC) — exact-alarm
      // scheduling still works, just anchored to UTC wall-clock if the
      // device's real zone couldn't be resolved.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Not const: DarwinNotificationAction.plain(...) is a non-const factory,
    // so this whole tree can't be a compile-time constant.
    final darwinInit = DarwinInitializationSettings(
      // Also attempts the Critical Alert interruption level; inert unless
      // Apple ever grants that entitlement for this app (a business-side
      // request, not a code change) — Time-Sensitive is what actually ships.
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

    await _plugin.initialize(
      settings: InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kOngoingChannelId,
          'Meetup Safety (active)',
          description:
              'The persistent alert panel shown while a Meetup Safety '
              'check-in is active.',
          importance: Importance.low,
          playSound: false,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kDueChannelId,
          'Meetup Safety check-in',
          description:
              "Alerts you when it's time to check in during Meetup Safety.",
          importance: Importance.max,
        ),
      );
    }

    await _restore();
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
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool(_kPrefActive) ?? false;
    if (!active) return;

    final intervalSeconds = prefs.getInt(_kPrefIntervalSeconds);
    final nextEpochMs = prefs.getInt(_kPrefNextCheckInEpochMs);
    if (intervalSeconds == null || nextEpochMs == null) return;

    isActive = true;
    checkInInterval = Duration(seconds: intervalSeconds);
    nextCheckInAt = DateTime.fromMillisecondsSinceEpoch(nextEpochMs);
    checkInLabel = prefs.getString(_kPrefLabel) ?? '';
    _serverSessionId = prefs.getString(_kPrefServerSessionId);
    // Defensively re-post rather than assume the previous ongoing
    // notification / scheduled alarm survived whatever caused this restart
    // (idempotent either way - this is the same call every checkInSafely()/
    // extend() already makes).
    await _showOngoingNotification();
    await _scheduleDueNotification();
    _armDueTimer();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefActive, isActive);
    if (!isActive) {
      await prefs.remove(_kPrefIntervalSeconds);
      await prefs.remove(_kPrefNextCheckInEpochMs);
      await prefs.remove(_kPrefLabel);
      await prefs.remove(_kPrefServerSessionId);
      return;
    }
    await prefs.setInt(_kPrefIntervalSeconds, checkInInterval.inSeconds);
    await prefs.setInt(
      _kPrefNextCheckInEpochMs,
      nextCheckInAt!.millisecondsSinceEpoch,
    );
    await prefs.setString(_kPrefLabel, checkInLabel);
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

  /// Mirrors a freshly-started session server-side. Fire-and-forget from
  /// start() — the local exact-alarm loop is what actually keeps the check-in
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
      // rather than leaving an orphaned active session behind.
      unawaited(SafetyAlertApi.endSession(sessionId));
      return;
    }
    _serverSessionId = sessionId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefServerSessionId, sessionId);
  }

  /// Heartbeats the server mirror on a successful check-in (or an extend,
  /// which is really just a reschedule) — resets its escalation counter the
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
    if (sessionId == null) return;
    await SafetyAlertApi.endSession(sessionId);
  }

  /// Requests the two Android 14+ settings-gated permissions this feature
  /// needs. Both open a system settings screen rather than an in-app dialog,
  /// so this is only called once, right as the user starts a session.
  Future<void> _ensureAndroidPermissions() async {
    if (!Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    await android?.requestFullScreenIntentPermission();
  }

  Future<void> start({
    required Duration interval,
    required String label,
  }) async {
    await _ensureAndroidPermissions();
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
    checkInInterval += extra;
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
  /// isn't already showing. Safe to call redundantly — both the in-app timer
  /// and a tapped/auto-launched notification can each trigger this for the
  /// same deadline, only the first call actually navigates.
  void _showAlertScreenIfNeeded() {
    if (!isActive || _alertScreenShowing) return;
    final navigator = ErrorHandler.navigatorKey.currentState;
    if (navigator == null) return;
    _alertScreenShowing = true;
    unawaited(
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const CheckInAlertScreen(),
            ),
          )
          .then((_) => _alertScreenShowing = false),
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
    // same buttons are available — see the class doc comment above.
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

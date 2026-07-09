import 'package:dio/dio.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/services/safety_contacts.dart';
import 'package:nexus/utils/network_utils.dart';

class SafetyAlertResult {
  const SafetyAlertResult({
    required this.alertId,
    required this.contactsNotified,
    required this.contactsTotal,
  });

  final String alertId;
  final int contactsNotified;
  final int contactsTotal;
}

/// Backend client for the Meetup Safety alert/contacts-sync endpoints (see
/// app/api/safety.py). Every call is best-effort from the caller's
/// perspective — network/auth failures are caught and surfaced as a bool/
/// null rather than thrown, since a failed sync or alert-send shouldn't
/// crash the in-app SOS flow (the in-app mock confirmation still shows).
class SafetyAlertApi {
  SafetyAlertApi._();

  static final Dio _dio = createDio();

  /// Mirrors the full trusted-contact list server-side so alerts can be
  /// sent without the device online. Fire-and-forget from callers.
  static Future<bool> syncContacts(List<SafetyContact> contacts) async {
    try {
      final token = await NetworkUtils.requireAccessToken();
      await _dio.put<void>(
        '${AppConfig.current.backendUrl}/api/v1/safety/contacts',
        data: {
          'contacts': contacts
              .map((c) => {'name': c.name, 'phone': c.phone})
              .toList(),
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on Exception {
      return false;
    }
  }

  /// Sends the SOS/inform SMS fan-out. Returns null if the request itself
  /// failed (no network, not signed in, etc.) — the in-app SOS flow treats
  /// null the same as "couldn't reach the server" and still shows its own
  /// confirmation, per the Meetup Safety plan's mock-action scoping.
  static Future<SafetyAlertResult?> sendAlert({
    required String alertType,
    String? sessionId,
    String? sessionLabel,
    String? eventLabel,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final token = await NetworkUtils.requireAccessToken();
      final response = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/safety/alert',
        data: {
          'alert_type': alertType,
          if (sessionId != null && sessionId.isNotEmpty)
            'session_id': sessionId,
          if (sessionLabel != null && sessionLabel.isNotEmpty)
            'session_label': sessionLabel,
          if (eventLabel != null && eventLabel.isNotEmpty)
            'event_label': eventLabel,
          if (latitude != null && longitude != null)
            'current_location': {'lat': latitude, 'lng': longitude},
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data;
      if (data == null) return null;
      return SafetyAlertResult(
        alertId: data['id'] as String,
        contactsNotified: data['contacts_notified'] as int,
        contactsTotal: data['contacts_total'] as int,
      );
    } on Exception {
      return null;
    }
  }

  /// Registers an encrypted Digital Witness evidence segment already
  /// uploaded to the safety_evidence storage bucket.
  static Future<bool> registerEvidence({
    required String alertId,
    required String storagePath,
    required String mediaKeyBase64,
    required String contentType,
    double? durationSeconds,
  }) async {
    try {
      final token = await NetworkUtils.requireAccessToken();
      await _dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/safety/evidence',
        data: {
          'alert_id': alertId,
          'storage_path': storagePath,
          'media_key_base64': mediaKeyBase64,
          'content_type': contentType,
          'duration_seconds': ?durationSeconds,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on Exception {
      return false;
    }
  }

  /// Mirrors a freshly-started check-in loop server-side so the dead-man's
  /// -switch scheduler (app/services/reminder_scheduler.py) has something to
  /// poll. Returns null if the request failed — the local exact-alarm loop
  /// still runs either way, this just widens the safety net.
  static Future<String?> startSession({
    required int intervalSeconds,
    required String label,
    required DateTime nextCheckInAt,
    int? batteryPercent,
    String? connectionType,
  }) async {
    try {
      final token = await NetworkUtils.requireAccessToken();
      final response = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/safety/session/start',
        data: {
          'interval_seconds': intervalSeconds,
          if (label.isNotEmpty) 'label': label,
          'next_checkin_at': nextCheckInAt.toUtc().toIso8601String(),
          'battery_percent': ?batteryPercent,
          'connection_type': ?connectionType,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data?['id'] as String?;
    } on Exception {
      return null;
    }
  }

  /// Heartbeats a successful "I'm Safe" check-in — proves the device is fine
  /// and resets the server-side escalation counter back to zero.
  static Future<bool> checkinSession({
    required String sessionId,
    required DateTime nextCheckInAt,
    int? batteryPercent,
    String? connectionType,
  }) async {
    try {
      final token = await NetworkUtils.requireAccessToken();
      await _dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/safety/session/checkin',
        data: {
          'session_id': sessionId,
          'next_checkin_at': nextCheckInAt.toUtc().toIso8601String(),
          'battery_percent': ?batteryPercent,
          'connection_type': ?connectionType,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on Exception {
      return false;
    }
  }

  static Future<bool> endSession(String sessionId) async {
    try {
      final token = await NetworkUtils.requireAccessToken();
      await _dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/safety/session/end',
        data: {'session_id': sessionId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on Exception {
      return false;
    }
  }
}

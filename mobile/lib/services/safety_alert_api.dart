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
}

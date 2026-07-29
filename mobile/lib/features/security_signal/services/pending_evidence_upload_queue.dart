import 'dart:convert';
import 'dart:io';

import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/secure_preferences.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/security_signal/services/signal/media_crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

/// Task name Digital Witness evidence retries are registered under. Handled
/// by the shared dispatcher in background_prekey_task.dart - Workmanager
/// only supports one globally-registered callback dispatcher per app, so
/// every background task type routes through that single entry point rather
/// than each calling `Workmanager().initialize()` itself.
const String kEvidenceUploadRetryTaskName =
    'com.devakesu.nexus.evidenceUploadRetry';
const String _kEvidenceUploadRetryUniqueName = 'evidence-upload-retry';

const _kPrefKey = 'digital_witness_pending_evidence_v1';

class _PendingSegment {
  _PendingSegment({
    required this.filePath,
    required this.alertId,
    required this.durationSeconds,
  });

  factory _PendingSegment.fromJson(Map<String, dynamic> json) =>
      _PendingSegment(
        filePath: json['filePath'] as String,
        alertId: json['alertId'] as String,
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
      );

  final String filePath;
  final String alertId;
  final double durationSeconds;

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'alertId': alertId,
    'durationSeconds': durationSeconds,
  };
}

/// Durable handoff point for Digital Witness evidence segments between being
/// captured and successfully uploaded+registered server-side.
///
/// Segments are queued to disk *before* the network attempt (see
/// [enqueueAll]), so a flaky connection or a process kill mid-upload during
/// an emergency loses nothing - the next [drain] (an immediate
/// fire-and-forget attempt, the next app launch, or the background
/// Workmanager retry) picks up wherever it left off, instead of the segment
/// being deleted on a failed attempt.
class PendingEvidenceUploadQueue {
  PendingEvidenceUploadQueue._();

  static Future<List<_PendingSegment>> _read() async {
    final prefs = await SecurePreferences.getInstance();
    final raw = await prefs.getString(_kPrefKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(_PendingSegment.fromJson)
        .toList();
  }

  static Future<void> _write(List<_PendingSegment> segments) async {
    final prefs = await SecurePreferences.getInstance();
    if (segments.isEmpty) {
      await prefs.remove(_kPrefKey);
      return;
    }
    await prefs.setString(
      _kPrefKey,
      jsonEncode(segments.map((s) => s.toJson()).toList()),
    );
  }

  /// Persists every captured segment to the queue. Call this and await it
  /// before doing anything fire-and-forget with the segments - once this
  /// returns, the segments survive an app kill regardless of what happens to
  /// the actual upload afterwards.
  static Future<void> enqueueAll({
    required String alertId,
    required List<(File, double)> segments,
  }) async {
    if (segments.isEmpty) return;
    final existing = await _read();
    existing.addAll(
      segments.map(
        (s) => _PendingSegment(
          filePath: s.$1.path,
          alertId: alertId,
          durationSeconds: s.$2,
        ),
      ),
    );
    await _write(existing);
  }

  /// Attempts to upload+register every currently-queued segment. Successful
  /// ones are dequeued and their local plaintext file deleted; failures are
  /// left queued for the next drain. Returns true once the queue is fully
  /// cleared (including "there was never anything queued").
  static Future<bool> drain() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      // Not signed in on this device right now - leave the queue as-is for
      // a later drain rather than losing it.
      return true;
    }

    final pending = await _read();
    if (pending.isEmpty) return true;

    final storage = Supabase.instance.client.storage.from('safety_evidence');
    final remaining = <_PendingSegment>[];

    for (final segment in pending) {
      final file = File(segment.filePath);
      try {
        if (!file.existsSync()) {
          // Already gone (e.g. cleared by the OS) - nothing left to retry.
          continue;
        }
        final bytes = await file.readAsBytes();
        final encrypted = await MediaCrypto.instance.encrypt(bytes);
        final path = '$userId/${DateTime.now().microsecondsSinceEpoch}.enc';
        await storage.uploadBinary(path, encrypted.ciphertext);
        await SafetyAlertApi.registerEvidence(
          alertId: segment.alertId,
          storagePath: path,
          mediaKeyBase64: encrypted.mediaKeyBase64,
          contentType: 'video',
          durationSeconds: segment.durationSeconds,
        );
        try {
          await file.delete();
        } on Exception {
          // Best-effort cleanup - upload already succeeded.
        }
      } on Exception catch (e, stackTrace) {
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          level: ErrorLevel.warning,
          showUi: false,
          customMessage:
              'Evidence upload failed for alertId=${segment.alertId}',
        );
        remaining.add(segment);
      }
    }

    await _write(remaining);
    return remaining.isEmpty;
  }

  /// Schedules a network-constrained Workmanager retry with the OS's own
  /// backoff, so queued evidence still gets uploaded even if the app isn't
  /// reopened again soon (or the immediate [drain] call had no connectivity
  /// at all). Safe to call unconditionally - `existingWorkPolicy: replace`
  /// keeps this idempotent, and the dispatcher itself is a no-op if the
  /// queue turns out to already be empty by the time it runs.
  ///
  /// Deliberately does NOT call `Workmanager().initialize()` - that's
  /// already done once at app startup (see schedulePrekeyReplenishment in
  /// background_prekey_task.dart) with the single shared dispatcher that
  /// also handles [kEvidenceUploadRetryTaskName].
  static Future<void> scheduleBackgroundRetry() async {
    await Workmanager().registerOneOffTask(
      _kEvidenceUploadRetryUniqueName,
      kEvidenceUploadRetryTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}

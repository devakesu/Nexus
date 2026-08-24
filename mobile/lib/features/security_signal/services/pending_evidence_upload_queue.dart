import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/secure_preferences.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
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
    this.storagePath,
    this.encryptedMediaKeyBase64,
  });

  factory _PendingSegment.fromJson(Map<String, dynamic> json) =>
      _PendingSegment(
        filePath: json['filePath'] as String,
        alertId: json['alertId'] as String,
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
        storagePath: json['storagePath'] as String?,
        encryptedMediaKeyBase64:
            (json['encryptedMediaKeyBase64'] ?? json['mediaKeyBase64'])
                as String?,
      );

  final String filePath;
  final String alertId;
  final double durationSeconds;
  String? storagePath;
  String? encryptedMediaKeyBase64;

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'alertId': alertId,
    'durationSeconds': durationSeconds,
    if (storagePath != null) 'storagePath': storagePath,
    if (encryptedMediaKeyBase64 != null)
      'encryptedMediaKeyBase64': encryptedMediaKeyBase64,
  };

  Future<String?> getDecryptedMediaKey() async {
    if (encryptedMediaKeyBase64 == null) return null;
    try {
      final ciphertext = base64Decode(encryptedMediaKeyBase64!);
      final decrypted = await LocalKeyVault.instance.decryptBytes(ciphertext);
      return utf8.decode(decrypted);
    } on Object catch (_) {
      // Fallback for legacy unencrypted key
      return encryptedMediaKeyBase64;
    }
  }

  static Future<String?> encryptMediaKey(String? rawKeyBase64) async {
    if (rawKeyBase64 == null) return null;
    try {
      final encryptedBytes = await LocalKeyVault.instance.encryptBytes(
        Uint8List.fromList(utf8.encode(rawKeyBase64)),
      );
      return base64Encode(encryptedBytes);
    } on Object catch (_) {
      return rawKeyBase64;
    }
  }
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

  /// Persists every captured segment to the queue with vault-encrypted media keys.
  /// Call this and await it before doing anything fire-and-forget with the segments.
  static Future<void> enqueueAll({
    required String alertId,
    required List<(File, double, String)> segments,
  }) async {
    if (segments.isEmpty) return;
    final existing = await _read();
    for (final s in segments) {
      final encKey = await _PendingSegment.encryptMediaKey(s.$3);
      existing.add(
        _PendingSegment(
          filePath: s.$1.path,
          alertId: alertId,
          durationSeconds: s.$2,
          encryptedMediaKeyBase64: encKey,
        ),
      );
    }
    await _write(existing);
  }

  /// Attempts to upload+register every currently-queued segment. Successful
  /// ones are dequeued and their local encrypted file deleted; failures are
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
        var storagePath = segment.storagePath;
        var mediaKeyBase64 = await segment.getDecryptedMediaKey();

        // Upload encrypted ciphertext if not already uploaded in a previous attempt
        if (storagePath == null) {
          if (!file.existsSync()) {
            // File is gone and was never uploaded - nothing left to retry.
            continue;
          }
          final fileBytes = await file.readAsBytes();
          Uint8List uploadBytes;
          if (mediaKeyBase64 == null) {
            // Backwards compatibility if an unencrypted legacy file was queued
            final encrypted = await MediaCrypto.instance.encrypt(fileBytes);
            uploadBytes = encrypted.ciphertext;
            mediaKeyBase64 = encrypted.mediaKeyBase64;
            segment.encryptedMediaKeyBase64 =
                await _PendingSegment.encryptMediaKey(mediaKeyBase64);
          } else {
            uploadBytes = fileBytes;
          }
          final path = '$userId/${DateTime.now().microsecondsSinceEpoch}.enc';
          await storage.uploadBinary(path, uploadBytes);
          storagePath = path;
          segment.storagePath = storagePath;
        }

        // Register evidence with backend using the uploaded storage path and key
        if (mediaKeyBase64 != null) {
          await SafetyAlertApi.registerEvidence(
            alertId: segment.alertId,
            storagePath: storagePath,
            mediaKeyBase64: mediaKeyBase64,
            contentType: 'video',
            durationSeconds: segment.durationSeconds,
          );
        }

        try {
          if (file.existsSync()) {
            await file.delete();
          }
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

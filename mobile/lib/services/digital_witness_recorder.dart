import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexus/services/pending_evidence_upload_queue.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Drives Silent SOS's "Digital Witness" recording: an explicit, foreground,
/// user-initiated camera+mic recording - never a covert background capture.
/// See the Meetup Safety plan's Milestone C notes for why keeping this overt
/// matters both for the UX and for the legal framing (recording a situation
/// you're an active participant in, in the open, is on much firmer ground
/// than covert surveillance).
///
/// Platform reality, not a bug:
/// - Android: SafetyRecordingService.kt's foreground service keeps this
///   app's *process* alive while backgrounded/locked, which is necessary
///   but not by itself a guarantee that the `camera` plugin's capture
///   session survives - Android has restricted background camera access
///   since API 28, and whether a foreground service is enough to avoid
///   that in practice is unverified on a real device. To be safe either
///   way, this class runs the same pause/resume segment handling on
///   Android as iOS (below): if backgrounding does interrupt the camera,
///   the segment gets finalized cleanly instead of corrupted; if it
///   doesn't, this just means slightly shorter segments, which is harmless.
/// - iOS: the instant the app leaves the foreground, iOS suspends the
///   camera session for every third-party app, no exception. This class
///   finalizes the current segment cleanly when that happens (rather than
///   letting iOS kill it mid-write) and starts a fresh segment if the app
///   returns to foreground before Silent SOS ends. Only audio would
///   continue in the background on iOS, which is a smaller follow-up, not
///   built here.
class DigitalWitnessRecorder extends ChangeNotifier
    with WidgetsBindingObserver {
  DigitalWitnessRecorder._();

  static final DigitalWitnessRecorder instance = DigitalWitnessRecorder._();

  static const _channel = MethodChannel('com.devakesu.apps.nexus/safety');

  CameraController? controller;
  bool isRecording = false;
  DateTime? _segmentStartedAt;
  final List<(File file, double durationSeconds)> _segments = [];
  String? _alertId;

  Duration get elapsed => _segmentStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_segmentStartedAt!);

  /// Starts the foreground recording. [alertId] links captured segments to
  /// the SOS alert row for later upload/registration - pass null if the
  /// alert failed to reach the backend; the local recording still proceeds
  /// (it's valuable evidence with or without connectivity), it just won't
  /// have anywhere server-side to register itself once stopped. Returns
  /// false if camera/mic permission was denied or no camera is available -
  /// callers should fall back to just the SMS alert already sent, not block
  /// the whole Silent SOS flow on this.
  Future<bool> start({required String? alertId}) async {
    if (isRecording) return true;
    _alertId = alertId;

    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    if (!statuses.values.every((s) => s.isGranted)) return false;

    final cameras = await availableCameras();
    if (cameras.isEmpty) return false;
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final newController = CameraController(backCamera, ResolutionPreset.medium);
    try {
      await newController.initialize();
      await newController.prepareForVideoRecording();
      await newController.startVideoRecording();
    } on CameraException {
      await newController.dispose();
      return false;
    }
    controller = newController;

    _segmentStartedAt = DateTime.now();
    isRecording = true;

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('startRecording');
      } on PlatformException {
        // Non-fatal: recording still works while the app stays foreground,
        // it just won't survive backgrounding/locking without the service.
      }
    }

    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
    return true;
  }

  /// Stops recording, tears down the camera, and durably queues whatever
  /// segments were captured for upload (see [PendingEvidenceUploadQueue]).
  Future<void> stop() async {
    if (!isRecording) return;
    WidgetsBinding.instance.removeObserver(this);
    await _finalizeCurrentSegment();
    isRecording = false;
    _segmentStartedAt = null;

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('stopRecording');
      } on PlatformException {
        // Ignore - nothing Dart-side depends on this succeeding.
      }
    }

    await controller?.dispose();
    controller = null;
    notifyListeners();

    await _handoffSegments();
  }

  Future<void> _finalizeCurrentSegment() async {
    final c = controller;
    final startedAt = _segmentStartedAt;
    if (c == null || !c.value.isRecordingVideo) return;
    try {
      final file = await c.stopVideoRecording();
      final durationSeconds = startedAt == null
          ? 0.0
          : DateTime.now().difference(startedAt).inMilliseconds / 1000.0;
      _segments.add((File(file.path), durationSeconds));
    } on CameraException {
      // Best-effort - a failed segment shouldn't crash the SOS flow.
    }
  }

  /// Hands captured segments off to the durable upload queue, then attempts
  /// an immediate upload. The handoff itself is awaited (it's just a local
  /// disk write) so a process kill right after stop() returns can't drop
  /// evidence that was never recorded anywhere; the actual encrypt+upload
  /// network work stays fire-and-forget, backed up by a background retry
  /// task in case the immediate attempt can't finish (no connectivity, app
  /// killed mid-upload, etc).
  Future<void> _handoffSegments() async {
    final alertId = _alertId;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final segments = List<(File, double)>.from(_segments);
    _segments.clear();
    _alertId = null;

    if (alertId == null || userId == null) {
      // No alert to register against (e.g. the SMS alert send failed) -
      // still clean up the local files rather than leaking them on disk
      // forever, even though the evidence itself can't be preserved.
      for (final (file, _) in segments) {
        try {
          await file.delete();
        } on Exception {
          // Best-effort cleanup.
        }
      }
      return;
    }

    await PendingEvidenceUploadQueue.enqueueAll(
      alertId: alertId,
      segments: segments,
    );
    unawaited(PendingEvidenceUploadQueue.drain());
    unawaited(PendingEvidenceUploadQueue.scheduleBackgroundRetry());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Applied on both platforms, not just iOS - see the class doc comment
    // on why Android's foreground service isn't assumed to guarantee the
    // camera session survives backgrounding either. Harmless if it does
    // (just an extra segment boundary); a real safety net if it doesn't.
    if (!isRecording) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_finalizeCurrentSegment());
    } else if (state == AppLifecycleState.resumed &&
        controller != null &&
        !controller!.value.isRecordingVideo) {
      unawaited(_resumeSegment());
    }
  }

  Future<void> _resumeSegment() async {
    final c = controller;
    if (c == null) return;
    try {
      await c.startVideoRecording();
      _segmentStartedAt = DateTime.now();
    } on CameraException {
      // Leave as-is - the next explicit stop() finalizes whatever was
      // captured so far.
    }
  }
}

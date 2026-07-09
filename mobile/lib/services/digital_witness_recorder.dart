import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexus/services/safety_alert_api.dart';
import 'package:nexus/services/signal/media_crypto.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Drives Silent SOS's "Digital Witness" recording: an explicit, foreground,
/// user-initiated camera+mic recording — never a covert background capture.
/// See the Meetup Safety plan's Milestone C notes for why keeping this overt
/// matters both for the UX and for the legal framing (recording a situation
/// you're an active participant in, in the open, is on much firmer ground
/// than covert surveillance).
///
/// Platform reality, not a bug:
/// - Android: recording continues even if the screen locks/app backgrounds,
///   via a lightweight foreground service (SafetyRecordingService.kt) that
///   keeps the process alive — the camera plugin itself keeps running in
///   the Flutter engine the whole time.
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
  final List<File> _segments = [];
  String? _alertId;

  Duration get elapsed => _segmentStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(_segmentStartedAt!);

  /// Starts the foreground recording. [alertId] links captured segments to
  /// the SOS alert row for later upload/registration — pass null if the
  /// alert failed to reach the backend; the local recording still proceeds
  /// (it's valuable evidence with or without connectivity), it just won't
  /// have anywhere server-side to register itself once stopped. Returns
  /// false if camera/mic permission was denied or no camera is available —
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

  /// Stops recording, tears down the camera, and kicks off (fire-and-forget)
  /// encrypting and uploading whatever segments were captured.
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
        // Ignore — nothing Dart-side depends on this succeeding.
      }
    }

    await controller?.dispose();
    controller = null;
    notifyListeners();

    unawaited(_uploadSegments());
  }

  Future<void> _finalizeCurrentSegment() async {
    final c = controller;
    if (c == null || !c.value.isRecordingVideo) return;
    try {
      final file = await c.stopVideoRecording();
      _segments.add(File(file.path));
    } on CameraException {
      // Best-effort — a failed segment shouldn't crash the SOS flow.
    }
  }

  Future<void> _uploadSegments() async {
    final alertId = _alertId;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final segments = List<File>.from(_segments);
    _segments.clear();
    _alertId = null;
    if (alertId == null || userId == null) return;

    final storage = Supabase.instance.client.storage.from('safety_evidence');
    for (final segment in segments) {
      try {
        final bytes = await segment.readAsBytes();
        final encrypted = await MediaCrypto.instance.encrypt(bytes);
        final path = '$userId/${DateTime.now().microsecondsSinceEpoch}.enc';
        await storage.uploadBinary(path, encrypted.ciphertext);
        await SafetyAlertApi.registerEvidence(
          alertId: alertId,
          storagePath: path,
          mediaKeyBase64: encrypted.mediaKeyBase64,
          contentType: 'video',
        );
      } on Exception {
        // Best-effort — ciphertext is never left half-uploaded in a
        // readable state, so a failed segment just has no server-side
        // evidence rather than a corrupt one.
      } finally {
        try {
          await segment.delete();
        } on Exception {
          // Local temp file cleanup is best-effort too.
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isRecording || !Platform.isIOS) return;
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
      // Leave as-is — the next explicit stop() finalizes whatever was
      // captured so far.
    }
  }
}

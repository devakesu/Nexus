import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nexus/core/utils/secure_storage_options.dart';

/// Service to handle application security checks, including debugger detection,
/// overlays, and screen recording/mirroring detection.
class SecurityService {
  SecurityService._();

  static const _channel = MethodChannel('com.devakesu.apps.nexus/security');
  static final StreamController<void> _overlayController =
      StreamController<void>.broadcast();

  /// Stream emitting events when a native UI overlay/touch obscuration is detected.
  static Stream<void> get onOverlayDetected => _overlayController.stream;

  static Timer? _debuggerPollTimer;

  /// Initializes the security channel listener and continuous security monitors.
  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOverlayDetected') {
        _overlayController.add(null);
      }
    });
    startContinuousDebuggerMonitoring();
  }

  /// Starts a periodic background timer to detect post-startup debugger attachment.
  static void startContinuousDebuggerMonitoring() {
    _debuggerPollTimer?.cancel();
    _debuggerPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(checkDebugger());
    });
  }

  /// Stops continuous debugger monitoring (used for tests).
  static void stopContinuousDebuggerMonitoringForTesting() {
    _debuggerPollTimer?.cancel();
    _debuggerPollTimer = null;
  }

  /// Checks if a debugger is currently connected to the application.
  static Future<bool> isDebuggerConnected() async {
    try {
      final connected = await _channel.invokeMethod<bool>(
        'isDebuggerConnected',
      );
      return connected ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// Checks for debuggers, and if found, wipes all secure storage keys,
  /// purges temporary evidence files from disk, and terminates the app.
  static Future<void> checkDebugger() async {
    if (await isDebuggerConnected()) {
      try {
        // 1. Wipe key vault and tokens
        await AppSecureStorage.instance.deleteAll();
        // 2. Best-effort purge of temporary evidence directory files from disk
        final tempDir = Directory.systemTemp;
        if (tempDir.existsSync()) {
          await for (final entity in tempDir.list()) {
            if (entity.path.contains('digital_witness') ||
                entity.path.endsWith('.enc') ||
                entity.path.endsWith('.mp4') ||
                entity.path.endsWith('.mov')) {
              try {
                await entity.delete(recursive: true);
              } on Object catch (_) {}
            }
          }
        }
      } on Object catch (_) {}
      // 3. Immediately exit without network calls
      exit(0);
    }
  }

  /// Toggles the native window secure flag (FLAG_SECURE) to block recording/screenshots.
  static Future<void> setSecureFlag({required bool secure}) async {
    try {
      await _channel.invokeMethod('setSecureFlag', {'secure': secure});
    } on Object catch (_) {}
  }

  /// Checks if screen recording or mirroring is currently active.
  static Future<bool> isScreenRecordingOrMirroring() async {
    try {
      final active = await _channel.invokeMethod<bool>(
        'isScreenRecordingOrMirroring',
      );
      return active ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// Notifier updated whenever screen recording or external display mirroring is detected.
  static final ValueNotifier<bool> isScreenRecordingDetected =
      ValueNotifier<bool>(false);

  /// Checks if screen recording or mirroring is currently active and updates [isScreenRecordingDetected].
  static Future<bool> checkScreenRecording() async {
    final active = await isScreenRecordingOrMirroring();
    isScreenRecordingDetected.value = active;
    return active;
  }

  static int _sensitiveScreenCount = 0;
  static bool _isAppBackgrounded = false;

  /// Whether any sensitive screen is currently mounted and active.
  static bool get isSensitiveScreenActive => _sensitiveScreenCount > 0;

  /// Number of currently mounted sensitive screens.
  static int get sensitiveScreenCount => _sensitiveScreenCount;

  /// Prepares the screen for sensitive data display (blocks recording/screenshots).
  static Future<void> enterSensitiveScreen() async {
    unawaited(checkDebugger());
    unawaited(checkScreenRecording());
    _sensitiveScreenCount++;
    if (_sensitiveScreenCount == 1 && !_isAppBackgrounded) {
      await setSecureFlag(secure: true);
    }
  }

  /// Disables sensitive screen protections once the screen is closed/disposed.
  static Future<void> exitSensitiveScreen() async {
    if (_sensitiveScreenCount > 0) {
      _sensitiveScreenCount--;
    }
    if (_sensitiveScreenCount == 0 && !_isAppBackgrounded) {
      await setSecureFlag(secure: false);
    }
  }

  /// Handles app lifecycle state changes for global screenshot privacy.
  static Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _isAppBackgrounded = true;
        await setSecureFlag(secure: true);
      case AppLifecycleState.resumed:
        _isAppBackgrounded = false;
        unawaited(checkDebugger());
        unawaited(checkScreenRecording());
        if (_sensitiveScreenCount == 0) {
          await setSecureFlag(secure: false);
        } else {
          await setSecureFlag(secure: true);
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Resets test state.
  static void resetSensitiveScreenCountForTesting() {
    _sensitiveScreenCount = 0;
    _isAppBackgrounded = false;
  }
}

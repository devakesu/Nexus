import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service to handle application security checks, including debugger detection,
/// overlays, and screen recording/mirroring detection.
class SecurityService {
  SecurityService._();

  static const _channel = MethodChannel('com.devakesu.apps.nexus/security');
  static final StreamController<void> _overlayController = StreamController<void>.broadcast();

  /// Stream emitting events when a native UI overlay/touch obscuration is detected.
  static Stream<void> get onOverlayDetected => _overlayController.stream;

  /// Initializes the security channel listener for callbacks from native code.
  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOverlayDetected') {
        _overlayController.add(null);
      }
    });
  }

  /// Checks if a debugger is currently connected to the application.
  static Future<bool> isDebuggerConnected() async {
    try {
      final connected = await _channel.invokeMethod<bool>('isDebuggerConnected');
      return connected ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// Checks for debuggers, and if found, wipes all secure storage keys and terminates the app.
  static Future<void> checkDebugger() async {
    if (await isDebuggerConnected()) {
      try {
        const storage = FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );
        await storage.deleteAll();
      } on Object catch (_) {}
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
      final active = await _channel.invokeMethod<bool>('isScreenRecordingOrMirroring');
      return active ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// Prepares the screen for sensitive data display (blocks recording/screenshots).
  static Future<void> enterSensitiveScreen() async {
    await setSecureFlag(secure: true);
  }

  /// Disables sensitive screen protections once the screen is closed/disposed.
  static Future<void> exitSensitiveScreen() async {
    await setSecureFlag(secure: false);
  }
}

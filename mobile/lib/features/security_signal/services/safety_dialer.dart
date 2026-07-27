import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexus/features/security_signal/services/safety_contacts.dart'
    show launchSafetyTel;

const _channel = MethodChannel('com.devakesu.apps.nexus/safety');

/// Calls an emergency number with as few taps as possible.
///
/// Android: places the call directly via a native `ACTION_CALL` (the
/// `CALL_PHONE` permission, requested here on first use) - no dialer, no
/// confirmation step. iOS never allows any third-party app to skip its own
/// "Call 112?" system confirmation, so it falls back to the existing
/// dialer-prefill flow via `tel:` - there's no API that changes that.
Future<void> callEmergencyNumber(BuildContext context, String number) async {
  if (Platform.isAndroid) {
    try {
      final placed = await _channel.invokeMethod<bool>('callDirect', {
        'number': number,
      });
      if (placed ?? false) return;
    } on Object catch (_) {
      // Falls through to the dialer-prefill path below (e.g. permission
      // denied, or the platform call itself failed).
    }
  }
  if (context.mounted) {
    await launchSafetyTel(context, 'tel:$number');
  }
}

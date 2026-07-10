import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SafetyContact {
  SafetyContact({required this.name, required this.phone});

  factory SafetyContact.fromJson(Map<String, dynamic> json) {
    return SafetyContact(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
    );
  }
  final String name;
  final String phone;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

const _kSecureStorageKey = 'safety_contacts';

const _kSecureStorageOptions = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// Loads trusted contacts, migrating any legacy SharedPreferences copy into
/// secure storage on first read (mirrors the migration `MeetupSafetyPage`
/// used to do inline).
Future<List<SafetyContact>> loadSafetyContacts() async {
  try {
    final val = await _kSecureStorageOptions.read(key: _kSecureStorageKey);
    if (val != null) {
      final list = jsonDecode(val) as List<dynamic>;
      return list
          .map((item) => SafetyContact.fromJson(item as Map<String, dynamic>))
          .toList();
    }
  } on Object catch (_) {
    // Gracefully fallback to legacy storage or empty list on corruption/decryption error.
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final legacyList = prefs.getStringList(_kSecureStorageKey);
    if (legacyList == null || legacyList.isEmpty) return [];

    final migrated = legacyList
        .map(
          (item) =>
              SafetyContact.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList();
    await saveSafetyContacts(migrated);
    await prefs.remove(_kSecureStorageKey);
    return migrated;
  } on Object catch (_) {
    return [];
  }
}

Future<void> saveSafetyContacts(List<SafetyContact> contacts) async {
  final encoded = jsonEncode(contacts.map((c) => c.toJson()).toList());
  await _kSecureStorageOptions.write(key: _kSecureStorageKey, value: encoded);
}

// ---------------------------------------------------------------------------
// Confirmation UI shown after the real SOS/inform SMS has already been sent
// (SafetyAlertApi.sendAlert) — these just give the user consistent visual
// feedback that it went out, wherever they're triggered from (MeetupSafetyPage,
// CheckInAlertScreen). They don't send anything themselves.
// ---------------------------------------------------------------------------

/// Shown when Silent SOS's Digital Witness recording couldn't start (camera/
/// mic permission denied, no camera available) — the SOS alert itself was
/// already sent for real, so this confirms that rather than implying nothing
/// happened.
Future<void> showSosFallbackDialog(
  BuildContext context, {
  required List<SafetyContact> contacts,
  VoidCallback? onRetryRecording,
}) async {
  final contactNames = contacts.map((c) => c.name).join(', ');
  final message = contacts.isEmpty
      ? 'Emergency SOS activated! Your alert is on its way.'
      : 'Emergency SOS activated! Your alert and last known location were '
            'sent to: $contactNames. Evidence recording could not start.';

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: const Icon(
        LucideIcons.shieldAlert,
        color: AppColors.error,
        size: 48,
      ).animate(onPlay: (c) => c.repeat()).shake(duration: 800.ms, hz: 4),
      title: Text(
        'Emergency Triggered',
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          color: AppColors.error,
        ),
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(fontSize: 14, height: 1.45),
      ),
      actions: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetryRecording != null) ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onRetryRecording();
                  },
                  child: Text(
                    'Retry Recording',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Dismiss',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Launches the dialer pre-filled with [number] (e.g. `tel:112`). Never
/// throws - an emergency call action failing silently with no feedback
/// (and no chance to retry) is worse than a caught error toast, since the
/// button otherwise looks like it did nothing.
Future<void> launchSafetyTel(BuildContext context, String number) async {
  try {
    final uri = Uri.parse(number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
  } on Object catch (_) {
    // Falls through to the error toast below.
  }
  if (context.mounted) {
    NexusToast.show(
      context,
      'Could not launch helpline dialer',
      type: NexusToastType.error,
    );
  }
}

/// Lighter-weight than a full SOS: confirms the real "inform" SMS
/// (SafetyAlertApi.sendAlert, already fired by the caller) went out, without
/// a countdown or confirmation dialog.
void showInformContactsToast(
  BuildContext context,
  List<SafetyContact> contacts,
) {
  if (contacts.isEmpty) {
    NexusToast.show(
      context,
      'Add a trusted contact first so we know who to alert.',
      type: NexusToastType.error,
    );
    return;
  }
  final contactNames = contacts.map((c) => c.name).join(', ');
  NexusToast.show(
    context,
    'Alert sent to $contactNames with your check-in status.',
    type: NexusToastType.success,
  );
}

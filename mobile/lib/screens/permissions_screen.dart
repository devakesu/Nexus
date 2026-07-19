import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/secure_preferences.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/scale_pressable.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionItem {
  const PermissionItem({
    required this.permission,
    required this.name,
    required this.description,
    required this.icon,
    required this.isCore,
    required this.reason,
  });

  final Permission permission;
  final String name;
  final String description;
  final IconData icon;
  final bool isCore;
  final String reason;
}

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({
    required this.onCompleted,
    super.key,
  });

  final VoidCallback onCompleted;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  Map<Permission, PermissionStatus> _statuses = {};
  bool _isLoading = true;
  bool _isApproximateLocation = false;

  List<PermissionItem> get _permissions {
    return [
      const PermissionItem(
        permission: Permission.notification,
        name: 'Push Notifications',
        description:
            'Optional • Required to receive instant safety alerts, chat messages, and check-in alarms.',
        icon: LucideIcons.bell,
        isCore: true,
        reason: "Required so you don't miss safety check-ins and messages.",
      ),
      const PermissionItem(
        permission: Permission.locationWhenInUse,
        name: 'Location Services',
        description:
            'Optional • Used to share your current location in chat and with Meetup Safety alerts or SOS.',
        icon: LucideIcons.mapPin,
        isCore: true,
        reason: 'Required for core safety features and meeting up.',
      ),
      if (Platform.isAndroid)
        const PermissionItem(
          permission: Permission.scheduleExactAlarm,
          name: 'Alarms & Reminders',
          description:
              'Optional • Required so Meetup Safety check-ins can trigger alarms exactly on time even in background.',
          icon: LucideIcons.clock,
          isCore: true,
          reason: 'Required for exact timing of safety check-ins.',
        ),
      if (Platform.isAndroid)
        const PermissionItem(
          permission: Permission.phone,
          name: 'Direct Phone Calling',
          description:
              'Optional • Required to place an SOS call to emergency services directly with zero taps.',
          icon: LucideIcons.phoneCall,
          isCore: false,
          reason: 'Used to call emergency lines instantly in SOS mode.',
        ),
      const PermissionItem(
        permission: Permission.camera,
        name: 'Camera Access',
        description:
            'Optional • Used for taking profile photos, sending images in chat, and recording video during a Silent SOS.',
        icon: LucideIcons.camera,
        isCore: false,
        reason: 'Used for profiles, chat media, and video evidence.',
      ),
      const PermissionItem(
        permission: Permission.microphone,
        name: 'Microphone Access',
        description:
            'Optional • Used for sending voice messages in chat and recording audio evidence during a Silent SOS.',
        icon: LucideIcons.mic,
        isCore: false,
        reason: 'Used for voice messages and audio evidence.',
      ),
      const PermissionItem(
        permission: Permission.contacts,
        name: 'Contacts Access',
        description:
            "Optional • Required to pick trusted safety contacts directly from your device's address book.",
        icon: LucideIcons.users,
        isCore: false,
        reason: 'Used to easily select and add trusted contacts.',
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkStatuses());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkStatuses());
    }
  }

  Future<void> _checkStatuses() async {
    final newStatuses = <Permission, PermissionStatus>{};
    for (final item in _permissions) {
      newStatuses[item.permission] = await item.permission.status;
    }

    var isApprox = false;
    final locStatus = newStatuses[Permission.locationWhenInUse];
    if (locStatus != null &&
        (locStatus.isGranted ||
            locStatus.isLimited ||
            locStatus.isProvisional)) {
      try {
        final accuracy = await Geolocator.getLocationAccuracy();
        if (accuracy == LocationAccuracyStatus.reduced) {
          isApprox = true;
        }
      } on Object catch (_) {}
    }

    if (mounted) {
      setState(() {
        _statuses = newStatuses;
        _isApproximateLocation = isApprox;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermission(PermissionItem item) async {
    final status = _statuses[item.permission];

    if (status != null &&
        (status.isGranted || status.isLimited || status.isProvisional)) {
      if (item.permission == Permission.locationWhenInUse &&
          _isApproximateLocation) {
        // Try requesting location again to see if they want to upgrade to precise from the system dialog
        final newStatus = await item.permission.request();
        await _checkStatuses();

        if (mounted) {
          setState(() {
            _statuses[item.permission] = newStatus;
          });
        }

        if (mounted && !_isApproximateLocation) {
          NexusToast.show(
            context,
            'Location accuracy upgraded to precise!',
            type: NexusToastType.success,
          );
          return;
        } else {
          _showPreciseLocationWarningDialog();
          return;
        }
      }

      if (mounted) {
        NexusToast.show(
          context,
          '${item.name} is already granted.',
          type: NexusToastType.success,
        );
      }
      return;
    }

    if (status == PermissionStatus.permanentlyDenied) {
      _showSettingsDialog(item);
      return;
    }

    final newStatus = await item.permission.request();

    if (mounted) {
      setState(() {
        _statuses[item.permission] = newStatus;
      });
    }

    if (newStatus.isPermanentlyDenied) {
      _showSettingsDialog(item);
    } else if (newStatus.isGranted ||
        newStatus.isLimited ||
        newStatus.isProvisional) {
      await _checkStatuses();

      if (item.permission == Permission.locationWhenInUse) {
        try {
          final accuracy = await Geolocator.getLocationAccuracy();
          if (accuracy == LocationAccuracyStatus.reduced) {
            _showPreciseLocationWarningDialog();
            return;
          }
        } on Object catch (_) {}
      }

      if (mounted) {
        NexusToast.show(
          context,
          '${item.name} granted successfully!',
          type: NexusToastType.success,
        );
      }
    } else if (newStatus.isDenied) {
      if (mounted) {
        NexusToast.show(
          context,
          '${item.name} permission was denied.',
          type: NexusToastType.error,
        );
      }
    }
  }

  void _showSettingsDialog(PermissionItem item) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Settings Required',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          content: Text(
            '${item.name} permission was previously denied. Please open system settings, tap "Permissions", and enable it manually for Nexus.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.manrope(
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(openAppSettings());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pulsarPink,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Open Settings',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreciseLocationWarningDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Precise Location Recommended',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          content: Text(
            'You granted approximate location access. Nexus requires precise location to accurately share your position in chat and locate you during emergency SOS check-ins. Please enable precise location in system settings under "Permissions".',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Keep Approximate',
                style: GoogleFonts.manrope(
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(openAppSettings());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pulsarPink,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Open Settings',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onContinue() async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setBool('permissions_page_completed', value: true);
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.canvas,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.pulsarPink),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Elegant Header Block
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.pulsarPink.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.shieldAlert,
                      color: AppColors.pulsarPink,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXUS',
                        style: GoogleFonts.orbitron(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: AppColors.pulsarPink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SECURE BOUNDARIES',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                          'Configure permissions',
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            height: 1.2,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.1, end: 0),
                    const SizedBox(height: 8),
                    Text(
                      'Configure device permissions to access core security features and social integration. All permissions are optional and can be managed anytime.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                    ).animate().fadeIn(delay: 50.ms, duration: 300.ms),
                    const SizedBox(height: 16),

                    // Tip Card for One-time grants
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.info,
                            color: AppColors.info,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Tip: Select 'While using the app' (rather than 'Only this time') and enable 'Precise location' (rather than 'Approximate') for Location, Camera, and Mic to ensure safety features work accurately.",
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppColors.inkMuted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 100.ms, duration: 350.ms),
                    const SizedBox(height: 24),

                    // Section: Core Permissions
                    _buildSectionHeader('CORE PERMISSIONS'),
                    const SizedBox(height: 12),
                    ..._permissions
                        .where((p) => p.isCore)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildPermissionCard(item),
                              )
                              .animate()
                              .fadeIn(
                                delay: (index * 50 + 150).ms,
                                duration: 400.ms,
                              )
                              .slideY(
                                begin: 0.05,
                                end: 0,
                                curve: Curves.easeOut,
                              );
                        }),
                    const SizedBox(height: 16),

                    // Section: Additional Permissions
                    _buildSectionHeader('ADDITIONAL PERMISSIONS'),
                    const SizedBox(height: 12),
                    ..._permissions
                        .where((p) => !p.isCore)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildPermissionCard(item),
                              )
                              .animate()
                              .fadeIn(
                                delay: (index * 50 + 250).ms,
                                duration: 400.ms,
                              )
                              .slideY(
                                begin: 0.05,
                                end: 0,
                                curve: Curves.easeOut,
                              );
                        }),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Continue Button Block
            Padding(
              padding: const EdgeInsets.all(24),
              child: ScalePressable(
                onTap: _onContinue,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.pulsarPink,
                        Color(0xFFE04B76),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.pulsarPink.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Continue to Nexus',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 350.ms, duration: 350.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.orbitron(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: AppColors.inkMuted,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildPermissionCard(PermissionItem item) {
    final status = _statuses[item.permission];
    final isGranted =
        status != null &&
        (status.isGranted || status.isLimited || status.isProvisional);
    final isPermanentlyDenied = status == PermissionStatus.permanentlyDenied;

    Color badgeBgColor;
    Color badgeTextColor;
    String badgeText;
    IconData badgeIcon;

    if (isGranted) {
      if (item.permission == Permission.locationWhenInUse &&
          _isApproximateLocation) {
        badgeBgColor = AppColors.warning.withValues(alpha: 0.1);
        badgeTextColor = AppColors.warning;
        badgeText = 'APPROXIMATE';
        badgeIcon = LucideIcons.alertTriangle;
      } else {
        badgeBgColor = AppColors.success.withValues(alpha: 0.1);
        badgeTextColor = AppColors.success;
        badgeText = 'GRANTED';
        badgeIcon = LucideIcons.check;
      }
    } else if (isPermanentlyDenied) {
      badgeBgColor = AppColors.error.withValues(alpha: 0.1);
      badgeTextColor = AppColors.error;
      badgeText = 'BLOCKED';
      badgeIcon = LucideIcons.alertTriangle;
    } else {
      badgeBgColor = AppColors.pulsarPink.withValues(alpha: 0.1);
      badgeTextColor = AppColors.pulsarPink;
      badgeText = 'GRANT';
      badgeIcon = LucideIcons.chevronRight;
    }

    final accentColor = item.isCore
        ? AppColors.pulsarPink
        : AppColors.primaryTeal;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderNeutral),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _requestPermission(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.icon,
                    color: accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            badgeText,
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: badgeTextColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            badgeIcon,
                            color: badgeTextColor,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.isCore
                            ? AppColors.pulsarPink.withValues(alpha: 0.1)
                            : AppColors.primaryTeal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'OPTIONAL',
                        style: GoogleFonts.manrope(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: item.isCore
                              ? AppColors.pulsarPink
                              : AppColors.primaryTeal,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

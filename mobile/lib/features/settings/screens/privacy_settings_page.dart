import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/app_refresh_notifier.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/consent_prompt_dialog.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/security_signal/services/safety_contacts.dart';
import 'package:nexus/features/security_signal/services/security_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FieldDescriptor {
  const _FieldDescriptor({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
}

final _kHideableFields = <_FieldDescriptor>[
  const _FieldDescriptor(
    key: 'display_gender',
    label: 'Gender',
    subtitle: 'Hide your gender identity from other profiles.',
    icon: LucideIcons.users,
  ),
  const _FieldDescriptor(
    key: 'display_sexuality',
    label: 'Sexuality',
    subtitle: 'Hide your sexual orientation from other profiles.',
    icon: LucideIcons.heart,
  ),
  const _FieldDescriptor(
    key: 'pronouns',
    label: 'Pronouns',
    subtitle: 'Hide your preferred pronouns from other profiles.',
    icon: LucideIcons.messageSquare,
  ),
  const _FieldDescriptor(
    key: 'hometown',
    label: 'Hometown',
    subtitle: 'Hide your hometown from other profiles.',
    icon: LucideIcons.home,
  ),
  const _FieldDescriptor(
    key: 'current_place',
    label: 'Current Place',
    subtitle: 'Hide your current city or location from other profiles.',
    icon: LucideIcons.mapPin,
  ),
  const _FieldDescriptor(
    key: 'campus_branch',
    label: 'Major / Branch',
    subtitle: 'Hide your academic branch or major from other profiles.',
    icon: LucideIcons.graduationCap,
  ),
  const _FieldDescriptor(
    key: 'religious_beliefs',
    label: 'Religious Beliefs',
    subtitle: 'Hide your religious beliefs from other profiles.',
    icon: LucideIcons.sun,
  ),
  const _FieldDescriptor(
    key: 'pets',
    label: 'Pets',
    subtitle: 'Hide your pet preferences from other profiles.',
    icon: LucideIcons.cat,
  ),
  const _FieldDescriptor(
    key: 'top_artists',
    label: 'Top Artists',
    subtitle: 'Hide your Spotify top artists from other profiles.',
    icon: LucideIcons.music,
  ),
  const _FieldDescriptor(
    key: 'causes_supported',
    label: 'Causes Supported',
    subtitle: 'Hide the causes you support from other profiles.',
    icon: LucideIcons.handHeart,
  ),
];

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  // Settings Signal - matches this page's parent Settings tab. Was
  // previously Safety Blue (#0284C7); Privacy Settings isn't a safety
  // surface (that's Safety Center / meetup safety / crisis helplines).
  static const Color _accent = AppColors.modeSettings;

  late final Dio _dio;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Field visibility: true = VISIBLE to others, false = HIDDEN
  final Map<String, bool> _visibility = {};

  bool _loading = true;
  String? _error;
  // Track which fields are currently being saved to show per-item loading.
  final Set<String> _saving = {};

  // Whether the user has granted special-category (sexuality / religion)
  // consent. Populated from the in-memory cache set by AuthGate; no extra
  // network call needed.
  bool _specialCategoryGranted = false;
  bool _safetyDataGranted = false;

  bool _activeStatus = true;
  bool _readReceipts = true;
  StreamSubscription<void>? _profileRefreshSub;

  @override
  void initState() {
    super.initState();
    unawaited(SecurityService.enterSensitiveScreen());
    _dio = createDio();
    // Default all fields to visible.
    for (final f in _kHideableFields) {
      _visibility[f.key] = true;
    }
    // Populate consent flag from the cache that AuthGate set at boot.
    _specialCategoryGranted = ConsentCacheManager.specialCategoryConsentGranted;
    _safetyDataGranted = ConsentCacheManager.safetyConsentGranted;
    _profileRefreshSub = ProfileRefreshNotifier.stream.listen((_) {
      if (mounted) {
        unawaited(_load(silent: true));
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(SecurityService.exitSensitiveScreen());
    unawaited(_profileRefreshSub?.cancel());
    super.dispose();
  }

  Future<String?> _token() async => _supabase.auth.currentSession?.accessToken;

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final token = await _token();
      if (token == null) throw Exception('Not signed in');
      final resp = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/profile/privacy-settings',
      );
      if (resp.statusCode == 200 && resp.data != null && mounted) {
        final hidden = (resp.data!['hidden_fields'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toSet();
        setState(() {
          for (final f in _kHideableFields) {
            _visibility[f.key] = !hidden.contains(f.key);
          }
          _activeStatus = resp.data!['share_active_status'] as bool? ?? true;
          _readReceipts = resp.data!['share_read_receipts'] as bool? ?? true;
        });
      }
    } on DioException catch (e) {
      if (mounted && !silent) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail']
            ?.toString();
        setState(() => _error = detail ?? 'Failed to load privacy settings.');
      }
    } on Exception catch (_) {
      if (mounted && !silent) {
        setState(() => _error = 'Failed to load privacy settings.');
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _toggleField(String key, bool visible) async {
    if (_saving.contains(key)) return;
    // Optimistic update.
    setState(() {
      _visibility[key] = visible;
      _saving.add(key);
    });
    try {
      final token = await _token();
      if (token == null) throw Exception('Not signed in');
      final hidden = _visibility.entries
          .where((e) => !e.value)
          .map((e) => e.key)
          .toList();
      await _dio.patch<void>(
        '${AppConfig.current.backendUrl}/api/v1/profile/privacy-settings',
        data: {'hidden_fields': hidden},
      );
      ProfileRefreshNotifier.notifyChanged();
    } on DioException catch (e) {
      // Roll back.
      if (mounted) {
        setState(() => _visibility[key] = !visible);
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail']
            ?.toString();
        NexusToast.show(
          context,
          detail ?? 'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() => _visibility[key] = !visible);
        NexusToast.show(
          context,
          'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<void> _toggleActiveStatus(bool value) => _togglePrivacyFlag(
    'share_active_status',
    value,
    ({required value}) => _activeStatus = value,
  );

  Future<void> _toggleReadReceipts(bool value) => _togglePrivacyFlag(
    'share_read_receipts',
    value,
    ({required value}) => _readReceipts = value,
  );

  Future<void> _togglePrivacyFlag(
    String field,
    bool value,
    void Function({required bool value}) apply,
  ) async {
    if (_saving.contains(field)) return;
    final previous = field == 'share_active_status'
        ? _activeStatus
        : _readReceipts;
    setState(() {
      apply(value: value);
      _saving.add(field);
    });
    try {
      final token = await _token();
      if (token == null) throw Exception('Not signed in');
      await _dio.patch<void>(
        '${AppConfig.current.backendUrl}/api/v1/profile/privacy-settings',
        data: {field: value},
      );
    } on DioException catch (e) {
      if (mounted) {
        setState(() => apply(value: previous));
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail']
            ?.toString();
        NexusToast.show(
          context,
          detail ?? 'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() => apply(value: previous));
        NexusToast.show(
          context,
          'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(field));
    }
  }

  /// Shows the GDPR consent bottom sheet. On grant, marks consent, flips
  /// both special-category fields to visible, and persists via the API.
  Future<void> _promptSpecialCategoryConsent() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SpecialCategoryConsentPromptCard(
          onGranted: () {
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            setState(() => _specialCategoryGranted = true);
            // Flip both special-category fields to visible.
            unawaited(_toggleField('display_sexuality', true));
            unawaited(_toggleField('religious_beliefs', true));
          },
        ),
      ),
    );
  }

  Future<bool> _showConfirmWithdrawDialog({
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 26,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: const Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(
                        'Withdraw',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return confirmed == true;
  }

  Future<void> _withdrawSpecialCategoryConsent() async {
    final confirmed = await _showConfirmWithdrawDialog(
      title: 'Withdraw Special Category Consent?',
      description:
          'This will clear your sexuality and religious belief fields on your profile '
          'and set them to hidden.',
      icon: LucideIcons.userMinus,
      iconColor: AppColors.warning,
      iconBgColor: const Color(0xFFFFFBEB),
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _loading = true;
    });

    try {
      // 1. Accept terms with special_category_accepted = false
      await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
        data: {
          'terms_version': ConsentCacheManager.currentTermsVersion,
          'general_accepted': true,
          'community_guidelines_accepted': true,
          'special_category_accepted': false,
          'safety_data_accepted': _safetyDataGranted,
        },
      );

      // 2. Clear sexuality and religious_beliefs fields
      await _dio.patch<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/profile/details',
        data: {
          'display_sexuality': 'Prefer not to say',
          'religious_beliefs': 'Prefer not to say',
        },
      );

      // 3. Make the fields hidden (visibility = false)
      final currentHidden = _visibility.entries
          .where((e) => !e.value)
          .map((e) => e.key)
          .toList();
      if (!currentHidden.contains('display_sexuality')) {
        currentHidden.add('display_sexuality');
      }
      if (!currentHidden.contains('religious_beliefs')) {
        currentHidden.add('religious_beliefs');
      }
      await _dio.patch<void>(
        '${AppConfig.current.backendUrl}/api/v1/profile/privacy-settings',
        data: {'hidden_fields': currentHidden},
      );

      // 4. Update caches and local state
      ConsentCacheManager.specialCategoryConsentGranted = false;
      await SecureProfileCache.clear();
      ProfileRefreshNotifier.notifyChanged();

      if (mounted) {
        setState(() {
          _specialCategoryGranted = false;
          _visibility['display_sexuality'] = false;
          _visibility['religious_beliefs'] = false;
        });
        NexusToast.show(
          context,
          'Special category consent withdrawn and profile fields cleared.',
          type: NexusToastType.success,
        );
      }
    } on Exception catch (_) {
      if (mounted) {
        NexusToast.show(
          context,
          'Failed to withdraw consent. Please try again.',
          type: NexusToastType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _withdrawSafetyDataConsent() async {
    final confirmed = await _showConfirmWithdrawDialog(
      title: 'Withdraw Safety Data Consent?',
      description:
          'This will terminate any active safety or check-in session and disable '
          'all meetup safety features.',
      icon: LucideIcons.shieldAlert,
      iconColor: AppColors.error,
      iconBgColor: const Color(0xFFFEF2F2),
    );

    if (!confirmed || !mounted) return;

    setState(() {
      _loading = true;
    });

    try {
      // 1. Accept terms with safety_data_accepted = false
      await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
        data: {
          'terms_version': ConsentCacheManager.currentTermsVersion,
          'general_accepted': true,
          'community_guidelines_accepted': true,
          'special_category_accepted': _specialCategoryGranted,
          'safety_data_accepted': false,
        },
      );

      // 2. End any active meetup safety session
      await MeetupSafetySession.instance.end();

      // Clear safety contacts locally and sync empty list to server
      await clearSafetyContacts();
      await SafetyAlertApi.syncContacts([]);

      // 3. Update caches and local state
      ConsentCacheManager.safetyConsentGranted = false;

      if (mounted) {
        setState(() {
          _safetyDataGranted = false;
        });
        NexusToast.show(
          context,
          'Safety data consent withdrawn and session stopped.',
          type: NexusToastType.success,
        );
      }
    } on Exception catch (_) {
      if (mounted) {
        NexusToast.show(
          context,
          'Failed to withdraw consent. Please try again.',
          type: NexusToastType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildConsentTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required String actionLabel,
    VoidCallback? onActionTap,
    bool isFirst = false,
  }) {
    final isDestructive =
        actionLabel == 'Delete Account' || actionLabel == 'Withdraw Consent';
    final isInteractive = onActionTap != null;

    return Column(
      children: [
        if (!isFirst)
          Container(
            margin: const EdgeInsets.only(left: 64),
            height: 0.5,
            color: const Color(0xFFE2E8F0),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 17,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onActionTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isInteractive
                        ? (isDestructive
                              ? const Color(0xFFFEF2F2)
                              : const Color(0xFFF1F5F9))
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isInteractive
                          ? (isDestructive
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFE2E8F0))
                          : const Color(0xFFF1F5F9),
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isInteractive
                          ? (isDestructive
                                ? AppColors.error
                                : const Color(0xFF475569))
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: NexusOrbitLoader(lightMode: true))
          : _error != null
          ? _buildError()
          : ListView(
              padding: const EdgeInsets.only(bottom: 48),
              children: [
                _buildFieldVisibilitySection(),
                _Section(
                  title: 'Activity',
                  children: [
                    _ToggleTile(
                      icon: LucideIcons.activity,
                      label: 'Active Status',
                      subtitle: "Let others see when you're currently active.",
                      accentColor: _accent,
                      value: _activeStatus,
                      isFirst: true,
                      isLast: true,
                      saving: _saving.contains('share_active_status'),
                      onChanged: _toggleActiveStatus,
                    ),
                  ],
                ),
                _Section(
                  title: 'Messages',
                  children: [
                    _ToggleTile(
                      icon: LucideIcons.checkCheck,
                      label: 'Read Receipts',
                      subtitle:
                          "Let matches see when you've read their messages.",
                      accentColor: _accent,
                      value: _readReceipts,
                      isFirst: true,
                      isLast: true,
                      saving: _saving.contains('share_read_receipts'),
                      onChanged: _toggleReadReceipts,
                    ),
                  ],
                ),
                _Section(
                  title: 'Withdraw Consents',
                  children: [
                    _buildConsentTile(
                      icon: LucideIcons.scroll,
                      iconColor: AppColors.inkMuted,
                      iconBgColor: const Color(0xFFF1F5F9),
                      title: 'General Terms & Policies',
                      subtitle:
                          'Mandatory to use Nexus. Withdrawing requires account deletion.',
                      actionLabel: 'Delete Account',
                      onActionTap: () =>
                          context.push('/settings/delete-account'),
                      isFirst: true,
                    ),
                    _buildConsentTile(
                      icon: LucideIcons.heart,
                      iconColor: _specialCategoryGranted
                          ? AppColors.error
                          : const Color(0xFF94A3B8),
                      iconBgColor: _specialCategoryGranted
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFF8FAFC),
                      title: 'Sensitive Profile Data',
                      subtitle:
                          'Consent for processing sexual orientation & religious beliefs.',
                      actionLabel: _specialCategoryGranted
                          ? 'Withdraw Consent'
                          : 'Not Granted',
                      onActionTap: _specialCategoryGranted
                          ? _withdrawSpecialCategoryConsent
                          : null,
                    ),
                    _buildConsentTile(
                      icon: LucideIcons.shieldAlert,
                      iconColor: _safetyDataGranted
                          ? AppColors.safetyBlue
                          : const Color(0xFF94A3B8),
                      iconBgColor: _safetyDataGranted
                          ? const Color(0xFFF0F9FF)
                          : const Color(0xFFF8FAFC),
                      title: 'Meetup Safety & SOS Data',
                      subtitle:
                          'Consent for location sharing, battery, camera & mic during dates.',
                      actionLabel: _safetyDataGranted
                          ? 'Withdraw Consent'
                          : 'Not Granted',
                      onActionTap: _safetyDataGranted
                          ? _withdrawSafetyDataConsent
                          : null,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.alertCircle,
              color: AppColors.error,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVisibilityInfo() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              const Icon(
                LucideIcons.info,
                size: 18,
                color: AppColors.modeSettings,
              ),
              const SizedBox(width: 8),
              Text(
                'About Field Visibility',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          content: Text(
            'Hidden fields are still used to find great matches for you - '
            "they just won't be visible on your public profile.",
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: const Color(0xFF475569),
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Got it',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: AppColors.modeSettings,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldVisibilitySection() {
    // Keys of fields that require special-category consent to be manipulated.
    const specialCategoryKeys = {'display_sexuality', 'religious_beliefs'};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Text(
                  'PROFILE FIELD VISIBILITY',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkMuted,
                    letterSpacing: 1.5,
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'About field visibility',
                  excludeSemantics: true,
                  onTap: _showVisibilityInfo,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showVisibilityInfo,
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(
                          LucideIcons.info,
                          size: 13,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  for (int i = 0; i < _kHideableFields.length; i++)
                    _ToggleTile(
                      icon: _kHideableFields[i].icon,
                      label: _kHideableFields[i].label,
                      subtitle: _kHideableFields[i].subtitle,
                      accentColor: _accent,
                      value: _visibility[_kHideableFields[i].key] ?? true,
                      isFirst: i == 0,
                      isLast: i == _kHideableFields.length - 1,
                      saving: _saving.contains(_kHideableFields[i].key),
                      locked:
                          specialCategoryKeys.contains(
                            _kHideableFields[i].key,
                          ) &&
                          !_specialCategoryGranted,
                      onChanged: (v) =>
                          _toggleField(_kHideableFields[i].key, v),
                      onLockedTap: _promptSpecialCategoryConsent,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.modeSettings,
              AppColors.tint(AppColors.modeSettings),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.modeSettings.withAlpha(0x33),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Privacy Settings',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section wrapper
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMuted,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle tile
// ---------------------------------------------------------------------------

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accentColor,
    required this.value,
    required this.isFirst,
    required this.isLast,
    required this.saving,
    required this.onChanged,
    this.locked = false,
    this.onLockedTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color accentColor;
  final bool value;
  final bool isFirst;
  final bool isLast;
  final bool saving;
  final ValueChanged<bool> onChanged;

  /// When true the toggle is replaced by a lock icon and the row is not
  /// interactive via onChanged. Tapping the row instead calls onLockedTap.
  final bool locked;
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!isFirst)
          Container(
            margin: const EdgeInsets.only(left: 64),
            height: 0.5,
            color: const Color(0xFFE2E8F0),
          ),
        InkWell(
          onTap: locked ? onLockedTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: locked
                        ? AppColors.inkFaint.withValues(alpha: 0.1)
                        : accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    color: locked ? AppColors.inkFaint : accentColor,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: locked ? AppColors.inkFaint : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locked ? 'Requires consent - tap to enable' : subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: locked
                              ? AppColors.primaryTeal.withValues(alpha: 0.8)
                              : const Color(0xFF94A3B8),
                          height: 1.3,
                          fontWeight: locked
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (saving)
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: NexusOrbitLoader(size: 36, lightMode: true),
                  )
                else if (locked)
                  const Icon(
                    LucideIcons.lock,
                    size: 18,
                    color: AppColors.inkFaint,
                  )
                else
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

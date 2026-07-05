import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Field descriptors
// ---------------------------------------------------------------------------

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
  static const _accent = Color(0xFF0284C7);

  late final Dio _dio;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Field visibility: true = VISIBLE to others, false = HIDDEN
  final Map<String, bool> _visibility = {};

  bool _loading = true;
  String? _error;
  // Track which fields are currently being saved to show per-item loading.
  final Set<String> _saving = {};

  bool _activeStatus = true;
  bool _readReceipts = true;

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    // Default all fields to visible.
    for (final f in _kHideableFields) {
      _visibility[f.key] = true;
    }
    unawaited(_load());
  }

  Future<String?> _token() async => _supabase.auth.currentSession?.accessToken;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _token();
      if (token == null) throw Exception('Not signed in');
      final resp = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/profile/privacy-settings',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (resp.statusCode == 200 && resp.data != null) {
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
      final detail = (e.response?.data as Map<String, dynamic>?)?['detail']
          ?.toString();
      setState(() => _error = detail ?? 'Failed to load privacy settings.');
    } on Exception catch (_) {
      setState(() => _error = 'Failed to load privacy settings.');
    } finally {
      setState(() => _loading = false);
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      // Roll back.
      setState(() => _visibility[key] = !visible);
      if (mounted) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail']
            ?.toString();
        NexusToast.show(
          context,
          detail ?? 'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } on Exception catch (_) {
      setState(() => _visibility[key] = !visible);
      if (mounted) {
        NexusToast.show(
          context,
          'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } finally {
      setState(() => _saving.remove(key));
    }
  }

  Future<void> _toggleActiveStatus(bool value) =>
      _togglePrivacyFlag('share_active_status', value, ({required value}) => _activeStatus = value);

  Future<void> _toggleReadReceipts(bool value) =>
      _togglePrivacyFlag('share_read_receipts', value, ({required value}) => _readReceipts = value);

  Future<void> _togglePrivacyFlag(
    String field,
    bool value,
    void Function({required bool value}) apply,
  ) async {
    if (_saving.contains(field)) return;
    final previous = field == 'share_active_status' ? _activeStatus : _readReceipts;
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
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      setState(() => apply(value: previous));
      if (mounted) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail']
            ?.toString();
        NexusToast.show(
          context,
          detail ?? 'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } on Exception catch (_) {
      setState(() => apply(value: previous));
      if (mounted) {
        NexusToast.show(
          context,
          'Failed to save setting.',
          type: NexusToastType.error,
        );
      }
    } finally {
      setState(() => _saving.remove(field));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: NexusOrbitLoader(size: 48))
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
              color: Color(0xFFEF4444),
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF64748B),
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
              const Icon(LucideIcons.info, size: 18, color: Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Text(
                'About Field Visibility',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
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
                  color: const Color(0xFF0284C7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldVisibilitySection() {
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
                    color: const Color(0xFF64748B),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _showVisibilityInfo,
                  child: const Icon(
                    LucideIcons.info,
                    size: 13,
                    color: Color(0xFF94A3B8),
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
                      onChanged: (v) =>
                          _toggleField(_kHideableFields[i].key, v),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0284C7), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x330284C7),
              blurRadius: 12,
              offset: Offset(0, 4),
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
                color: const Color(0xFF64748B),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: accentColor, size: 17),
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
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                        height: 1.3,
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
      ],
    );
  }
}

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

class _EmailCategory {
  const _EmailCategory({
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

final _kEmailCategories = <_EmailCategory>[
  const _EmailCategory(
    key: 'email_notify_matches',
    label: 'New Matches & Likes',
    subtitle: 'Get an email when you match with someone or receive a like.',
    icon: LucideIcons.heart,
  ),
  const _EmailCategory(
    key: 'email_notify_messages',
    label: 'New Messages',
    subtitle: 'Get an email when a match sends you a new message.',
    icon: LucideIcons.messageCircle,
  ),
  const _EmailCategory(
    key: 'email_notify_digest',
    label: 'Weekly Activity Digest',
    subtitle: 'A weekly summary of your profile views and activity.',
    icon: LucideIcons.barChart2,
  ),
  const _EmailCategory(
    key: 'email_notify_product_updates',
    label: 'Product News & Updates',
    subtitle: 'Hear about new features and improvements to Nexus.',
    icon: LucideIcons.sparkles,
  ),
  const _EmailCategory(
    key: 'email_notify_promotions',
    label: 'Promotions & Offers',
    subtitle: 'Special offers, discounts, and Nexus+ promotions.',
    icon: LucideIcons.tag,
  ),
];

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class EmailNotificationSettingsPage extends StatefulWidget {
  const EmailNotificationSettingsPage({super.key});

  @override
  State<EmailNotificationSettingsPage> createState() =>
      _EmailNotificationSettingsPageState();
}

class _EmailNotificationSettingsPageState
    extends State<EmailNotificationSettingsPage> {
  static const _accent = Color(0xFF0284C7);

  late final Dio _dio;
  final SupabaseClient _supabase = Supabase.instance.client;

  final Map<String, bool> _prefs = {};
  final Set<String> _saving = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    for (final c in _kEmailCategories) {
      _prefs[c.key] = true;
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
        '${AppConfig.current.backendUrl}/api/v1/profile/email-notification-settings',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (resp.statusCode == 200 && resp.data != null && mounted) {
        setState(() {
          for (final c in _kEmailCategories) {
            _prefs[c.key] = resp.data![c.key] as bool? ?? true;
          }
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = (e.response?.data as Map<String, dynamic>?)?['detail']
            ?.toString();
        setState(
          () => _error = detail ?? 'Failed to load email notification settings.',
        );
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() => _error = 'Failed to load email notification settings.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    if (_saving.contains(key)) return;
    final previous = _prefs[key] ?? true;
    setState(() {
      _prefs[key] = value;
      _saving.add(key);
    });
    try {
      final token = await _token();
      if (token == null) throw Exception('Not signed in');
      await _dio.patch<void>(
        '${AppConfig.current.backendUrl}/api/v1/profile/email-notification-settings',
        data: {key: value},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _prefs[key] = previous);
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
        setState(() => _prefs[key] = previous);
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
                _buildIntro(),
                _buildMandatorySection(),
                _buildToggleableSection(),
              ],
            ),
    );
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
      child: Text(
        'Choose which emails Nexus sends you. Account and security emails '
        'are always sent to keep your account safe.',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: const Color(0xFF64748B),
          height: 1.45,
        ),
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

  Widget _buildMandatorySection() {
    return const _Section(
      title: 'Account & Security',
      children: [
        _MandatoryTile(
          icon: LucideIcons.shieldCheck,
          label: 'Transactional Emails',
          subtitle:
              'Security alerts, password resets, and billing receipts. '
              "Required to keep your account safe — can't be turned off.",
          accentColor: _accent,
        ),
      ],
    );
  }

  Widget _buildToggleableSection() {
    return _Section(
      title: 'Notify Me About',
      children: [
        for (int i = 0; i < _kEmailCategories.length; i++)
          _ToggleTile(
            icon: _kEmailCategories[i].icon,
            label: _kEmailCategories[i].label,
            subtitle: _kEmailCategories[i].subtitle,
            accentColor: _accent,
            value: _prefs[_kEmailCategories[i].key] ?? true,
            isFirst: i == 0,
            isLast: i == _kEmailCategories.length - 1,
            saving: _saving.contains(_kEmailCategories[i].key),
            onChanged: (v) => _toggle(_kEmailCategories[i].key, v),
          ),
      ],
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
            'Email Notifications',
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
// Mandatory (always-on) tile
// ---------------------------------------------------------------------------

class _MandatoryTile extends StatelessWidget {
  const _MandatoryTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.lock,
                  size: 11,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 4),
                Text(
                  'Always On',
                  style: GoogleFonts.manrope(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF16A34A),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
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

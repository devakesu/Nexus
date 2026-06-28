import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  static const _accent = Color(0xFF0284C7);

  // Stub state — will be wired to backend later.
  bool _activeStatus = true;
  bool _readReceipts = true;
  bool _showDistance = true;
  bool _showAge = true;
  _MessagePermission _whoCanMessage = _MessagePermission.everyone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
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
                onChanged: (v) => setState(() => _activeStatus = v),
              ),
            ],
          ),
          _Section(
            title: 'Messages',
            children: [
              _ToggleTile(
                icon: LucideIcons.checkCheck,
                label: 'Read Receipts',
                subtitle: "Let matches see when you've read their messages.",
                accentColor: _accent,
                value: _readReceipts,
                isFirst: true,
                isLast: false,
                onChanged: (v) => setState(() => _readReceipts = v),
              ),
              _OptionTile(
                icon: LucideIcons.messageCircle,
                label: 'Who Can Message Me',
                value: _whoCanMessage.label,
                accentColor: _accent,
                isFirst: false,
                isLast: true,
                onTap: () => _pickMessagePermission(context),
              ),
            ],
          ),
          _Section(
            title: 'Profile',
            children: [
              _ToggleTile(
                icon: LucideIcons.mapPin,
                label: 'Show My Distance',
                subtitle: 'Show your approximate distance to other users.',
                accentColor: _accent,
                value: _showDistance,
                isFirst: true,
                isLast: false,
                onChanged: (v) => setState(() => _showDistance = v),
              ),
              _ToggleTile(
                icon: LucideIcons.cake,
                label: 'Show My Age',
                subtitle: 'Display your age on your profile.',
                accentColor: _accent,
                value: _showAge,
                isFirst: false,
                isLast: true,
                onChanged: (v) => setState(() => _showAge = v),
              ),
            ],
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

  Future<void> _pickMessagePermission(BuildContext context) async {
    final picked = await showModalBottomSheet<_MessagePermission>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MessagePermissionSheet(current: _whoCanMessage),
    );
    if (picked != null && mounted) {
      setState(() => _whoCanMessage = picked);
    }
  }
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum _MessagePermission {
  everyone('Everyone'),
  matchesOnly('Matches Only');

  const _MessagePermission(this.label);
  final String label;
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
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color accentColor;
  final bool value;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        if (!isLast)
          Container(
            margin: const EdgeInsets.only(left: 64),
            height: 0.5,
            color: const Color(0xFFE2E8F0),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Option tile (tappable, shows current value + chevron)
// ---------------------------------------------------------------------------

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

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
          onTap: onTap,
          child: Padding(
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
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  LucideIcons.chevronRight,
                  color: Color(0xFFCBD5E1),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Who Can Message Me — bottom sheet picker
// ---------------------------------------------------------------------------

class _MessagePermissionSheet extends StatelessWidget {
  const _MessagePermissionSheet({required this.current});

  final _MessagePermission current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Who Can Message Me',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Control who can start a conversation with you.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            ..._MessagePermission.values.map(
              (option) => _PermissionOption(
                option: option,
                isSelected: option == current,
                onTap: () => Navigator.of(context).pop(option),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PermissionOption extends StatelessWidget {
  const _PermissionOption({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _MessagePermission option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0284C7);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? accent : const Color(0xFF0F172A),
                ),
              ),
            ),
            if (isSelected)
              const Icon(LucideIcons.check, color: accent, size: 18),
          ],
        ),
      ),
    );
  }
}

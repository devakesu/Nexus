import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/profile/widgets/universe_section.dart';

class BioSection extends StatefulWidget {
  const BioSection({
    required this.bio,
    required this.onBioChanged,
    required this.onBioSubmitted,
    this.isSaving = false,
    this.focusNode,
    super.key,
  });

  final String bio;
  final ValueChanged<String> onBioChanged;
  final ValueChanged<String> onBioSubmitted;
  final bool isSaving;
  final FocusNode? focusNode;

  static const int maxLength = 400;

  @override
  State<BioSection> createState() => _BioSectionState();
}

class _BioSectionState extends State<BioSection> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isDirty = false;

  static const Color _pulsarPink = AppColors.pulsarPink;
  static const _deepPurple = Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.bio);
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant BioSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external state changes (e.g., after a load) without losing cursor.
    if (!_isDirty && widget.bio != _controller.text) {
      _controller.text = widget.bio;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (!_focusNode.hasFocus && _isDirty) {
      widget.onBioSubmitted(_controller.text.trim());
      setState(() => _isDirty = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = BioSection.maxLength - _controller.text.length;
    final isNearLimit = remaining <= 50;
    final isAtLimit = remaining <= 0;

    final counterColor = isAtLimit
        ? Colors.redAccent
        : isNearLimit
        ? _pulsarPink
        : Colors.black45;

    return UniverseSection(
      icon: LucideIcons.fileText,
      title: 'Cosmic Signature',
      description:
          'Your signal to the universe - who you are in your own words',
      cardColor: const Color(0xFFFFF0F5),
      borderColor: const Color(0xFFFF4D7E).withValues(alpha: 0.4),
      accentColor: _pulsarPink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Textarea container
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: _focusNode.hasFocus
                  ? const LinearGradient(
                      colors: [_deepPurple, _pulsarPink],
                    )
                  : LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.08),
                      ],
                    ),
              boxShadow: _focusNode.hasFocus
                  ? [
                      BoxShadow(
                        color: _pulsarPink.withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.all(1.2),
              decoration: BoxDecoration(
                color: _focusNode.hasFocus
                    ? Colors.white
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.penLine,
                              size: 13,
                              color: _pulsarPink,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'BIO',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.black.withValues(alpha: 0.45),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 5,
                        minLines: 3,
                        maxLength: BioSection.maxLength,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF0F172A),
                          fontSize: 14,
                          height: 1.55,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Tell your story - your vibe, your passions, what makes you, you...',
                          hintStyle: GoogleFonts.plusJakartaSans(
                            color: Colors.black.withValues(alpha: 0.3),
                            fontSize: 13,
                            height: 1.5,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.fromLTRB(
                            14,
                            8,
                            14,
                            12,
                          ),
                        ),
                        onChanged: (val) {
                          widget.onBioChanged(val);
                          setState(() => _isDirty = true);
                        },
                        onEditingComplete: () {
                          widget.onBioSubmitted(_controller.text.trim());
                          setState(() => _isDirty = false);
                        },
                      ),
                    ],
                  ),
                  if (widget.isSaving)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(15),
                          bottomRight: Radius.circular(15),
                        ),
                        child: SizedBox(
                          height: 2,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _pulsarPink,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Footer row: hint + char counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.plusJakartaSans(
                  color: counterColor,
                  fontSize: 11,
                  fontWeight: isNearLimit ? FontWeight.bold : FontWeight.normal,
                ),
                child: Text('$remaining left'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

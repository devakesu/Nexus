import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../widgets/universe_section.dart';

class BioSection extends StatefulWidget {
  const BioSection({
    required this.bio,
    required this.onBioChanged,
    required this.onBioSubmitted,
    super.key,
  });

  final String bio;
  final ValueChanged<String> onBioChanged;
  final ValueChanged<String> onBioSubmitted;

  static const int maxLength = 400;

  @override
  State<BioSection> createState() => _BioSectionState();
}

class _BioSectionState extends State<BioSection> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isDirty = false;

  static const _pulsarPink = Color(0xFFFF7597);
  static const _deepPurple = Color(0xFF7C3AED);
  static const _mistLavender = Color(0xFFE2D9F3);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.bio);
    _focusNode = FocusNode();
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
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onFocusChange() {
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
            : Colors.white38;

    return UniverseSection(
      icon: LucideIcons.fileText,
      title: 'Cosmic Signature',
      description: 'Your signal to the universe — who you are in your own words',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Textarea container
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? _pulsarPink.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.1),
                width: _focusNode.hasFocus ? 1.5 : 1,
              ),
              boxShadow: _focusNode.hasFocus
                  ? [
                      BoxShadow(
                        color: _deepPurple.withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: Column(
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
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          fontFamily: 'Outfit',
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
                  buildCounter: (_,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null, // We render our own counter below
                  style: const TextStyle(
                    color: _mistLavender,
                    fontSize: 14,
                    height: 1.55,
                    fontFamily: 'Outfit',
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Tell your story — your vibe, your passions, what makes you, you...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 13,
                      height: 1.5,
                      fontFamily: 'Outfit',
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
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
          ),
          const SizedBox(height: 8),

          // Footer row: hint + char counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Auto-saves when you leave this field',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 11,
                  fontFamily: 'Outfit',
                ),
              ),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: counterColor,
                  fontSize: 11,
                  fontWeight:
                      isNearLimit ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'Outfit',
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

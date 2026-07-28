import 'package:flutter/material.dart';
import 'package:nexus/core/theme/app_colors.dart';

class GlassTextField extends StatefulWidget {
  const GlassTextField({
    required this.label,
    required this.initialValue,
    required this.hintText,
    required this.prefixIcon,
    required this.onChanged,
    this.onFieldSubmitted,
    this.maxLines = 1,
    this.minLines = 1,
    this.keyboardType,
    this.isSaving = false,
    this.focusNode,
    this.visibilityBadge,
    super.key,
  });

  final String label;
  final String initialValue;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final bool isSaving;
  final FocusNode? focusNode;
  final Widget? visibilityBadge;

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (!_focusNode.hasFocus) {
        widget.onFieldSubmitted?.call(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(covariant GlassTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = AppColors.pulsarPink;

    final isMultiLine = widget.minLines != null && widget.minLines! > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              if (widget.visibilityBadge != null) ...[
                const SizedBox(width: 6),
                widget.visibilityBadge!,
              ],
            ],
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: _isFocused
                  ? const LinearGradient(
                      colors: [Color(0xFF00E5FF), pulsarPink],
                    )
                  : LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.08),
                      ],
                    ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: pulsarPink.withValues(alpha: 0.2),
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
                color: _isFocused ? Colors.white : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: Row(
                      crossAxisAlignment: isMultiLine
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: isMultiLine
                              ? const EdgeInsets.only(top: 2)
                              : EdgeInsets.zero,
                          child: Icon(
                            widget.prefixIcon,
                            color: _isFocused ? pulsarPink : Colors.black38,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _controller,
                            focusNode: _focusNode,
                            onChanged: widget.onChanged,
                            maxLines: widget.maxLines,
                            minLines: widget.minLines,
                            keyboardType: widget.keyboardType,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              hintStyle: TextStyle(
                                color: Colors.black.withValues(alpha: 0.3),
                                fontSize: 14,
                              ),
                              hintMaxLines: 5,
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                              pulsarPink,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

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

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  late TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() {
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
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);

    final isMultiLine = widget.minLines != null && widget.minLines! > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _isFocused ? 0.08 : 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused
                    ? pulsarPink.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.12),
                width: _isFocused ? 1.5 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: pulsarPink.withValues(alpha: 0.15),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
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
                    color: _isFocused ? pulsarPink : Colors.white38,
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
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
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
        ],
      ),
    );
  }
}

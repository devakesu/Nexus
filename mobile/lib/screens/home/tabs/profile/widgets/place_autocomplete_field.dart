import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';

class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    required this.label,
    required this.initialValue,
    required this.hintText,
    required this.prefixIcon,
    required this.onChanged,
    this.onFieldSubmitted,
    this.isSaving = false,
    this.focusNode,
    super.key,
  });

  final String label;
  final String initialValue;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final bool isSaving;
  final FocusNode? focusNode;

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isFocused = false;
  List<String> _suggestions = [];

  static const List<String> _allPlaces = [
    'New York, NY',
    'San Francisco, CA',
    'Los Angeles, CA',
    'Chicago, IL',
    'Boston, MA',
    'Seattle, WA',
    'Austin, TX',
    'Miami, FL',
    'Denver, CO',
    'Atlanta, GA',
    'London, UK',
    'Paris, France',
    'Berlin, Germany',
    'Tokyo, Japan',
    'Singapore',
    'Sydney, Australia',
    'Toronto, Canada',
    'Mumbai, India',
    'Delhi, India',
    'Bangalore, India',
    'Hyderabad, India',
    'Chennai, India',
    'Pune, India',
    'Kolkata, India',
    'San Jose, CA',
    'Portland, OR',
  ];

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
        // Delay hiding suggestions to allow tapping them
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              _suggestions = [];
            });
          }
        });
        widget.onFieldSubmitted?.call(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PlaceAutocompleteField oldWidget) {
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

  void _onTextChanged(String text) {
    widget.onChanged(text);
    if (text.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    final query = text.toLowerCase();
    setState(() {
      _suggestions = _allPlaces
          .where((place) => place.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = AppColors.pulsarPink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
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
                  TextFormField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onTextChanged,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          widget.prefixIcon,
                          color: _isFocused ? pulsarPink : Colors.black38,
                          size: 18,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: Colors.black.withValues(alpha: 0.3),
                        fontSize: 14,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 13,
                      ),
                      border: InputBorder.none,
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
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      dense: true,
                      leading: const Icon(
                        LucideIcons.mapPin,
                        color: pulsarPink,
                        size: 14,
                      ),
                      title: Text(
                        suggestion,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _controller.text = suggestion;
                          _suggestions = [];
                        });
                        widget.onChanged(suggestion);
                        widget.onFieldSubmitted?.call(suggestion);
                        _focusNode.unfocus();
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

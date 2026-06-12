import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'glass_text_field.dart';
import '../utils/emoji_helper.dart';

class CosmicSelectionOverlay extends StatefulWidget {
  const CosmicSelectionOverlay({
    required this.title,
    required this.options,
    required this.currentValue,
    super.key,
  });

  final String title;
  final List<String> options;
  final String currentValue;

  @override
  State<CosmicSelectionOverlay> createState() => _CosmicSelectionOverlayState();
}

class _CosmicSelectionOverlayState extends State<CosmicSelectionOverlay> {
  String _searchQuery = '';
  late List<String> _filteredOptions;

  @override
  void initState() {
    super.initState();
    _filteredOptions = widget.options;
  }

  void _filterOptions(String query) {
    setState(() {
      _searchQuery = query;
      _filteredOptions = widget.options
          .where((opt) => opt.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select your dimensional coordinates',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GlassTextField(
                  label: 'Search Option',
                  initialValue: _searchQuery,
                  hintText: 'Type to filter options...',
                  prefixIcon: LucideIcons.search,
                  onChanged: _filterOptions,
                ),
              ),

              // Options List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _filteredOptions.length,
                  itemBuilder: (context, index) {
                    final option = _filteredOptions[index];
                    final isSelected = option == widget.currentValue;

                    return GestureDetector(
                      onTap: () => Navigator.pop(context, option),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? deepPurple.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? pulsarPink.withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.08),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                if (getEmojiForTag(option).isNotEmpty) ...[
                                  Text(
                                    '${getEmojiForTag(option)}  ',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ],
                                Text(
                                  option,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ],
                            ),
                            if (isSelected)
                              const Icon(
                                LucideIcons.check,
                                color: pulsarPink,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

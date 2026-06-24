import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/utils/emoji_helper.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/glass_text_field.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.65),
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
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select your dimensional coordinates',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.x, color: isDark ? Colors.white70 : Colors.black54),
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
                      onTap: () => Navigator.pop(
                        context,
                        isSelected ? null : option,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? pulsarPink.withValues(alpha: 0.18)
                              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.7)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? pulsarPink.withValues(alpha: 0.8)
                                : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.12)),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: pulsarPink.withValues(alpha: isDark ? 0.15 : 0.08),
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
                                        ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                        : (isDark ? Colors.white70 : Colors.black87),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/tag_chips_editor.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/universe_section.dart';
import 'package:nexus/screens/home/widgets/interests_overlay.dart';

class AffinityInterestsSection extends StatefulWidget {
  const AffinityInterestsSection({
    required this.flatSubInterests,
    required this.causesSupported,
    required this.topArtists,
    required this.onInterestsSaved,
    required this.onCausesSupportedChanged,
    required this.onTopArtistsChanged,
    super.key,
  });

  final List<String> flatSubInterests;
  final List<String> causesSupported;
  final List<String> topArtists;

  final ValueChanged<List<String>> onInterestsSaved;
  final ValueChanged<List<String>> onCausesSupportedChanged;
  final ValueChanged<List<String>> onTopArtistsChanged;

  @override
  State<AffinityInterestsSection> createState() => _AffinityInterestsSectionState();
}

class _AffinityInterestsSectionState extends State<AffinityInterestsSection> {
  final TextEditingController _artistInputController = TextEditingController();

  @override
  void dispose() {
    _artistInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UniverseSection(
      icon: LucideIcons.tags,
      title: 'Interests & Hobbies',
      description: 'Your hobbies, music, and causes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Interests & Affinities tag editor
          TagChipsEditor(
            label: 'Interests',
            currentValues: widget.flatSubInterests,
            presets: const [],
            icon: LucideIcons.sparkles,
            iconColor: const Color(0xFFFF7597),
            onChanged: widget.onInterestsSaved,
            hintText: 'Select interests...',
            allowCustom: false,
            onTapEdit: () {
              unawaited(
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => InterestsOverlay(
                      initialSelected: widget.flatSubInterests,
                      onSave: widget.onInterestsSaved,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Causes Supported tag editor
          TagChipsEditor(
            label: 'Causes Supported',
            currentValues: widget.causesSupported,
            presets: const [
              'Climate Action',
              'Tech Ethics',
              'Mental Health',
              'LGBTQ+ Rights',
              'Education Access',
              'Animal Protection',
              'Disaster Relief',
              'Poverty Alleviation',
              'Gender Equality',
              'Scientific Research',
              'Mental Health Advocacy',
              'Human Rights',
              'Clean Water & Sanitation',
              'Renewable Energy',
              'Economic Development',
              'Arts & Culture Preservation',
            ],
            icon: LucideIcons.heart,
            iconColor: const Color(0xFF00BCD4),
            onChanged: widget.onCausesSupportedChanged,
            hintText: 'Select causes...',
            allowCustom: false,
          ),

          // Top Artists List
          Text(
            'TOP ARTISTS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.topArtists.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.topArtists.map((artist) {
                return Chip(
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  label: Text(
                    artist,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                  deleteIcon: const Icon(
                    LucideIcons.x,
                    size: 12,
                    color: Colors.white70,
                  ),
                  onDeleted: () {
                    final updated = List<String>.from(widget.topArtists)..remove(artist);
                    widget.onTopArtistsChanged(updated);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _artistInputController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type artist name and press Enter...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 11,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (val) {
                      final trimmed = val.trim();
                      if (trimmed.isNotEmpty && !widget.topArtists.contains(trimmed)) {
                        final updated = List<String>.from(widget.topArtists)..add(trimmed);
                        widget.onTopArtistsChanged(updated);
                        _artistInputController.clear();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

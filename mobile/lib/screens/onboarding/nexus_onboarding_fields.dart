import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Onboarding fields shown only for the main Nexus flavor.
///
/// Collects lifestyle-oriented inputs.
class NexusOnboardingFields extends StatefulWidget {
  const NexusOnboardingFields({
    required this.onChanged,
    super.key,
  });

  /// Called whenever lifestyle selection changes.
  final void Function({required String lifestyle}) onChanged;

  @override
  State<NexusOnboardingFields> createState() => _NexusOnboardingFieldsState();
}

class _NexusOnboardingFieldsState extends State<NexusOnboardingFields> {
  static const _availableLifestyles = [
    'Gym Rat',
    'Outdoorsy',
    'Music Lover',
    'Gaming',
    'Foodie',
    'Creative',
    'Night Owl',
    'Early Bird',
    'Chill',
    'Social Butterfly',
  ];

  final Set<String> _selectedTags = {};

  void _notify() {
    widget.onChanged(
      lifestyle: _selectedTags.isEmpty ? 'Chill' : _selectedTags.join(', '),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Lifestyle Tags ───────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'YOUR LIFESTYLE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Color(0x99FFFFFF),
              ),
            ),
            Text(
              '${_selectedTags.length} selected',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D9488),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableLifestyles.map((tag) {
            final selected = _selectedTags.contains(tag);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (selected) {
                    _selectedTags.remove(tag);
                  } else {
                    _selectedTags.add(tag);
                  }
                });
                _notify();
              },
              child: AnimatedContainer(
                duration: 200.ms,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF0D9488)
                        : const Color(0x1AFFFFFF),
                  ),
                  color: selected
                      ? const Color(0x260D9488)
                      : const Color(0xFF090D0F),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : const Color(0x80FFFFFF),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ).animate().fade(delay: 250.ms).slideY(begin: 0.05, end: 0, duration: 350.ms);
  }
}

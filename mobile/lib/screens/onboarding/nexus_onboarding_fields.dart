import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/theme/app_colors.dart';

/// Onboarding fields shown only for the main Nexus flavor.
///
/// Collects the user's demographic bucket - which group they primarily
/// identify as - used for relevance-ranked discovery.
class NexusOnboardingFields extends StatefulWidget {
  const NexusOnboardingFields({
    required this.onChanged,
    super.key,
  });

  /// Called whenever the demographic bucket selection changes.
  final void Function({required String demographicBucket}) onChanged;

  @override
  State<NexusOnboardingFields> createState() => _NexusOnboardingFieldsState();
}

class _NexusOnboardingFieldsState extends State<NexusOnboardingFields> {
  static const _buckets = [
    _BucketOption(label: 'Men', value: 'M', emoji: '♂️'),
    _BucketOption(label: 'Women', value: 'F', emoji: '♀️'),
    _BucketOption(label: 'Non-Binary', value: 'NB', emoji: '⚧️'),
  ];

  String _selectedBucket = '';

  void _select(String value) {
    setState(() => _selectedBucket = value);
    widget.onChanged(demographicBucket: value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ───────────────────────────────────────────────────────────
        const Text(
          'DEMOGRAPHIC BUCKET',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Color(0x99FFFFFF),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Which bucket do you primarily identify as?',
          style: TextStyle(
            fontSize: 12,
            color: Color(0x66FFFFFF),
          ),
        ),
        const SizedBox(height: 12),

        // ── Bucket chips ──────────────────────────────────────────────────
        Row(
          children: _buckets
              .map(
                (bucket) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: bucket == _buckets.last ? 0 : 8,
                    ),
                    child: _BucketChip(
                      option: bucket,
                      selected: _selectedBucket == bucket.value,
                      onTap: () => _select(bucket.value),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ).animate().fade(delay: 250.ms).slideY(begin: 0.05, end: 0, duration: 350.ms);
  }
}

class _BucketOption {
  const _BucketOption({
    required this.label,
    required this.value,
    required this.emoji,
  });

  final String label;
  final String value;
  final String emoji;
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _BucketOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.pulsarPink : const Color(0x1AFFFFFF),
            width: selected ? 1.5 : 1,
          ),
          color: selected ? const Color(0x26FF7597) : const Color(0xFF0B0D13),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              option.emoji,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(
              option.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0x80FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

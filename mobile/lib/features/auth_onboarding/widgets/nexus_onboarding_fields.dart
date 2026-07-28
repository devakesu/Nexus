import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/core/theme/app_colors.dart';

/// Onboarding demographic bucket selection fields for main Nexus and MEC variants.
class NexusOnboardingFields extends StatefulWidget {
  const NexusOnboardingFields({
    required this.onChanged,
    this.isMec = false,
    super.key,
  });

  final void Function({required String demographicBucket}) onChanged;
  final bool isMec;

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
        Row(
          children: _buckets.map((b) {
            final selected = _selectedBucket == b.value;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => _select(b.value),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryTeal.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.primaryTeal
                            : Colors.white.withValues(alpha: 0.1),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(b.emoji, style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text(
                          b.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: selected ? Colors.white : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
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

class NexusMECOnboardingFields extends StatelessWidget {
  const NexusMECOnboardingFields({
    required this.onChanged,
    super.key,
  });

  final void Function({required String demographicBucket}) onChanged;

  @override
  Widget build(BuildContext context) {
    return NexusOnboardingFields(
      onChanged: onChanged,
      isMec: true,
    );
  }
}

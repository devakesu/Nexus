import 'package:flutter/material.dart';

class NeonSlider extends StatelessWidget {
  const NeonSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.onChangeEnd,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: pulsarPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: pulsarPink.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${value.round()}',
                style: const TextStyle(
                  color: pulsarPink,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: deepPurple,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            trackHeight: 4,
            thumbColor: pulsarPink,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayColor: pulsarPink.withValues(alpha: 0.2),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTickMarkColor: pulsarPink.withValues(alpha: 0.8),
            inactiveTickMarkColor: Colors.white.withValues(alpha: 0.3),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2.5),
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

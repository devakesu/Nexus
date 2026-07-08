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
    this.isSaving = false,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0891B2);
    const pulsarPink = Color(0xFFFF7597);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                if (isSaving) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
                    ),
                  ),
                ],
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${value.round()}',
                style: const TextStyle(
                  color: primaryColor,
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
            inactiveTrackColor: Colors.black.withValues(alpha: 0.08),
            trackHeight: 4,
            thumbColor: primaryColor,
            thumbShape: const _NeonSliderThumbShape(thumbRadius: 9),
            trackShape: const _NeonGradientSliderTrackShape(),
            overlayColor: primaryColor.withValues(alpha: 0.2),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTickMarkColor: Colors.black.withValues(alpha: 0.8),
            inactiveTickMarkColor: Colors.black.withValues(alpha: 0.2),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
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

class _NeonGradientSliderTrackShape extends RectangularSliderTrackShape {
  const _NeonGradientSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    const primaryColor = Color(0xFF0891B2);

    final activePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final inactivePaint = Paint()
      ..color =
          sliderTheme.inactiveTrackColor ?? Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );
    final inactiveRect = Rect.fromLTRB(
      thumbCenter.dx,
      trackRect.top,
      trackRect.right,
      trackRect.bottom,
    );

    final activeRRect = RRect.fromRectAndCorners(
      activeRect,
      topLeft: const Radius.circular(2),
      bottomLeft: const Radius.circular(2),
    );
    final inactiveRRect = RRect.fromRectAndCorners(
      inactiveRect,
      topRight: const Radius.circular(2),
      bottomRight: const Radius.circular(2),
    );

    context.canvas.drawRRect(activeRRect, activePaint);
    context.canvas.drawRRect(inactiveRRect, inactivePaint);
  }
}

class _NeonSliderThumbShape extends SliderComponentShape {
  const _NeonSliderThumbShape({required this.thumbRadius});

  final double thumbRadius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    const primaryColor = Color(0xFF0891B2);
    final canvas = context.canvas;

    final outerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, thumbRadius, outerPaint);

    final innerPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, thumbRadius - 3.5, innerPaint);
  }
}

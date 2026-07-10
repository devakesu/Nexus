import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/theme/app_colors.dart';

class SpaceNode {
  SpaceNode({
    required this.position,
    required this.velocity,
    required this.score,
    required this.label,
    required this.type,
    required this.targetRadius,
  });

  Offset position; // relative position from -1.2 to 1.2
  Offset velocity;
  final double score;
  final String label;
  final int? type; // 0 = DATING, 1 = FRIENDS, 2 = PRO
  final double? targetRadius; // target orbit shell radius
}

// Custom Painter for Gravity Grid, ripples & Interactive Mode-specific Nodes
class GravityFieldPainter extends CustomPainter {
  GravityFieldPainter({
    required this.nodes,
    required this.touchPosition,
    required this.tiltOffset,
    required this.simulatedTime,
    required this.matrixIndex,
  });

  final List<SpaceNode> nodes;
  final Offset? touchPosition;
  final Offset tiltOffset;
  final double simulatedTime;
  final int matrixIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final coordinateScale =
        size.width *
        0.45; // scale factor mapping relative coordinates to pixels

    // Define colors
    const accentColor = AppColors.pulsarPink;
    const whiteColor = Color(0xFFFFFFFF);
    const greyColor = Color(0xFF6B7280);

    canvas.save();
    final activeTilt = Offset(
      math.sin(simulatedTime) * 0.03,
      math.cos(simulatedTime) * 0.03,
    );
    canvas.translate(activeTilt.dx * 12, activeTilt.dy * 12);

    // 1. Draw concentric grid rings (0.50, 0.75, 1.00)
    final gridPaint = Paint()
      ..color = greyColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final ringRatios = [0.5, 0.75, 1.0];
    for (final ratio in ringRatios) {
      final radius = ratio * coordinateScale;
      canvas.drawCircle(center, radius, gridPaint);

      // Decimal labels along X-axis
      final textSpan = TextSpan(
        text: ratio.toStringAsFixed(2),
        style: GoogleFonts.jetBrainsMono(
          color: greyColor.withValues(alpha: 0.35),
          fontSize: 8,
        ),
      );
      TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )
        ..layout()
        ..paint(canvas, Offset(center.dx + radius + 4, center.dy - 10));
    }

    // 2. Draw Distorted Space Grid Lines
    final linePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    const gridRowsCols = 16;
    final rowSpacing = size.height / gridRowsCols;
    final colSpacing = size.width / gridRowsCols;

    // Distort horizontal lines
    for (var r = 0; r <= gridRowsCols; r++) {
      final path = Path();
      final y = r * rowSpacing;

      for (var c = 0; c <= 40; c++) {
        final x = c * (size.width / 40);
        var point = Offset(x, y);

        // Apply grid distortion math from touch gravity well
        final touch = touchPosition;
        if (touch != null) {
          final touchPixel = Offset(
            center.dx + touch.dx * coordinateScale,
            center.dy + touch.dy * coordinateScale,
          );
          final toTouch = touchPixel - point;
          final dist = toTouch.distance;
          if (dist < 180 && dist > 1) {
            final warpForce = 45.0 * (1.0 - dist / 180);
            point += toTouch / dist * warpForce;
          }
        }

        if (c == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Distort vertical lines
    for (var col = 0; col <= gridRowsCols; col++) {
      final path = Path();
      final x = col * colSpacing;

      for (var r = 0; r <= 40; r++) {
        final y = r * (size.height / 40);
        var point = Offset(x, y);

        final touch = touchPosition;
        if (touch != null) {
          final touchPixel = Offset(
            center.dx + touch.dx * coordinateScale,
            center.dy + touch.dy * coordinateScale,
          );
          final toTouch = touchPixel - point;
          final dist = toTouch.distance;
          if (dist < 180 && dist > 1) {
            final warpForce = 45.0 * (1.0 - dist / 180);
            point += toTouch / dist * warpForce;
          }
        }

        if (r == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // 3. Touch Snapping Bounds
    final touch = touchPosition;
    if (touch != null) {
      final touchPixel = Offset(
        center.dx + touch.dx * coordinateScale,
        center.dy + touch.dy * coordinateScale,
      );
      final pulseRadius =
          (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0 * 100.0;
      final touchRingPaint = Paint()
        ..color = accentColor.withValues(
          alpha: 0.25 * (1.0 - pulseRadius / 100.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      canvas
        ..drawCircle(touchPixel, pulseRadius, touchRingPaint)
        ..drawCircle(
          touchPixel,
          40,
          touchRingPaint..color = accentColor.withValues(alpha: 0.1),
        );
    }

    // 4. Draw Center Pulsing Node • (You)
    final youPixel = center;
    final pulsePaint = Paint()
      ..color = whiteColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Pulsing circle glow
    canvas.drawCircle(youPixel, 18, pulsePaint);

    final innerPaint = Paint()
      ..color = whiteColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(youPixel, 4, innerPaint);

    final youLabelSpan = TextSpan(
      text: '• (You)',
      style: GoogleFonts.inter(
        color: whiteColor,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
    TextPainter(
        text: youLabelSpan,
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(canvas, Offset(youPixel.dx - 18, youPixel.dy - 20));

    // 5. Draw Floating Vector Nodes (Spaced out layout with mode-specific icons)
    for (final node in nodes) {
      final nodePixel = Offset(
        center.dx + node.position.dx * coordinateScale,
        center.dy + node.position.dy * coordinateScale,
      );

      // Node background connection path line
      final connPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.1)
        ..strokeWidth = 0.5;
      canvas.drawLine(center, nodePixel, connPaint);

      // Dynamic Node Icon selection based on type (simultaneous orbit)
      IconData nodeIcon;
      Color iconColor;

      final nodeType = node.type ?? (nodes.indexOf(node) % 3);
      if (nodeType == 0) {
        nodeIcon = Icons.favorite;
        iconColor = const Color(0xFFFF5A5F); // Crimson Red for Hearts/Dating
      } else if (nodeType == 1) {
        nodeIcon = Icons.auto_awesome;
        iconColor = const Color(0xFFFFB03A); // Teal for Sparkles/Friends
      } else {
        nodeIcon = Icons.work;
        iconColor = const Color(0xFFFFFFFF); // White for briefcase/Pro
      }

      // Slightly larger icon fonts (20.0 size) for clear readability
      final iconSpan = TextSpan(
        text: String.fromCharCode(nodeIcon.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: nodeIcon.fontFamily,
          package: nodeIcon.fontPackage,
          color: iconColor.withValues(alpha: 0.8),
          shadows: [
            Shadow(
              color: iconColor.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
      );

      final iconPainter = TextPainter(
        text: iconSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // Paint centered icon on nodePixel
      iconPainter.paint(
        canvas,
        nodePixel - Offset(iconPainter.width / 2, iconPainter.height / 2),
      );

      // Spaced-out Label and Compatibility score text to avoid overlaps
      final textSpan = TextSpan(
        text: 'o (${node.score.toStringAsFixed(2)})',
        style: GoogleFonts.jetBrainsMono(
          color: whiteColor.withValues(alpha: 0.55),
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      );
      final nodePainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // Dynamically position text on outer side relative to node vector path from center
      final textOffsetDir = node.position / node.position.distance;
      final textX =
          nodePixel.dx +
          (textOffsetDir.dx * 16) -
          (node.position.dx < 0 ? nodePainter.width - 4 : 0);
      final textY = nodePixel.dy + (textOffsetDir.dy * 12) - 6;

      nodePainter.paint(canvas, Offset(textX, textY));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GravityFieldPainter oldDelegate) {
    // simulatedTime advances every physics tick, so this still repaints on
    // essentially every real animation frame — but unlike a blanket `true`,
    // it skips repainting if this painter is reconstructed with identical
    // field values for an unrelated rebuild.
    return oldDelegate.simulatedTime != simulatedTime ||
        oldDelegate.touchPosition != touchPosition ||
        oldDelegate.tiltOffset != tiltOffset ||
        oldDelegate.matrixIndex != matrixIndex ||
        oldDelegate.nodes != nodes;
  }
}

// Optical Chromatic Border Dispersion (Real Lens Effect) CustomPainter
class ChromaticBorderPainter extends CustomPainter {
  ChromaticBorderPainter({required this.borderRadius});

  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );

    // Path 1 (Left offset): Hyper-muted Crimson Red (#FF5A5F, opacity 20%)
    final paintRed = Paint()
      ..color = const Color(0x33FF5A5F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas
      ..save()
      ..translate(-0.3, 0)
      ..drawRRect(rrect, paintRed)
      ..restore();

    // Path 2 (Right offset): Pure Oracle Aqua/Teal (#00ADB5, opacity 25%)
    final paintTeal = Paint()
      ..color = const Color(0x4000ADB5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas
      ..save()
      ..translate(0.3, 0)
      ..drawRRect(rrect, paintTeal)
      ..restore();

    // Path 3 (Absolute center): Mathematical White (#FFFFFF, opacity 60%)
    final paintWhite = Paint()
      ..color = const Color(0x99FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(rrect, paintWhite);
  }

  @override
  bool shouldRepaint(covariant ChromaticBorderPainter oldDelegate) => false;
}
